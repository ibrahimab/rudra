import 'dart:async';
import 'dart:typed_data';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_communication/src/messaging/protocol/json_envelope_encoding.dart';
import 'package:rudra_communication/src/messaging/protocol/length_prefixed_framing.dart';
import 'package:rudra_communication/src/messaging/protocol/message_envelope.dart';
import 'package:rudra_communication/src/sessions/default_message_session.dart';
import 'package:rudra_communication/src/sessions/message_session_options.dart';
import 'package:test/test.dart';

/// Verifies integrated object-level communication over substituted
/// authenticated transport connections.
void main() {
  late List<DefaultMessageSession> sessions;

  setUp(() {
    sessions = [];
  });

  tearDown(() async {
    await Future.wait(sessions.map((session) => session.close()));
  });

  /// Opens and retains a session using synthetic messaging configuration.
  ///
  /// [connection] supplies the substituted authenticated transport.
  /// [handler] optionally handles incoming synthetic requests.
  /// [options] supplies execution limits for the session.
  ///
  /// Returns an executing session retained for test cleanup.
  DefaultMessageSession open_session(
    _MemoryConnection connection, {
    RequestHandler<_EchoResponse, _EchoRequest>? handler,
    MessageSessionOptions options = const MessageSessionOptions(),
  }) {
    final codecs = _create_codecs();
    final handlers = RequestHandlerRegistry();

    if (handler != null) {
      handlers.register<_EchoResponse, _EchoRequest>(handler);
    }

    handlers.freeze(codecs: codecs);

    final session = DefaultMessageSession.open(
      connection: connection,
      codecs: codecs,
      handlers: handlers,
      options: options,
    );

    sessions.add(session);

    return session;
  }

  group('typed message delivery', () {
    test('exchanges typed requests and responses', () async {
      final pair = _create_pair();

      final left = open_session(pair.left);

      open_session(
        pair.right,
        handler: (request, session) {
          expect(session.os_user_id, 'left-peer');

          return _EchoResponse(request.value);
        },
      );

      expect(left.os_user_id, 'right-peer');

      // No explicit generic argument or response cast is required.
      final response = await left.request(const _EchoRequest('Hello'));

      expect(response.value, 'Hello');
    });

    test('supports simultaneous requests in both directions', () async {
      final pair = _create_pair();

      final left_entered = Completer<void>();
      final right_entered = Completer<void>();

      final left = open_session(
        pair.left,
        handler: (request, session) async {
          left_entered.complete();

          await right_entered.future;

          return _EchoResponse('left:${request.value}');
        },
      );

      final right = open_session(
        pair.right,
        handler: (request, session) async {
          right_entered.complete();

          await left_entered.future;

          return _EchoResponse('right:${request.value}');
        },
      );

      final from_left = left.request(const _EchoRequest('one'));

      final from_right = right.request(const _EchoRequest('two'));

      expect((await from_left).value, 'right:one');
      expect((await from_right).value, 'left:two');
    });

    test('processes nested requests without blocking responses', () async {
      final pair = _create_pair();

      final left = open_session(
        pair.left,
        handler: (request, session) {
          return _EchoResponse('nested:${request.value}');
        },
      );

      open_session(
        pair.right,
        handler: (request, session) async {
          final nested = await session.request(_EchoRequest(request.value));

          return _EchoResponse('outer:${nested.value}');
        },
      );

      final response = await left.request(const _EchoRequest('Hello'));

      expect(response.value, 'outer:nested:Hello');
    });

    test('correlates independently completed incoming handlers', () async {
      final pair = _create_pair();

      final first_entered = Completer<void>();
      final second_entered = Completer<void>();

      final first_result = Completer<_EchoResponse>();
      final second_result = Completer<_EchoResponse>();

      final left = open_session(pair.left);

      open_session(
        pair.right,
        handler: (request, session) {
          if (request.value == 'first') {
            first_entered.complete();
            return first_result.future;
          }

          expect(request.value, 'second');

          second_entered.complete();
          return second_result.future;
        },
      );

      final first = left.request(const _EchoRequest('first'));

      await first_entered.future;

      final second = left.request(const _EchoRequest('second'));

      await second_entered.future;

      second_result.complete(const _EchoResponse('second-result'));

      expect((await second).value, 'second-result');

      first_result.complete(const _EchoResponse('first-result'));

      expect((await first).value, 'first-result');
    });
  });

  group('request-local failures', () {
    test('missing handlers preserve bidirectional communication', () async {
      final pair = _create_pair();

      final left = open_session(
        pair.left,
        handler: (request, session) {
          return _EchoResponse(request.value);
        },
      );

      final right = open_session(pair.right);

      await expectLater(
        left.request(const _EchoRequest('unhandled')),
        throwsA(_session_failure(MessageSessionErrorCode.handler_unavailable)),
      );

      final response = await right.request(const _EchoRequest('reverse'));

      expect(response.value, 'reverse');
    });

    test('handler failures are sanitized and preserve the session', () async {
      final pair = _create_pair();

      final left = open_session(pair.left);

      open_session(
        pair.right,
        handler: (request, session) {
          if (request.value == 'fail') {
            throw StateError('Private application diagnostics.');
          }

          return _EchoResponse(request.value);
        },
      );

      await expectLater(
        left.request(const _EchoRequest('fail')),
        throwsA(_session_failure(MessageSessionErrorCode.handler_failed)),
      );

      final failure = await _decode_frame(pair.right.sent.single);

      expect(failure.kind, MessageKind.error);
      expect(failure.payload, {'code': 'handler_failed'});

      final response = await left.request(const _EchoRequest('still active'));

      expect(response.value, 'still active');
    });

    test('oversized local requests do not terminate communication', () async {
      final pair = _create_pair();

      final left = open_session(
        pair.left,
        options: const MessageSessionOptions(maximum_frame_size: 256),
      );

      open_session(
        pair.right,
        handler: (request, session) {
          return _EchoResponse(request.value);
        },
      );

      await expectLater(
        left.request(_EchoRequest(List.filled(512, 'a').join())),
        throwsA(_protocol_failure(ProtocolErrorCode.invalid_frame_length)),
      );

      expect(pair.left.sent, isEmpty);

      final response = await left.request(const _EchoRequest('valid'));

      expect(response.value, 'valid');
    });

    test('response encoding failures produce sanitized replies', () async {
      final pair = _create_pair();

      final left = open_session(pair.left);

      open_session(
        pair.right,
        options: const MessageSessionOptions(maximum_frame_size: 256),
        handler: (request, session) {
          if (request.value == 'oversized') {
            return _EchoResponse(List.filled(512, 'a').join());
          }

          return _EchoResponse(request.value);
        },
      );

      await expectLater(
        left.request(const _EchoRequest('oversized')),
        throwsA(_session_failure(MessageSessionErrorCode.handler_failed)),
      );

      final response = await left.request(const _EchoRequest('valid'));

      expect(response.value, 'valid');
    });

    test('rejects excess outgoing requests locally', () async {
      final pair = _create_pair();

      final entered = Completer<void>();
      final release = Completer<_EchoResponse>();

      final left = open_session(
        pair.left,
        options: const MessageSessionOptions(maximum_pending: 1),
      );

      open_session(
        pair.right,
        handler: (request, session) {
          if (request.value == 'first') {
            entered.complete();

            return release.future;
          }

          return _EchoResponse(request.value);
        },
      );

      final first = left.request(const _EchoRequest('first'));

      await entered.future;

      await expectLater(
        left.request(const _EchoRequest('excess')),
        throwsA(_session_failure(MessageSessionErrorCode.capacity_exceeded)),
      );

      release.complete(const _EchoResponse('first-result'));

      expect((await first).value, 'first-result');

      final next = await left.request(const _EchoRequest('next'));

      expect(next.value, 'next');
    });

    test(
      'rejects local submission when writer capacity is exhausted',
      () async {
        final connection = _MemoryConnection(os_user_id: 'test-peer');

        final entered = Completer<void>();
        final release = Completer<void>();

        connection.send_hook = (_) async {
          entered.complete();

          await release.future;
        };

        final session = open_session(
          connection,
          options: const MessageSessionOptions(maximum_outstanding: 1),
        );

        final first = session.request(const _EchoRequest('first'));

        await entered.future;

        await expectLater(
          session.request(const _EchoRequest('excess')),
          throwsA(_session_failure(MessageSessionErrorCode.capacity_exceeded)),
        );

        release.complete();

        connection.inject(
          _frame(
            kind: MessageKind.response,
            request_id: '1',
            message_type: _echo_response_id,
            payload: 'first-result',
          ),
        );

        expect((await first).value, 'first-result');
        expect(connection.close_calls, 0);
      },
    );
  });

  group('protocol failure isolation', () {
    final invalid_responses = [
      (
        description: 'unknown correlation identifier',
        request_id: '2',
        message_type: _echo_response_id,
        payload: 'unknown',
        code: ProtocolErrorCode.invalid_correlation,
      ),
      (
        description: 'incompatible concrete response',
        request_id: '1',
        message_type: _other_response_id,
        payload: null,
        code: ProtocolErrorCode.invalid_message,
      ),
      (
        description: 'unknown message type',
        request_id: '1',
        message_type: 'example.unknown.response.v1',
        payload: null,
        code: ProtocolErrorCode.invalid_message,
      ),
      (
        description: 'malformed application payload',
        request_id: '1',
        message_type: _echo_response_id,
        payload: 42,
        code: ProtocolErrorCode.invalid_message,
      ),
      (
        description: 'request object in a response envelope',
        request_id: '1',
        message_type: _echo_request_id,
        payload: 'wrong-category',
        code: ProtocolErrorCode.invalid_message,
      ),
    ];

    for (final scenario in invalid_responses) {
      test('terminates on ${scenario.description}', () async {
        final connection = _MemoryConnection(os_user_id: 'test-peer');

        final transmitted = Completer<void>();

        connection.send_hook = (_) async {
          transmitted.complete();
        };

        final session = open_session(connection);

        final request = session.request(const _EchoRequest('Hello'));

        final request_failed = expectLater(
          request,
          throwsA(_protocol_failure(scenario.code)),
        );

        final session_failed = expectLater(
          session.done,
          throwsA(_protocol_failure(scenario.code)),
        );

        await transmitted.future;

        connection.inject(
          _frame(
            kind: MessageKind.response,
            request_id: scenario.request_id,
            message_type: scenario.message_type,
            payload: scenario.payload,
          ),
        );

        await Future.wait([request_failed, session_failed]);

        await session.close();

        expect(connection.close_calls, 1);
      });
    }

    test('rejects duplicate responses', () async {
      final connection = _MemoryConnection(os_user_id: 'test-peer');

      final transmitted = Completer<void>();

      connection.send_hook = (_) async {
        transmitted.complete();
      };

      final session = open_session(connection);

      final request = session.request(const _EchoRequest('Hello'));

      await transmitted.future;

      final response_frame = _frame(
        kind: MessageKind.response,
        request_id: '1',
        message_type: _echo_response_id,
        payload: 'Hello',
      );

      connection.inject(response_frame);

      expect((await request).value, 'Hello');

      final failed = expectLater(
        session.done,
        throwsA(_protocol_failure(ProtocolErrorCode.invalid_correlation)),
      );

      connection.inject(response_frame);

      await failed;
    });

    test('rejects duplicate incoming requests without redispatch', () async {
      final connection = _MemoryConnection(os_user_id: 'test-peer');

      final entered = Completer<void>();
      final release = Completer<_EchoResponse>();

      var invocation_count = 0;

      final session = open_session(
        connection,
        handler: (request, session) {
          invocation_count++;

          entered.complete();

          return release.future;
        },
      );

      final request_frame = _frame(
        kind: MessageKind.request,
        request_id: '1',
        message_type: _echo_request_id,
        payload: 'Hello',
      );

      connection.inject(request_frame);

      await entered.future;

      final failed = expectLater(
        session.done,
        throwsA(_protocol_failure(ProtocolErrorCode.invalid_correlation)),
      );

      connection.inject(request_frame);

      await failed;

      release.complete(const _EchoResponse('Hello'));

      await session.handlers_done;

      expect(invocation_count, 1);
      expect(connection.sent, isEmpty);
    });

    test('terminates when incoming execution capacity is exhausted', () async {
      final connection = _MemoryConnection(os_user_id: 'test-peer');

      final entered = Completer<void>();
      final release = Completer<_EchoResponse>();

      var invocation_count = 0;

      final session = open_session(
        connection,
        options: const MessageSessionOptions(maximum_incoming: 1),
        handler: (request, session) {
          invocation_count++;

          entered.complete();

          return release.future;
        },
      );

      connection.inject(
        _frame(
          kind: MessageKind.request,
          request_id: '1',
          message_type: _echo_request_id,
          payload: 'first',
        ),
      );

      await entered.future;

      final failed = expectLater(
        session.done,
        throwsA(_protocol_failure(ProtocolErrorCode.capacity_exceeded)),
      );

      connection.inject(
        _frame(
          kind: MessageKind.request,
          request_id: '2',
          message_type: _echo_request_id,
          payload: 'excess',
        ),
      );

      await failed;

      release.complete(const _EchoResponse('first-result'));

      await session.handlers_done;

      expect(invocation_count, 1);
      expect(connection.sent, isEmpty);
    });

    test('reports an incomplete frame on peer disconnection', () async {
      final connection = _MemoryConnection(os_user_id: 'test-peer');

      final session = open_session(connection);

      final failed = expectLater(
        session.done,
        throwsA(_protocol_failure(ProtocolErrorCode.incomplete_frame)),
      );

      // Only part of the four-byte framing header arrives.
      connection.inject(Uint8List.fromList([0, 0]));

      connection.finish_input();

      await failed;
    });
  });

  group('session lifecycle', () {
    test(
      'disconnection does not cancel admitted application handlers',
      () async {
        final pair = _create_pair();

        final entered = Completer<void>();
        final release = Completer<_EchoResponse>();

        final left = open_session(pair.left);

        final right = open_session(
          pair.right,
          handler: (request, session) {
            entered.complete();

            return release.future;
          },
        );

        final request = left.request(const _EchoRequest('Hello'));

        final failed = expectLater(
          request,
          throwsA(_session_failure(MessageSessionErrorCode.session_closed)),
        );

        await entered.future;

        var handlers_drained = false;

        final drained = right.handlers_done.then<void>((_) {
          handlers_drained = true;
        });

        await left.close();
        await right.done;
        await failed;

        expect(handlers_drained, isFalse);

        release.complete(const _EchoResponse('completed'));

        await drained;

        expect(handlers_drained, isTrue);
        expect(pair.right.sent, isEmpty);
      },
    );

    test('an application handler can close its own session', () async {
      final pair = _create_pair();

      final handler_completed = Completer<void>();

      final left = open_session(pair.left);

      final right = open_session(
        pair.right,
        handler: (request, session) async {
          await session.close();

          handler_completed.complete();

          return const _EchoResponse('closed');
        },
      );

      await expectLater(
        left.request(const _EchoRequest('close')),
        throwsA(_session_failure(MessageSessionErrorCode.session_closed)),
      );

      await handler_completed.future;
      await right.done;
      await right.handlers_done;

      expect(pair.right.sent, isEmpty);
    });

    test('request deadlines remain effective during stalled writes', () async {
      final connection = _MemoryConnection(os_user_id: 'test-peer');

      final entered = Completer<void>();

      var write_settled = false;

      connection.send_hook = (_) async {
        entered.complete();

        await connection.closed;

        write_settled = true;

        throw StateError('Transport closed during transmission.');
      };

      final session = open_session(connection);

      late _ControlledTimer deadline;

      final request = runZoned(
        () => session.request(const _EchoRequest('Hello')),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            deadline = _ControlledTimer(callback);

            return deadline;
          },
        ),
      );

      final request_failed = expectLater(
        request,
        throwsA(_session_failure(MessageSessionErrorCode.request_timeout)),
      );

      final session_failed = expectLater(
        session.done,
        throwsA(_session_failure(MessageSessionErrorCode.request_timeout)),
      );

      await entered.future;

      deadline.fire();

      await Future.wait([request_failed, session_failed]);

      await session.close();

      expect(write_settled, isTrue);
      expect(connection.close_calls, 1);
    });

    test(
      'transport read failures propagate without reclassification',
      () async {
        final connection = _MemoryConnection(os_user_id: 'test-peer');

        final session = open_session(connection);

        final failure = StateError('Controlled transport read failure.');

        final request_failed = expectLater(
          session.request(const _EchoRequest('Hello')),
          throwsA(same(failure)),
        );

        final session_failed = expectLater(
          session.done,
          throwsA(same(failure)),
        );

        connection.inject_error(failure);

        await Future.wait([request_failed, session_failed]);

        await session.close();
      },
    );

    test('transport write failures terminate outstanding requests', () async {
      final connection = _MemoryConnection(os_user_id: 'test-peer');

      final failure = StateError('Controlled transport write failure.');

      connection.send_hook = (_) async {
        throw failure;
      };

      final session = open_session(connection);

      final session_failed = expectLater(session.done, throwsA(same(failure)));

      await expectLater(
        session.request(const _EchoRequest('Hello')),
        throwsA(same(failure)),
      );

      await session_failed;
      await session.close();

      expect(connection.close_calls, 1);
    });

    test('repeated close operations retain the same disposal result', () async {
      final connection = _MemoryConnection(os_user_id: 'test-peer');

      final session = open_session(connection);

      final first = session.close();
      final second = session.close();

      expect(second, same(first));

      await first;
      await session.done;
      await session.handlers_done;

      expect(connection.close_calls, 1);

      await expectLater(
        session.request(const _EchoRequest('closed')),
        throwsA(_session_failure(MessageSessionErrorCode.session_closed)),
      );
    });

    test(
      'resource disposal failures remain independently observable',
      () async {
        final failure = StateError('Controlled disposal failure.');

        final connection = _MemoryConnection(
          os_user_id: 'test-peer',
          close_failure: failure,
        );

        final session = open_session(connection);

        // This test explicitly owns verification of failed disposal.
        sessions.remove(session);

        final session_failed = expectLater(
          session.done,
          throwsA(same(failure)),
        );

        final first = session.close();
        final second = session.close();

        expect(second, same(first));

        await expectLater(first, throwsA(same(failure)));

        await session_failed;
        await session.handlers_done;

        expect(connection.close_calls, 1);
      },
    );
  });
}

