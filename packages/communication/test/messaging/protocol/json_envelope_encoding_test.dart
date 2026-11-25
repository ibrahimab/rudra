import 'dart:convert';
import 'dart:typed_data';

import 'package:rudra_communication/src/messaging/protocol/envelope_encoding.dart';
import 'package:rudra_communication/src/messaging/protocol/json_envelope_encoding.dart';
import 'package:rudra_communication/src/messaging/protocol/message_envelope.dart';
import 'package:rudra_communication/src/messaging/protocol/protocol_exception.dart';
import 'package:test/test.dart';

/// Verifies JSON wire encoding and protocol representation validation.
void main() {
  const EnvelopeEncoding encoding = JsonEnvelopeEncoding();

  final invalid_encoding = isA<ProtocolException>().having(
    (error) => error.code,
    'code',
    ProtocolErrorCode.invalid_encoding,
  );

  final invalid_envelope = isA<ProtocolException>().having(
    (error) => error.code,
    'code',
    ProtocolErrorCode.invalid_envelope,
  );

  final unsupported_version = isA<ProtocolException>().having(
    (error) => error.code,
    'code',
    ProtocolErrorCode.unsupported_version,
  );

  test('encodes the expected JSON wire representation', () {
    final envelope = MessageEnvelope(
      kind: MessageKind.request,
      request_id: '1',
      message_type: 'example.echo.request.v1',
      payload: {'value': 'Hello'},
    );

    final decoded = jsonDecode(utf8.decode(encoding.encode(envelope)));

    expect(decoded, {
      'protocol_version': 1,
      'kind': 'request',
      'request_id': '1',
      'message_type': 'example.echo.request.v1',
      'payload': {'value': 'Hello'},
    });
  });

  test('preserves structured payloads and UTF-8 characters', () {
    final payload = {
      'text': 'こんにちは — café',
      'values': [1, true, null, 2.5],
      'nested': {'key': 'value'},
    };

    final envelope = MessageEnvelope(
      kind: MessageKind.response,
      request_id: '42',
      message_type: 'example.echo.response.v1',
      payload: payload,
    );

    final decoded = encoding.decode(encoding.encode(envelope));

    expect(decoded.kind, MessageKind.response);
    expect(decoded.request_id, '42');
    expect(decoded.message_type, envelope.message_type);
    expect(decoded.payload, payload);
  });

  test('preserves an explicitly null payload', () {
    final envelope = MessageEnvelope(
      kind: MessageKind.response,
      request_id: '1',
      message_type: 'example.empty.response.v1',
      payload: null,
    );

    final decoded = encoding.decode(encoding.encode(envelope));

    expect(decoded.payload, isNull);
  });

  test('preserves a sanitized request failure', () {
    final envelope = MessageEnvelope.failure(
      request_id: '7',
      code: RequestFailureCode.handler_failed,
    );

    final decoded = encoding.decode(encoding.encode(envelope));

    expect(decoded.kind, MessageKind.error);
    expect(decoded.request_id, '7');
    expect(decoded.message_type, 'communication.error.v1');
    expect(decoded.payload, {'code': 'handler_failed'});
  });

  test('rejects malformed UTF-8', () {
    expect(
      () => encoding.decode(Uint8List.fromList([0xff])),
      throwsA(invalid_encoding),
    );
  });

  test('rejects malformed JSON', () {
    expect(
      () => encoding.decode(utf8.encode('{"payload":')),
      throwsA(invalid_encoding),
    );
  });

  test('rejects non-object envelope representations', () {
    for (final value in [null, 42, 'message', <Object?>[]]) {
      expect(
        () => encoding.decode(_encode_json(value)),
        throwsA(invalid_envelope),
      );
    }
  });

  test('rejects unsupported protocol versions', () {
    final fields = _valid_fields();

    fields['protocol_version'] = 2;

    expect(
      () => encoding.decode(_encode_json(fields)),
      throwsA(unsupported_version),
    );
  });

  test('rejects invalid protocol version representations', () {
    for (final version in [null, '1', 1.0, true]) {
      final fields = _valid_fields();

      fields['protocol_version'] = version;

      expect(
        () => encoding.decode(_encode_json(fields)),
        throwsA(invalid_envelope),
      );
    }
  });

  test('rejects missing envelope fields', () {
    for (final field in _valid_fields().keys) {
      final fields = _valid_fields()..remove(field);

      expect(
        () => encoding.decode(_encode_json(fields)),
        throwsA(invalid_envelope),
        reason: 'Missing field: $field',
      );
    }
  });

  test('rejects unexpected envelope fields', () {
    final fields = _valid_fields();

    fields['unexpected'] = true;

    expect(
      () => encoding.decode(_encode_json(fields)),
      throwsA(invalid_envelope),
    );
  });

  test('rejects invalid metadata field types', () {
    for (final field in ['kind', 'request_id', 'message_type']) {
      final fields = _valid_fields();

      fields[field] = 42;

      expect(
        () => encoding.decode(_encode_json(fields)),
        throwsA(invalid_envelope),
      );
    }
  });

  test('rejects unknown message kinds', () {
    final fields = _valid_fields();

    fields['kind'] = 'unknown';

    expect(
      () => encoding.decode(_encode_json(fields)),
      throwsA(invalid_envelope),
    );
  });

  test('rejects invalid request identifiers during decoding', () {
    final fields = _valid_fields();

    fields['request_id'] = '-1';

    expect(
      () => encoding.decode(_encode_json(fields)),
      throwsA(invalid_envelope),
    );
  });

  test('rejects implicit application object serialization', () {
    final envelope = MessageEnvelope(
      kind: MessageKind.request,
      request_id: '1',
      message_type: 'example.echo.request.v1',
      payload: const _ImplicitJsonValue(),
    );

    expect(() => encoding.encode(envelope), throwsA(invalid_encoding));
  });

  test('rejects cyclic structured payloads', () {
    final payload = <Object?>[];

    payload.add(payload);

    final envelope = MessageEnvelope(
      kind: MessageKind.request,
      request_id: '1',
      message_type: 'example.echo.request.v1',
      payload: payload,
    );

    expect(() => encoding.encode(envelope), throwsA(invalid_encoding));
  });

  test('revalidates failure payloads before encoding', () {
    final payload = <String, Object?>{'code': 'handler_failed'};

    final envelope = MessageEnvelope(
      kind: MessageKind.error,
      request_id: '1',
      message_type: 'communication.error.v1',
      payload: payload,
    );

    payload['diagnostic'] = 'Internal failure';

    expect(() => encoding.encode(envelope), throwsA(invalid_envelope));
  });
}

/// Returns an independently mutable, valid version 1 wire envelope.
Map<String, Object?> _valid_fields() => {
  'protocol_version': 1,
  'kind': 'request',
  'request_id': '1',
  'message_type': 'example.echo.request.v1',
  'payload': {'value': 'Hello'},
};

/// Encodes [value] as UTF-8 JSON.
///
/// Returns raw wire bytes for decoder verification.
Uint8List _encode_json(Object? value) => utf8.encode(jsonEncode(value));

/// Synthetic application object with implicit JSON conversion.
///
/// Verifies that encoding cannot bypass explicit message codecs.
///
/// Example:
/// ```dart
/// final value = _ImplicitJsonValue();
/// ```
final class _ImplicitJsonValue {
  /// Creates the synthetic application object.
  const _ImplicitJsonValue();

  /// Returns a representation accepted by ordinary JSON encoding.
  String toJson() => 'Implicit conversion';
}
