import 'message.dart';
import 'message_codec.dart';
import 'message_type_id.dart';

/// Maintains typed message registrations and their stable wire identities.
///
/// Each concrete message type and wire identifier may be registered
/// only once. Request registrations additionally establish their
/// expected concrete response type.
///
/// Configuration must be frozen before message processing begins.
/// Freezing validates request-to-response relationships and prevents
/// subsequent registration changes.
///
/// Example:
/// ```dart
/// final registry = MessageCodecRegistry();
///
/// registry.register_request<EchoResponse, EchoRequest>(
///   EchoRequestCodec(),
/// );
/// registry.register_response<EchoResponse>(
///   EchoResponseCodec(),
/// );
///
/// registry.freeze();
///
/// final encoded = registry.encode(
///   const EchoRequest('Hello'),
/// );
///
/// final decoded = registry.decode(
///   encoded.type_id,
///   encoded.payload,
/// );
/// ```
final class MessageCodecRegistry {
  /// Creates an empty, mutable message codec registry.
  ///
  /// Construction does not initialize communication resources.
  MessageCodecRegistry();

  /// Registrations indexed by their concrete Dart message type.
  final Map<Type, _CodecRegistration> _registrations_by_type = {};

  /// Registrations indexed by their stable wire identifier.
  final Map<String, _CodecRegistration> _registrations_by_id = {};

  /// Whether configuration has been validated and frozen.
  bool _is_frozen = false;

  /// Whether the registry is ready for message processing.
  ///
  /// A frozen registry cannot accept further registrations.
  bool get is_frozen => _is_frozen;

  /// Registers a codec for concrete request type [Q].
  ///
  /// [R] identifies the concrete response expected by the request.
  /// [codec] provides the request's structured representation
  /// and stable wire identifier.
  ///
  /// The corresponding response codec must be registered before
  /// configuration is frozen.
  ///
  /// Throws [ArgumentError] for an invalid or reserved wire identifier.
  /// Throws [StateError] for duplicate registrations or when
  /// configuration has already been frozen.
  void register_request<R extends Response, Q extends Request<R>>(
    MessageCodec<Q> codec,
  ) {
    _register<Q>(codec, response_type: R);
  }

  /// Registers a codec for concrete response type [R].
  ///
  /// [codec] provides the response's structured representation
  /// and stable wire identifier.
  ///
  /// Throws [ArgumentError] for an invalid or reserved wire identifier.
  /// Throws [StateError] for duplicate registrations or when
  /// configuration has already been frozen.
  void register_response<R extends Response>(MessageCodec<R> codec) {
    _register<R>(codec);
  }

  /// Validates and freezes the registered messaging configuration.
  ///
  /// Every registered request must have a corresponding concrete
  /// response registration before message processing can begin.
  ///
  /// Throws [StateError] when a required response registration
  /// is missing or incompatible.
  ///
  /// Failed validation leaves the registry mutable.
  /// Repeated successful calls have no additional effect.
  void freeze() {
    if (_is_frozen) {
      return;
    }

    for (final registration in _registrations_by_type.values) {
      final response_type = registration.response_type;

      if (response_type == null) {
        continue;
      }

      final response_registration = _registrations_by_type[response_type];

      if (response_registration == null ||
          response_registration.response_type != null) {
        throw StateError(
          'Missing response registration for '
          '${registration.message_type}: $response_type.',
        );
      }
    }

    _is_frozen = true;
  }

  /// Returns the registered response type for [request].
  ///
  /// The result identifies the configured concrete response type
  /// independently of generic type widening by a request caller.
  ///
  /// Throws [StateError] if configuration has not been frozen.
  /// Throws [ArgumentError] if the request is not registered.
  Type response_type_for(Request<Response> request) {
    _require_frozen();

    final registration = _registrations_by_type[request.runtimeType];

    if (registration == null || registration.response_type == null) {
      throw ArgumentError.value(
        request.runtimeType,
        'request',
        'Unregistered request type.',
      );
    }

    _validate_message(registration, request);

    return registration.response_type!;
  }