/// Stable wire identifier of the synthetic echo request.
const String _echo_request_id = 'example.echo.request.v1';

/// Stable wire identifier of the synthetic echo response.
const String _echo_response_id = 'example.echo.response.v1';

/// Stable wire identifier of an independent response.
const String _other_response_id = 'example.other.response.v1';

/// Creates frozen codec configuration for synthetic session messages.
///
/// Returns the request, associated response and independent
/// response registrations used by the integrated session tests.
MessageCodecRegistry _create_codecs() {
  final codecs = MessageCodecRegistry();

  codecs.register_request<_EchoResponse, _EchoRequest>(
    const _EchoRequestCodec(),
  );

  codecs.register_response<_EchoResponse>(const _EchoResponseCodec());

  codecs.register_response<_OtherResponse>(const _OtherResponseCodec());

  codecs.freeze();

  return codecs;
}

/// Creates two independently owned, connected memory transports.
///
/// Returns both endpoints with their respective remote peer identities.
({_MemoryConnection left, _MemoryConnection right}) _create_pair() {
  final left = _MemoryConnection(os_user_id: 'right-peer');
  final right = _MemoryConnection(os_user_id: 'left-peer');

  left.peer = right;
  right.peer = left;

  return (left: left, right: right);
}

/// Creates an encoded protocol frame for the supplied message metadata.
///
/// [kind] identifies its delivery semantics.
/// [request_id] identifies its communication correlation.
/// [message_type] identifies the registered wire representation.
/// [payload] supplies the encoded application data.
///
/// Returns a complete frame suitable for transport injection.
Uint8List _frame({
  required MessageKind kind,
  required String request_id,
  required String message_type,
  required Object? payload,
}) {
  final envelope = MessageEnvelope(
    kind: kind,
    request_id: request_id,
    message_type: message_type,
    payload: payload,
  );

  return LengthPrefixedFraming().encode(
    const JsonEnvelopeEncoding().encode(envelope),
  );
}

