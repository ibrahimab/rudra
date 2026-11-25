import 'package:rudra_communication/rudra_communication.dart';
import 'package:test/test.dart';

/// Verifies typed codec registration, configuration integrity
/// and structured message conversion.
void main() {
  group('registration', () {
    test('new registry remains mutable', () {
      final registry = MessageCodecRegistry();

      expect(registry.is_frozen, isFalse);
    });

    test('registers request and response codecs', () {
      final registry = MessageCodecRegistry();

      registry.register_request<_EchoResponse, _EchoRequest>(
        const _EchoRequestCodec(),
      );

      registry.register_response<_EchoResponse>(const _EchoResponseCodec());

      registry.freeze();

      expect(registry.is_frozen, isTrue);
    });

    test('rejects duplicate concrete message types', () {
      final registry = MessageCodecRegistry();

      registry.register_response<_EchoResponse>(const _EchoResponseCodec());

      expect(
        () => registry.register_response<_EchoResponse>(
          const _EchoResponseCodec(type_id: 'example.alternative.response.v1'),
        ),
        throwsStateError,
      );
    });

    test('rejects duplicate wire identifiers', () {
      final registry = MessageCodecRegistry();

      registry.register_response<_EchoResponse>(const _EchoResponseCodec());

      expect(
        () => registry.register_response<_OtherResponse>(
          const _OtherResponseCodec(type_id: 'example.echo.response.v1'),
        ),
        throwsStateError,
      );

      // Failed registration must not reserve the concrete type.
      registry.register_response<_OtherResponse>(const _OtherResponseCodec());

      registry.freeze();

      expect(
        registry.decode('example.other.response.v1', null),
        isA<_OtherResponse>(),
      );
    });

    test('rejects invalid wire identifiers', () {
      final invalid_identifiers = [
        '',
        ' ',
        'Example.Response',
        'example response',
        'example/response',
        'example.response\n',
        List.filled(129, 'a').join(),
      ];

      for (final identifier in invalid_identifiers) {
        final registry = MessageCodecRegistry();

        expect(
          () => registry.register_response<_EchoResponse>(
            _EchoResponseCodec(type_id: identifier),
          ),
          throwsArgumentError,
          reason: 'Identifier must be rejected: $identifier',
        );
      }
    });
  });

  group('configuration freezing', () {
    test('rejects a missing response registration', () {
      final registry = MessageCodecRegistry();

      registry.register_request<_EchoResponse, _EchoRequest>(
        const _EchoRequestCodec(),
      );

      expect(registry.freeze, throwsStateError);
      expect(registry.is_frozen, isFalse);

      registry.register_response<_EchoResponse>(const _EchoResponseCodec());

      registry.freeze();

      expect(registry.is_frozen, isTrue);
    });

    test('rejects further request registrations', () {
      final registry = _create_registry();

      expect(
        () => registry.register_request<_EchoResponse, _EchoRequest>(
          const _EchoRequestCodec(),
        ),
        throwsStateError,
      );
    });

    test('rejects further response registrations', () {
      final registry = _create_registry();

      expect(
        () => registry.register_response<_OtherResponse>(
          const _OtherResponseCodec(),
        ),
        throwsStateError,
      );
    });

    test('repeated freezing preserves configuration', () {
      final registry = _create_registry();

      registry.freeze();

      expect(registry.is_frozen, isTrue);
    });

    test('message processing requires frozen configuration', () {
      final registry = MessageCodecRegistry();

      registry.register_request<_EchoResponse, _EchoRequest>(
        const _EchoRequestCodec(),
      );

      registry.register_response<_EchoResponse>(const _EchoResponseCodec());

      expect(
        () => registry.encode(const _EchoRequest('Hello')),
        throwsStateError,
      );

      expect(
        () => registry.decode('example.echo.response.v1', 'Hello'),
        throwsStateError,
      );

      expect(
        () => registry.response_type_for(const _EchoRequest('Hello')),
        throwsStateError,
      );
    });
  });

  group('typed message conversion', () {
    test('encodes and decodes a request', () {
      final registry = _create_registry();

      final encoded = registry.encode(const _EchoRequest('Hello'));

      expect(encoded.type_id, 'example.echo.request.v1');
      expect(encoded.payload, 'Hello');

      final decoded = registry.decode(encoded.type_id, encoded.payload);

      expect(decoded, isA<_EchoRequest>());
      expect((decoded as _EchoRequest).value, 'Hello');
    });

    test('encodes and decodes a response', () {
      final registry = _create_registry();

      final encoded = registry.encode(const _EchoResponse('Hello'));

      expect(encoded.type_id, 'example.echo.response.v1');
      expect(encoded.payload, 'Hello');

      final decoded = registry.decode(encoded.type_id, encoded.payload);

      expect(decoded, isA<_EchoResponse>());
      expect((decoded as _EchoResponse).value, 'Hello');
    });

    test('preserves the registered concrete response type', () {
      final registry = _create_registry();

      // Deliberately widen the request reference.
      const Request<Response> request = _EchoRequest('Hello');

      expect(registry.response_type_for(request), _EchoResponse);
    });

    test('rejects unregistered outgoing message types', () {
      final registry = _create_registry();

      expect(
        () => registry.encode(const _OtherResponse()),
        throwsArgumentError,
      );
    });

    test('rejects unknown incoming wire identifiers', () {
      final registry = _create_registry();

      expect(
        () => registry.decode('example.unknown.response.v1', null),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed request payloads', () {
      final registry = _create_registry();

      expect(
        () => registry.decode('example.echo.request.v1', 42),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed response payloads', () {
      final registry = _create_registry();

      expect(
        () => registry.decode('example.echo.response.v1', null),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a codec violating its concrete type contract', () {
      final registry = MessageCodecRegistry();

      registry.register_response<Response>(const _BroadResponseCodec());

      registry.freeze();

      expect(
        () => registry.decode('example.broad.response.v1', null),
        throwsStateError,
      );
    });
  });
}

/// Creates a frozen registry containing the synthetic echo messages.
///
/// Returns validated configuration ready for message conversion.
MessageCodecRegistry _create_registry() {
  final registry = MessageCodecRegistry();

  registry.register_request<_EchoResponse, _EchoRequest>(
    const _EchoRequestCodec(),
  );

  registry.register_response<_EchoResponse>(const _EchoResponseCodec());

  registry.freeze();

  return registry;
}

/// Synthetic request carrying an arbitrary string.
final class _EchoRequest implements Request<_EchoResponse> {
  /// Creates a request containing [value].
  const _EchoRequest(this.value);

  /// Application value carried by the request.
  final String value;
}

/// Synthetic response carrying the echoed string.
final class _EchoResponse implements Response {
  /// Creates a response containing [value].
  const _EchoResponse(this.value);

  /// Application value carried by the response.
  final String value;
}

/// Independent response used to verify registration isolation.
final class _OtherResponse implements Response {
  /// Creates an empty synthetic response.
  const _OtherResponse();
}

/// Codec for the synthetic echo request.
final class _EchoRequestCodec implements MessageCodec<_EchoRequest> {
  /// Creates the synthetic request codec.
  const _EchoRequestCodec();

  /// Stable wire identity of the synthetic request.
  @override
  String get type_id => 'example.echo.request.v1';

  /// Returns the string carried by [message].
  @override
  Object? encode(_EchoRequest message) => message.value;

  /// Reconstructs a request from [payload].
  ///
  /// Throws [FormatException] for non-string payloads.
  @override
  _EchoRequest decode(Object? payload) {
    if (payload is! String) {
      throw const FormatException('Invalid request payload.');
    }

    return _EchoRequest(payload);
  }
}

/// Codec for the synthetic echo response.
final class _EchoResponseCodec implements MessageCodec<_EchoResponse> {
  /// Creates a response codec with the supplied [type_id].
  const _EchoResponseCodec({this.type_id = 'example.echo.response.v1'});

  /// Configurable identifier used to exercise registration validation.
  @override
  final String type_id;

  /// Returns the string carried by [message].
  @override
  Object? encode(_EchoResponse message) => message.value;

  /// Reconstructs a response from [payload].
  ///
  /// Throws [FormatException] for non-string payloads.
  @override
  _EchoResponse decode(Object? payload) {
    if (payload is! String) {
      throw const FormatException('Invalid response payload.');
    }

    return _EchoResponse(payload);
  }
}

/// Codec for the independent synthetic response.
final class _OtherResponseCodec implements MessageCodec<_OtherResponse> {
  /// Creates a codec with the supplied [type_id].
  const _OtherResponseCodec({this.type_id = 'example.other.response.v1'});

  /// Configurable identifier used to verify registration conflicts.
  @override
  final String type_id;

  /// Encodes [message] as an empty payload.
  @override
  Object? encode(_OtherResponse message) => null;

  /// Reconstructs the independent response from [payload].
  ///
  /// Throws [FormatException] for non-null payloads.
  @override
  _OtherResponse decode(Object? payload) {
    if (payload != null) {
      throw const FormatException('Invalid response payload.');
    }

    return const _OtherResponse();
  }
}

/// Deliberately invalid codec registered against an abstract response.
///
/// Exercises exact concrete type validation at the registry boundary.
final class _BroadResponseCodec implements MessageCodec<Response> {
  /// Creates the deliberately broad codec.
  const _BroadResponseCodec();

  /// Stable identifier of the invalid test registration.
  @override
  String get type_id => 'example.broad.response.v1';

  /// Returns an empty representation of [message].
  @override
  Object? encode(Response message) => null;

  /// Returns a concrete subtype rather than the registered type.
  @override
  Response decode(Object? payload) => const _OtherResponse();
}
