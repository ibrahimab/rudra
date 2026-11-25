import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:test/test.dart';

/// Verifies typed handler registration, configuration validation
/// and independent application request dispatch.
void main() {
  group('handler registration', () {
    test('registration does not execute the handler', () {
      final handlers = RequestHandlerRegistry();

      handlers.register<_EchoResponse, _EchoRequest>((request, session) {
        fail('Registration must not execute the handler.');
      });

      expect(handlers.is_frozen, isFalse);

      handlers.freeze(codecs: _create_codecs());

      expect(handlers.is_frozen, isTrue);
    });

    test('rejects duplicate request handlers', () {
      final handlers = RequestHandlerRegistry();

      handlers.register<_EchoResponse, _EchoRequest>(
        (request, session) => _EchoResponse(request.value),
      );

      expect(
        () => handlers.register<_EchoResponse, _EchoRequest>(
          (request, session) => _EchoResponse(request.value),
        ),
        throwsStateError,
      );
    });

    test('rejects registration after freezing', () {
      final handlers = RequestHandlerRegistry();

      handlers.freeze(codecs: _create_codecs());

      expect(
        () => handlers.register<_EchoResponse, _EchoRequest>(
          (request, session) => _EchoResponse(request.value),
        ),
        throwsStateError,
      );
    });
  });

  group('configuration validation', () {
    test('rejects mutable codec configuration', () {
      final handlers = RequestHandlerRegistry();
      final codecs = MessageCodecRegistry();

      expect(() => handlers.freeze(codecs: codecs), throwsStateError);

      expect(handlers.is_frozen, isFalse);

      codecs.freeze();
      handlers.freeze(codecs: codecs);

      expect(handlers.is_frozen, isTrue);
    });

    test('rejects handlers without registered request codecs', () {
      final handlers = RequestHandlerRegistry();
      final codecs = MessageCodecRegistry()..freeze();

      handlers.register<_EchoResponse, _EchoRequest>(
        (request, session) => _EchoResponse(request.value),
      );

      expect(() => handlers.freeze(codecs: codecs), throwsStateError);

      expect(handlers.is_frozen, isFalse);
    });

    test('rejects widened handler response configuration', () {
      final handlers = RequestHandlerRegistry();

      // Dart covariance permits this registration, but the
      // concrete codec configuration expects _EchoResponse.
      handlers.register<Response, _EchoRequest>(
        (request, session) => _EchoResponse(request.value),
      );

      expect(() => handlers.freeze(codecs: _create_codecs()), throwsStateError);

      expect(handlers.is_frozen, isFalse);
    });

    test('accepts request codecs without local handlers', () {
      final handlers = RequestHandlerRegistry();

      handlers.freeze(codecs: _create_codecs());

      expect(handlers.is_frozen, isTrue);
    });

    test('repeated freezing preserves validated configuration', () {
      final handlers = RequestHandlerRegistry();
      final codecs = _create_codecs();

      handlers.freeze(codecs: codecs);
      handlers.freeze(codecs: codecs);

      expect(handlers.is_frozen, isTrue);
    });

    test('rejects rebinding to another codec registry', () {
      final handlers = RequestHandlerRegistry();

      handlers.freeze(codecs: _create_codecs());

      expect(() => handlers.freeze(codecs: _create_codecs()), throwsStateError);
    });
  });

  group('request dispatch', () {
    test('dispatch requires frozen handler configuration', () async {
      final handlers = RequestHandlerRegistry();

      await expectLater(
        handlers.dispatch(const _EchoRequest('Hello'), _TestSession()),
        throwsStateError,
      );
    });

    test('delivers a typed request and its authenticated session', () async {
      final handlers = RequestHandlerRegistry();
      final session = _TestSession();
      const request = _EchoRequest('Hello');

      handlers.register<_EchoResponse, _EchoRequest>((
        received_request,
        received_session,
      ) {
        expect(received_request, same(request));
        expect(received_session, same(session));
        expect(received_session.os_user_id, session.os_user_id);

        return _EchoResponse(received_request.value);
      });

      handlers.freeze(codecs: _create_codecs());

      final response = await handlers.dispatch(request, session);

      expect(response, isA<_EchoResponse>());
      expect((response as _EchoResponse).value, 'Hello');
    });

    test('awaits asynchronous application responses', () async {
      final handlers = RequestHandlerRegistry();

      final entered = Completer<void>();
      final result = Completer<_EchoResponse>();

      handlers.register<_EchoResponse, _EchoRequest>((request, session) {
        entered.complete();
        return result.future;
      });

      handlers.freeze(codecs: _create_codecs());

      final pending = handlers.dispatch(
        const _EchoRequest('Hello'),
        _TestSession(),
      );

      await entered.future;

      const expected = _EchoResponse('Hello');
      result.complete(expected);

      expect(await pending, same(expected));
    });

    test('dispatches independent requests concurrently', () async {
      final handlers = RequestHandlerRegistry();

      final first_entered = Completer<void>();
      final second_entered = Completer<void>();

      final first_result = Completer<_EchoResponse>();
      final second_result = Completer<_EchoResponse>();

      const first_value = 'first';
      const second_value = 'second';

      handlers.register<_EchoResponse, _EchoRequest>((request, session) {
        if (request.value == first_value) {
          first_entered.complete();
          return first_result.future;
        }

        expect(request.value, second_value);

        second_entered.complete();
        return second_result.future;
      });

      handlers.freeze(codecs: _create_codecs());

      final session = _TestSession();

      final first = handlers.dispatch(const _EchoRequest(first_value), session);

      await first_entered.future;

      final second = handlers.dispatch(
        const _EchoRequest(second_value),
        session,
      );

      // The second handler must be able to enter while the
      // first application's execution remains outstanding.
      await second_entered.future;

      const expected_second = _EchoResponse(second_value);
      second_result.complete(expected_second);

      expect(await second, same(expected_second));

      const expected_first = _EchoResponse(first_value);
      first_result.complete(expected_first);

      expect(await first, same(expected_first));
    });

    test('returns null when no local handler exists', () async {
      final handlers = RequestHandlerRegistry();

      handlers.freeze(codecs: _create_codecs());

      final response = await handlers.dispatch(
        const _EchoRequest('Hello'),
        _TestSession(),
      );

      expect(response, isNull);
    });

    test('rejects requests missing from codec configuration', () async {
      final handlers = RequestHandlerRegistry();

      handlers.freeze(codecs: _create_codecs());

      await expectLater(
        handlers.dispatch(const _UnregisteredRequest(), _TestSession()),
        throwsArgumentError,
      );
    });

    test('propagates application handler failures unchanged', () async {
      final handlers = RequestHandlerRegistry();
      final failure = StateError('Controlled handler failure.');

      handlers.register<_EchoResponse, _EchoRequest>((request, session) {
        throw failure;
      });

      handlers.freeze(codecs: _create_codecs());

      await expectLater(
        handlers.dispatch(const _EchoRequest('Hello'), _TestSession()),
        throwsA(same(failure)),
      );
    });

    test('rejects an incompatible concrete response subtype', () async {
      final handlers = RequestHandlerRegistry();

      handlers.register<_EchoResponse, _EchoRequest>(
        (request, session) => _DerivedEchoResponse(request.value),
      );

      handlers.freeze(codecs: _create_codecs());

      await expectLater(
        handlers.dispatch(const _EchoRequest('Hello'), _TestSession()),
        throwsStateError,
      );
    });
  });
}