/// Decodes the supplied complete [frame].
///
/// Returns its validated communication envelope.
Future<MessageEnvelope> _decode_frame(Uint8List frame) async {
  final payload = await LengthPrefixedFraming()
      .decode(Stream.value(frame))
      .single;

  return const JsonEnvelopeEncoding().decode(payload);
}

/// Returns a matcher for the supplied session failure [code].
Matcher _session_failure(MessageSessionErrorCode code) {
  return isA<MessageSessionException>().having(
    (error) => error.code,
    'code',
    code,
  );
}

/// Returns a matcher for the supplied protocol failure [code].
Matcher _protocol_failure(ProtocolErrorCode code) {
  return isA<ProtocolException>().having((error) => error.code, 'code', code);
}

/// Synthetic application request carrying an arbitrary string.
///
/// Example:
/// ```dart
/// const request = _EchoRequest('Hello');
/// ```
final class _EchoRequest implements Request<_EchoResponse> {
  /// Creates a request containing [value].
  const _EchoRequest(this.value);

  /// Synthetic application data.
  final String value;
}

/// Synthetic application response carrying an arbitrary string.
///
/// Example:
/// ```dart
/// const response = _EchoResponse('Hello');
/// ```
final class _EchoResponse implements Response {
  /// Creates a response containing [value].
  const _EchoResponse(this.value);

