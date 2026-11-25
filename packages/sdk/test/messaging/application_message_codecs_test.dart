import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies application messaging composition and feature isolation.
void main() {
  group('feature composition', () {
    test('assembles independent feature messaging capabilities', () {
      final registry = create_application_message_codecs(
        modules: [
          const _TestModule('test.echo', _register_echo),
          const _TestModule('test.label', _register_label),
        ],
      );

      expect(registry.is_frozen, isTrue);

      expect(
        registry.response_type_for(const _EchoRequest('Hello')),
        _EchoResponse,
      );

      expect(
        registry.response_type_for(const _LabelRequest('Example')),
        _LabelResponse,
      );

      final messages = <Message>[
        const _EchoRequest('Hello'),
        const _EchoResponse('World'),
        const _LabelRequest('Example'),
        const _LabelResponse('Label'),
      ];

      for (final message in messages) {
        final encoded = registry.encode(message);
        final decoded = registry.decode(encoded.type_id, encoded.payload);

        expect(decoded.runtimeType, message.runtimeType);
        expect(registry.encode(decoded), encoded);
      }
    });

    test('validates message relationships after all contributions', () {
      final registry = create_application_message_codecs(
        modules: [
          _TestModule('test.request', (registry) {
            registry.register_request<_EchoResponse, _EchoRequest>(
              _echo_request_codec(),
            );
          }),
          _TestModule('test.response', (registry) {
            registry.register_response<_EchoResponse>(_echo_response_codec());
          }),
        ],
      );

      expect(registry.is_frozen, isTrue);

      expect(
        registry.response_type_for(const _EchoRequest('Hello')),
        _EchoResponse,
      );
    });

    test('rejects duplicate module identifiers', () {
      expect(
        () => create_application_message_codecs(
          modules: [
            const _TestModule('test.feature', _register_echo),
            const _TestModule('test.feature', _register_label),
          ],
        ),
        throwsStateError,
      );
    });

    test('rejects blank module identifiers', () {
      for (final module_id in ['', ' ', '\t\n']) {
        expect(
          () => create_application_message_codecs(
            modules: [_TestModule(module_id, _register_echo)],
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects conflicting concrete message types', () {
      expect(
        () => create_application_message_codecs(
          modules: [
            const _TestModule('test.echo', _register_echo),
            _TestModule('test.conflict', (registry) {
              registry.register_response<_EchoResponse>(
                _echo_response_codec(type_id: 'test.conflict.response.v1'),
              );
            }),
          ],
        ),
        throwsStateError,
      );
    });

    test('rejects conflicting wire identifiers', () {
      expect(
        () => create_application_message_codecs(
          modules: [
            const _TestModule('test.echo', _register_echo),
            _TestModule('test.conflict', (registry) {
              registry.register_response<_LabelResponse>(
                _label_response_codec(type_id: 'test.echo.response.v1'),
              );
            }),
          ],
        ),
        throwsStateError,
      );
    });

    test('rejects incomplete request-to-response configuration', () {
      expect(
        () => create_application_message_codecs(
          modules: [
            _TestModule('test.incomplete', (registry) {
              registry.register_request<_EchoResponse, _EchoRequest>(
                _echo_request_codec(),
              );
            }),
          ],
        ),
        throwsStateError,
      );
    });

    test('rejects premature freezing by a contribution', () {
      expect(
        () => create_application_message_codecs(
          modules: [
            _TestModule('test.premature', (registry) {
              _register_echo(registry);
              registry.freeze();
            }),
          ],
        ),
        throwsStateError,
      );
    });
  });

  group('configuration ownership', () {
    test('failed contributions do not contaminate later composition', () {
      final failure = StateError('Simulated contribution failure.');

      expect(
        () => create_application_message_codecs(
          modules: [
            _TestModule('test.feature', (registry) {
              _register_echo(registry);

              throw failure;
            }),
          ],
        ),
        throwsA(same(failure)),
      );

      final registry = create_application_message_codecs(
        modules: [const _TestModule('test.feature', _register_label)],
      );

      expect(registry.is_frozen, isTrue);

      expect(
        registry.response_type_for(const _LabelRequest('Example')),
        _LabelResponse,
      );

      expect(
        () => registry.encode(const _EchoRequest('Hello')),
        throwsArgumentError,
      );
    });

    test('each composition owns an independent registry', () {
      final echo = create_application_message_codecs(
        modules: [const _TestModule('test.echo', _register_echo)],
      );

      final label = create_application_message_codecs(
        modules: [const _TestModule('test.label', _register_label)],
      );

      expect(identical(echo, label), isFalse);

      expect(
        echo.response_type_for(const _EchoRequest('Hello')),
        _EchoResponse,
      );

      expect(
        label.response_type_for(const _LabelRequest('Example')),
        _LabelResponse,
      );

      expect(
        () => echo.encode(const _LabelRequest('Example')),
        throwsArgumentError,
      );

      expect(
        () => label.encode(const _EchoRequest('Hello')),
        throwsArgumentError,
      );
    });

    test('completed configuration rejects further contributions', () {
      final registry = create_application_message_codecs(
        modules: [const _TestModule('test.echo', _register_echo)],
      );

      expect(() => _register_label(registry), throwsStateError);
    });
  });

  group('standard composition', () {
    test('assembles a frozen default configuration', () {
      final registry = create_application_message_codecs();

      expect(registry.is_frozen, isTrue);
    });

    test('accepts an explicitly empty module collection', () {
      final registry = create_application_message_codecs(modules: []);

      expect(registry.is_frozen, isTrue);

      expect(
        () => registry.encode(const _EchoRequest('Hello')),
        throwsArgumentError,
      );
    });

    test('standard module collections are independent', () {
      final first = standard_messaging_modules();
      final second = standard_messaging_modules();
      final original_length = second.length;

      first.add(const _TestModule('test.echo', _register_echo));

      expect(identical(first, second), isFalse);
      expect(second, hasLength(original_length));
    });

    test('standard configuration accepts additional modules', () {
      final registry = create_application_message_codecs(
        modules: [
          ...standard_messaging_modules(),
          const _TestModule('test.echo', _register_echo),
        ],
      );

      expect(registry.is_frozen, isTrue);

      expect(
        registry.response_type_for(const _EchoRequest('Hello')),
        _EchoResponse,
      );
    });
  });
}

/// Synthetic messaging module with an explicit contribution callback.
final class _TestModule implements ApplicationMessagingModule {
  /// Creates a module with [module_id] and its [contribute] callback.
  const _TestModule(this.module_id, this.contribute);

  /// Stable synthetic module identifier.
  @override
  final String module_id;

  /// Callback contributing the module's messaging capabilities.
  final void Function(MessageCodecRegistry) contribute;

  /// Contributes the configured capabilities to [registry].
  @override
  void register_codecs(MessageCodecRegistry registry) {
    contribute(registry);
  }
}

/// Synthetic request belonging to the Echo feature.
final class _EchoRequest implements Request<_EchoResponse> {
  /// Creates an Echo request containing [value].
  const _EchoRequest(this.value);

  /// Application value carried by the request.
  final String value;
}

/// Synthetic response belonging to the Echo feature.
final class _EchoResponse implements Response {
  /// Creates an Echo response containing [value].
  const _EchoResponse(this.value);

  /// Application value carried by the response.
  final String value;
}

/// Synthetic request belonging to the Label feature.
final class _LabelRequest implements Request<_LabelResponse> {
  /// Creates a Label request containing [value].
  const _LabelRequest(this.value);

  /// Application value carried by the request.
  final String value;
}

/// Synthetic response belonging to the Label feature.
final class _LabelResponse implements Response {
  /// Creates a Label response containing [value].
  const _LabelResponse(this.value);

  /// Application value carried by the response.
  final String value;
}

/// Synthetic codec for messages containing one string value.
///
/// Keeps test serialization independent of production application
/// message representations.
final class _TextCodec<M extends Message> implements MessageCodec<M> {
  /// Creates a codec with a stable [type_id].
  ///
  /// [create] reconstructs the concrete message from its string value.
  /// [read] extracts the string value from a concrete message.
  const _TextCodec({
    required this.type_id,
    required this.create,
    required this.read,
  });

  /// Stable wire identifier of the synthetic message.
  @override
  final String type_id;

  /// Constructs a message from its decoded value.
  final M Function(String) create;

  /// Extracts the value carried by a message.
  final String Function(M) read;

  /// Returns the string value carried by [message].
  @override
  Object? encode(M message) => read(message);

  /// Reconstructs a message from [payload].
  ///
  /// Throws [FormatException] when the payload is not a string.
  @override
  M decode(Object? payload) {
    if (payload is! String) {
      throw const FormatException('Invalid synthetic message payload.');
    }

    return create(payload);
  }
}

/// Returns the synthetic Echo request codec.
MessageCodec<_EchoRequest> _echo_request_codec() {
  return _TextCodec<_EchoRequest>(
    type_id: 'test.echo.request.v1',
    create: _EchoRequest.new,
    read: (message) => message.value,
  );
}

/// Returns the synthetic Echo response codec.
///
/// [type_id] permits explicit wire identifier conflict testing.
MessageCodec<_EchoResponse> _echo_response_codec({
  String type_id = 'test.echo.response.v1',
}) {
  return _TextCodec<_EchoResponse>(
    type_id: type_id,
    create: _EchoResponse.new,
    read: (message) => message.value,
  );
}

/// Returns the synthetic Label request codec.
MessageCodec<_LabelRequest> _label_request_codec() {
  return _TextCodec<_LabelRequest>(
    type_id: 'test.label.request.v1',
    create: _LabelRequest.new,
    read: (message) => message.value,
  );
}

/// Returns the synthetic Label response codec.
///
/// [type_id] permits explicit wire identifier conflict testing.
MessageCodec<_LabelResponse> _label_response_codec({
  String type_id = 'test.label.response.v1',
}) {
  return _TextCodec<_LabelResponse>(
    type_id: type_id,
    create: _LabelResponse.new,
    read: (message) => message.value,
  );
}

/// Contributes the Echo feature's message codecs to [registry].
void _register_echo(MessageCodecRegistry registry) {
  registry
    ..register_request<_EchoResponse, _EchoRequest>(_echo_request_codec())
    ..register_response<_EchoResponse>(_echo_response_codec());
}

/// Contributes the Label feature's message codecs to [registry].
void _register_label(MessageCodecRegistry registry) {
  registry
    ..register_request<_LabelResponse, _LabelRequest>(_label_request_codec())
    ..register_response<_LabelResponse>(_label_response_codec());
}