/// Creates frozen codec configuration for the synthetic echo messages.
///
/// Returns a registry containing the concrete request-to-response
/// relationship used by handler registration tests.
MessageCodecRegistry _create_codecs() {
  final codecs = MessageCodecRegistry();

  codecs.register_request<_EchoResponse, _EchoRequest>(
    const _EchoRequestCodec(),
  );

  codecs.register_response<_EchoResponse>(const _EchoResponseCodec());

  codecs.freeze();

  return codecs;
}

/// Synthetic request carrying an arbitrary application value.
///
/// Example:
/// ```dart
/// const request = _EchoRequest('Hello');
/// ```
final class _EchoRequest implements Request<_EchoResponse> {
  /// Creates a request containing [value].
  const _EchoRequest(this.value);

  /// Application value supplied to the handler.
  final String value;
}

/// Synthetic response carrying an application result.
///
/// Example:
/// ```dart
/// const response = _EchoResponse('Hello');
/// ```
class _EchoResponse implements Response {
  /// Creates a response containing [value].
  const _EchoResponse(this.value);

  /// Application result returned by the handler.
  final String value;
}

/// Response subtype used to exercise exact concrete type validation.
///
/// Example:
/// ```dart
/// const response = _DerivedEchoResponse('Hello');
/// ```
final class _DerivedEchoResponse extends _EchoResponse {
  /// Creates a derived response containing [value].
  const _DerivedEchoResponse(super.value);
}

/// Synthetic request deliberately absent from codec configuration.
///
/// Example:
/// ```dart
/// const request = _UnregisteredRequest();
/// ```
final class _UnregisteredRequest implements Request<_EchoResponse> {
  /// Creates an unregistered synthetic request.
  const _UnregisteredRequest();
}

/// Codec for the synthetic echo request.
///
/// Example:
/// ```dart
/// const codec = _EchoRequestCodec();
/// final request = codec.decode('Hello');
/// ```
final class _EchoRequestCodec implements MessageCodec<_EchoRequest> {
  /// Creates the synthetic request codec.
  const _EchoRequestCodec();

  /// Stable wire identity of the synthetic request.
  @override
  String get type_id => 'example.echo.request.v1';

  /// Returns the application value carried by [message].
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

/// Codec for the synthetic echo response.
///
/// Example:
/// ```dart
/// const codec = _EchoResponseCodec();
/// final response = codec.decode('Hello');
/// ```
final class _EchoResponseCodec implements MessageCodec<_EchoResponse> {
  /// Creates the synthetic response codec.
  const _EchoResponseCodec();

  /// Stable wire identity of the synthetic response.
  @override
  String get type_id => 'example.echo.response.v1';

  /// Returns the application result carried by [message].
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

/// Supplies authenticated session context for handler dispatch tests.
///
/// The test session acquires no transport resources. Outgoing
/// requests are outside the responsibility under test.
///
/// Example:
/// ```dart
/// final session = _TestSession();
/// assert(session.os_user_id == 'test-peer');
/// ```
final class _TestSession implements MessageSession {
  /// Creates a synthetic authenticated session.
  _TestSession();

  /// Synthetic trusted identity of the connected peer.
  @override
  String get os_user_id => 'test-peer';

  /// Completion signal for the synthetic session lifecycle.
  final Completer<void> _completion = Completer<void>();

  /// Completes when the synthetic session is closed.
  @override
  Future<void> get done => _completion.future;

  /// Rejects unexpected outgoing [request] execution.
  ///
  /// Throws [UnsupportedError] because outgoing communication
  /// is outside the responsibility of this test fixture.
  @override
  Future<R> request<R extends Response>(Request<R> request) async {
    throw UnsupportedError('Unexpected outgoing request.');
  }

  /// Completes the synthetic session lifecycle.
  ///
  /// Repeated calls return the same completion result.
  @override
  Future<void> close() {
    if (!_completion.isCompleted) {
      _completion.complete();
    }

    return done;
  }
}