  /// Synthetic application result.
  final String value;
}

/// Independent response used for incompatible response testing.
///
/// Example:
/// ```dart
/// const response = _OtherResponse();
/// ```
final class _OtherResponse implements Response {
  /// Creates an empty synthetic response.
  const _OtherResponse();
}

/// Converts synthetic echo requests to and from string payloads.
///
/// Example:
/// ```dart
/// const codec = _EchoRequestCodec();
/// final request = codec.decode('Hello');
/// ```
final class _EchoRequestCodec implements MessageCodec<_EchoRequest> {
  /// Creates the synthetic request codec.
  const _EchoRequestCodec();

  /// Stable wire identifier of the request.
  @override
  String get type_id => _echo_request_id;

  /// Returns the string carried by [message].
  @override
  Object? encode(_EchoRequest message) => message.value;

  /// Reconstructs a request from [payload].
  ///
  /// Throws [FormatException] for non-string payloads.
  @override
  _EchoRequest decode(Object? payload) {
    if (payload is! String) {
      throw const FormatException('Invalid echo request payload.');
    }

    return _EchoRequest(payload);
  }
}

/// Converts synthetic echo responses to and from string payloads.
///
/// Example:
/// ```dart
/// const codec = _EchoResponseCodec();
/// final response = codec.decode('Hello');
/// ```
final class _EchoResponseCodec implements MessageCodec<_EchoResponse> {
  /// Creates the synthetic response codec.
  const _EchoResponseCodec();

