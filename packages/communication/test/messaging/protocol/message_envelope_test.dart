import 'package:rudra_communication/src/messaging/protocol/message_envelope.dart';
import 'package:rudra_communication/src/messaging/protocol/protocol_exception.dart';
import 'package:test/test.dart';

/// Verifies protocol envelope metadata and failure representation.
void main() {
  const request_type = 'example.echo.request.v1';
  const response_type = 'example.echo.response.v1';
  const error_type = 'communication.error.v1';

  final invalid_envelope = isA<ProtocolException>().having(
    (error) => error.code,
    'code',
    ProtocolErrorCode.invalid_envelope,
  );

  test('constructs a request envelope', () {
    final envelope = MessageEnvelope(
      kind: MessageKind.request,
      request_id: '1',
      message_type: request_type,
      payload: {'value': 'Hello'},
    );

    expect(envelope.protocol_version, 1);
    expect(envelope.kind, MessageKind.request);
    expect(envelope.request_id, '1');
    expect(envelope.message_type, request_type);
    expect(envelope.payload, {'value': 'Hello'});
  });

  test('constructs a response containing a null payload', () {
    final envelope = MessageEnvelope(
      kind: MessageKind.response,
      request_id: '1',
      message_type: response_type,
      payload: null,
    );

    expect(envelope.kind, MessageKind.response);
    expect(envelope.payload, isNull);
  });

  test('accepts the maximum request identifier length', () {
    final envelope = MessageEnvelope(
      kind: MessageKind.request,
      request_id: '12345678901234567890',
      message_type: request_type,
      payload: null,
    );

    expect(envelope.request_id.length, 20);
  });

  test('rejects invalid request identifiers', () {
    final identifiers = [
      '',
      '0',
      '01',
      '-1',
      '1.0',
      ' 1',
      '1\n',
      'request-1',
      '123456789012345678901',
    ];

    for (final identifier in identifiers) {
      expect(
        () => MessageEnvelope(
          kind: MessageKind.request,
          request_id: identifier,
          message_type: request_type,
          payload: null,
        ),
        throwsA(invalid_envelope),
        reason: 'Invalid identifier: $identifier',
      );
    }
  });

  test('rejects invalid application message identifiers', () {
    final identifiers = [
      '',
      'Example.Request',
      'example/request',
      'example.request\n',
      List.filled(129, 'a').join(),
      error_type,
    ];

    for (final identifier in identifiers) {
      expect(
        () => MessageEnvelope(
          kind: MessageKind.request,
          request_id: '1',
          message_type: identifier,
          payload: null,
        ),
        throwsA(invalid_envelope),
      );
    }
  });

  test('constructs sanitized request failure envelopes', () {
    for (final code in RequestFailureCode.values) {
      final envelope = MessageEnvelope.failure(request_id: '42', code: code);

      expect(envelope.kind, MessageKind.error);
      expect(envelope.request_id, '42');
      expect(envelope.message_type, error_type);
      expect(envelope.payload, {'code': code.wire_value});
    }
  });

  test('rejects application identifiers on failure envelopes', () {
    expect(
      () => MessageEnvelope(
        kind: MessageKind.error,
        request_id: '1',
        message_type: response_type,
        payload: {'code': 'handler_failed'},
      ),
      throwsA(invalid_envelope),
    );
  });

  test('rejects malformed request failure payloads', () {
    final payloads = <Object?>[
      null,
      'handler_failed',
      <String, Object?>{},
      {'code': 42},
      {'code': 'unknown_failure'},
      {
        'code': 'handler_failed',
        'diagnostic': 'Internal infrastructure failure',
      },
    ];

    for (final payload in payloads) {
      expect(
        () => MessageEnvelope(
          kind: MessageKind.error,
          request_id: '1',
          message_type: error_type,
          payload: payload,
        ),
        throwsA(invalid_envelope),
      );
    }
  });

  test('constructed failure payload cannot be modified', () {
    final envelope = MessageEnvelope.failure(
      request_id: '1',
      code: RequestFailureCode.handler_failed,
    );

    final payload = envelope.payload as Map<String, Object?>;

    expect(
      () => payload['diagnostic'] = 'Internal failure',
      throwsUnsupportedError,
    );
  });
}