  /// Encodes [message] through its registered codec.
  ///
  /// Returns its stable wire identifier and structured payload.
  /// The returned representation contains no request correlation
  /// or transport framing metadata.
  ///
  /// Throws [StateError] if configuration has not been frozen or
  /// the registered message contract is violated.
  /// Throws [ArgumentError] if the message type is not registered.
  /// Codec encoding failures propagate to the caller.
  ({String type_id, Object? payload}) encode(Message message) {
    _require_frozen();

    final registration = _registrations_by_type[message.runtimeType];

    if (registration == null) {
      throw ArgumentError.value(
        message.runtimeType,
        'message',
        'Unregistered message type.',
      );
    }

    _validate_message(registration, message);

    return (
      type_id: registration.type_id,
      payload: registration.codec.encode(message),
    );
  }

  /// Decodes [payload] through the codec registered for [type_id].
  ///
  /// Returns an instance of the registered concrete message type.
  ///
  /// Throws [FormatException] for an unknown wire identifier or
  /// a malformed message payload.
  /// Throws [StateError] if configuration has not been frozen
  /// or the codec violates its registered message contract.
  Message decode(String type_id, Object? payload) {
    _require_frozen();

    final registration = _registrations_by_id[type_id];

    if (registration == null) {
      throw const FormatException('Unknown message type.');
    }

    final message = registration.codec.decode(payload);

    _validate_message(registration, message);

    return message;
  }

  /// Registers [codec] for concrete message type [M].
  ///
  /// [response_type] identifies the expected response for a request
  /// registration and is absent for a response registration.
  ///
  /// Both indexes are validated before either is modified, preventing
  /// failed registrations from leaving inconsistent configuration.
  ///
  /// Throws [ArgumentError] for an invalid or reserved identifier
  /// and [StateError] for duplicate or frozen registrations.
  void _register<M extends Message>(
    MessageCodec<M> codec, {
    Type? response_type,
  }) {
    if (_is_frozen) {
      throw StateError('Message codec registry is frozen.');
    }

    final type_id = codec.type_id;

    if (!is_application_message_type_id(type_id)) {
      throw ArgumentError.value(
        type_id,
        'type_id',
        'Invalid or reserved application message type identifier.',
      );
    }

    if (_registrations_by_type.containsKey(M)) {
      throw StateError('Message type is already registered: $M.');
    }

    if (_registrations_by_id.containsKey(type_id)) {
      throw StateError('Message identifier is already registered: $type_id.');
    }

    final registration = _CodecRegistration(
      message_type: M,
      type_id: type_id,
      codec: codec,
      response_type: response_type,
    );

    _registrations_by_type[M] = registration;
    _registrations_by_id[type_id] = registration;
  }

  /// Validates [message] against its concrete [registration].
  ///
  /// Exact type and message category validation protect the
  /// registry's heterogeneous codec storage boundary.
  ///
  /// Throws [StateError] when a codec or registration violates
  /// its declared message contract.
  void _validate_message(_CodecRegistration registration, Message message) {
    if (message.runtimeType != registration.message_type) {
      throw StateError('Message does not match its registered concrete type.');
    }

    final is_request = message is Request<Response>;
    final is_response = message is Response;

    // A message registration must represent exactly one category.
    // Request registrations additionally carry a response type.
    if (is_request == is_response ||
        is_request != (registration.response_type != null)) {
      throw StateError('Message does not match its registered category.');
    }
  }

  /// Ensures configuration has been frozen before message processing.
  ///
  /// Throws [StateError] while configuration remains mutable.
  void _require_frozen() {
    if (!_is_frozen) {
      throw StateError('Message codec registry is not frozen.');
    }
  }
}

/// Retains the validated metadata of one message codec registration.
///
/// Registration metadata is captured once so that registry indexing
/// remains independent of subsequent codec property evaluation.
final class _CodecRegistration {
  /// Creates an immutable registration.
  ///
  /// [message_type] identifies the concrete application message.
  /// [type_id] identifies its stable wire representation.
  /// [codec] performs structured message conversion.
  /// [response_type] identifies the expected request response,
  /// or is null for response registrations.
  const _CodecRegistration({
    required this.message_type,
    required this.type_id,
    required this.codec,
    required this.response_type,
  });

  /// Concrete Dart type represented by the codec.
  final Type message_type;

  /// Stable identifier used for wire representation lookup.
  final String type_id;

  /// Codec responsible for encoding and decoding the message.
  final MessageCodec<Message> codec;

  /// Expected concrete response type for request registrations.
  final Type? response_type;
}