  /// Stable wire identifier of the response.
  @override
  String get type_id => _echo_response_id;

  /// Returns the string carried by [message].
  @override
  Object? encode(_EchoResponse message) => message.value;

  /// Reconstructs a response from [payload].
  ///
  /// Throws [FormatException] for non-string payloads.
  @override
  _EchoResponse decode(Object? payload) {
    if (payload is! String) {
      throw const FormatException('Invalid echo response payload.');
    }

    return _EchoResponse(payload);
  }
}

/// Converts the independent synthetic response.
///
/// Example:
/// ```dart
/// const codec = _OtherResponseCodec();
/// final response = codec.decode(null);
/// ```
final class _OtherResponseCodec implements MessageCodec<_OtherResponse> {
  /// Creates the independent response codec.
  const _OtherResponseCodec();

  /// Stable wire identifier of the independent response.
  @override
  String get type_id => _other_response_id;

  /// Returns the empty representation of [message].
  @override
  Object? encode(_OtherResponse message) => null;

  /// Reconstructs the independent response from [payload].
  ///
  /// Throws [FormatException] for non-null payloads.
  @override
  _OtherResponse decode(Object? payload) {
    if (payload != null) {
      throw const FormatException('Invalid independent response payload.');
    }

    return const _OtherResponse();
  }
}

/// Supplies an in-memory authenticated transport connection.
///
/// Supports independently controlled incoming data, outgoing
/// transmission, peer disconnection and disposal failure.
///
/// Example:
/// ```dart
/// final connection = _MemoryConnection(os_user_id: 'peer');
/// connection.inject(Uint8List.fromList([1, 2, 3]));
/// await connection.close();
/// ```
final class _MemoryConnection implements TransportConnection {
  /// Creates a controlled transport with the supplied [os_user_id].
  ///
  /// [close_failure] optionally causes disposal to report failure.
  _MemoryConnection({required this.os_user_id, this.close_failure});

  /// Synthetic authenticated identity of the remote peer.
  @override
  final String os_user_id;

  /// Optional controlled resource disposal failure.
  final Object? close_failure;

  /// Connected peer receiving normally transmitted bytes.
  _MemoryConnection? peer;

  /// Optional substitute for normal outbound transmission.
  Future<void> Function(Uint8List)? send_hook;

  /// Records independent copies of transmitted frames.
  final List<Uint8List> sent = [];

  /// Incoming single-subscription transport stream.
  final StreamController<Uint8List> _input = StreamController<Uint8List>();

  /// Signals the beginning of transport closure.
  final Completer<void> _closed = Completer<void>();

  /// Retains the result of the initial disposal operation.
  Future<void>? _closing;

  /// Number of actual disposal operations.
  int close_calls = 0;

  /// Signals transport termination to controlled active writers.
  Future<void> get closed => _closed.future;

  /// Supplies the controlled incoming byte stream.
  @override
  Stream<Uint8List> get incoming => _input.stream;

  /// Sends an independent copy of [bytes].
  ///
  /// Returns after the controlled transmission capability completes.
  /// Throws [StateError] after transport closure.
  @override
  Future<void> send(Uint8List bytes) async {
    if (_closed.isCompleted) {
      throw StateError('Memory transport is closed.');
    }

    final copy = Uint8List.fromList(bytes);

    sent.add(copy);

    final hook = send_hook;

    if (hook != null) {
      await hook(copy);

      return;
    }

    peer?.inject(copy);
  }

  /// Delivers an independent copy of [bytes] as incoming transport data.
  void inject(Uint8List bytes) {
    _input.add(Uint8List.fromList(bytes));
  }

  /// Delivers a controlled incoming transport [error].
  void inject_error(Object error) {
    _input.addError(error, StackTrace.current);
  }

  /// Signals normal termination of incoming transport data.
  ///
  /// Completion of the stream remains independently observable by
  /// its consumer.
  void finish_input() {
    if (!_input.isClosed) {
      _input.close().ignore();
    }
  }

  /// Terminates the controlled connection.
  ///
  /// Returns the retained disposal result for repeated requests.
  @override
  Future<void> close() => _closing ??= _dispose();

  /// Releases controlled resources and notifies the connected peer.
  ///
  /// Throws the configured disposal failure when present.
  Future<void> _dispose() async {
    close_calls++;

    _closed.complete();

    finish_input();
    peer?.finish_input();

    final failure = close_failure;

    if (failure != null) {
      throw failure;
    }
  }
}

/// Supplies a manually triggered one-shot deadline timer.
///
/// Example:
/// ```dart
/// final timer = _ControlledTimer(handle_expiration);
/// timer.fire();
/// ```
final class _ControlledTimer implements Timer {
  /// Creates an active timer retaining [callback].
  _ControlledTimer(this._callback);

  /// Callback executed on controlled expiration.
  final void Function() _callback;

  /// Whether the timer remains eligible for expiration.
  bool _active = true;

  /// Number of completed timer ticks.
  int _tick = 0;

  /// Whether the timer remains active.
  @override
  bool get isActive => _active;

  /// Number of completed timer ticks.
  @override
  int get tick => _tick;

  /// Prevents subsequent expiration.
  @override
  void cancel() {
    _active = false;
  }

  /// Expires this timer once if it remains active.
  void fire() {
    if (!_active) {
      return;
    }

    _active = false;
    _tick++;

    _callback();
  }
}
