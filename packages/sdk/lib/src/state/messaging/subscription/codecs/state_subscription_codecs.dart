import 'package:rudra_communication/rudra_communication.dart';

import '../../../../workflow/workflow_runtime.dart';

import '../../../publication/state_publication_snapshot.dart';
import '../../serialization/rudra_state_codec.dart';

import '../state_subscription_messages.dart';

/// Serializes state subscription establishment requests.
///
/// Example:
/// ```dart
/// const codec = StateSubscribeRequestCodec();
///
/// final request = codec.decode({
///   'subscription_id': 'subscription-1',
/// });
///
/// print(request.subscription_id);
/// ```
final class StateSubscribeRequestCodec
    implements MessageCodec<StateSubscribeRequest> {
  /// Creates the stateless subscription request codec.
  const StateSubscribeRequestCodec();

  /// Stable version 1 wire identifier.
  @override
  String get type_id => 'rudra.state.subscribe.request.v1';

  /// Returns the subscription identifier from [message].
  @override
  Map<String, Object?> encode(StateSubscribeRequest message) {
    return {'subscription_id': message.subscription_id};
  }

  /// Reconstructs a subscription request from [payload].
  ///
  /// Throws [FormatException] for invalid fields or identifiers.
  @override
  StateSubscribeRequest decode(Object? payload) {
    final fields = _require_fields(payload, {'subscription_id'});

    return StateSubscribeRequest(
      subscription_id: _identifier(fields, 'subscription_id'),
    );
  }
}

/// Serializes subscription acceptance responses.
///
/// Example:
/// ```dart
/// const codec = StateSubscribeResponseCodec();
///
/// final response = codec.decode({
///   'subscription_id': 'subscription-1',
///   'generation': 'generation-1',
/// });
///
/// print(response.generation);
/// ```
final class StateSubscribeResponseCodec
    implements MessageCodec<StateSubscribeResponse> {
  /// Creates the stateless subscription response codec.
  const StateSubscribeResponseCodec();

  /// Stable version 1 wire identifier.
  @override
  String get type_id => 'rudra.state.subscribe.response.v1';

  /// Returns the accepted subscription and generation from [message].
  @override
  Map<String, Object?> encode(StateSubscribeResponse message) {
    return {
      'subscription_id': message.subscription_id,
      'generation': message.generation,
    };
  }

  /// Reconstructs subscription acceptance from [payload].
  ///
  /// Throws [FormatException] for invalid fields or identifiers.
  @override
  StateSubscribeResponse decode(Object? payload) {
    final fields = _require_fields(payload, {'subscription_id', 'generation'});

    return StateSubscribeResponse(
      subscription_id: _identifier(fields, 'subscription_id'),
      generation: _identifier(fields, 'generation'),
    );
  }
}

/// Serializes verified composite application-state deliveries.
///
/// Domain-state serialization is delegated to [RudraStateCodec].
///
/// Example:
/// ```dart
/// final codec = StateDeliveryRequestCodec(runtime: runtime);
///
/// final payload = codec.encode(request);
/// final restored = codec.decode(payload);
///
/// print(restored.publication.state.workflows.current_workflow);
/// ```
final class StateDeliveryRequestCodec
    implements MessageCodec<StateDeliveryRequest> {
  /// Creates a delivery codec using the supplied [runtime].
  ///
  /// Throws [StateError] when required state serialization capabilities
  /// are missing from the workflow configuration.
  StateDeliveryRequestCodec({required WorkflowRuntime runtime})
    : _state_codec = RudraStateCodec(runtime: runtime);

  /// Serializer for immutable composite application state.
  final RudraStateCodec _state_codec;

  /// Stable version 1 wire identifier.
  @override
  String get type_id => 'rudra.state.delivery.request.v1';

  /// Returns the subscription, publication position and state from
  /// [message].
  ///
  /// Domain serialization failures propagate.
  @override
  Map<String, Object?> encode(StateDeliveryRequest message) {
    final publication = message.publication;

    return {
      'subscription_id': message.subscription_id,
      'generation': publication.generation,
      'revision': publication.revision,
      'state': _state_codec.encode(publication.state),
    };
  }

  /// Reconstructs a typed state delivery from [payload].
  ///
  /// Returns the complete publication with its concrete SDK state.
  ///
  /// Throws [FormatException] for malformed publication metadata
  /// or invalid state representations.
  ///
  /// Feature-owned serialization contract failures propagate.
  @override
  StateDeliveryRequest decode(Object? payload) {
    final fields = _require_fields(payload, {
      'subscription_id',
      'generation',
      'revision',
      'state',
    });

    final subscription_id = _identifier(fields, 'subscription_id');
    final generation = _identifier(fields, 'generation');
    final revision = _revision(fields);

    return StateDeliveryRequest(
      subscription_id: subscription_id,
      publication: StatePublicationSnapshot(
        generation: generation,
        revision: revision,
        state: _state_codec.decode(fields['state']),
      ),
    );
  }
}

/// Serializes exact publication acknowledgments.
///
/// Example:
/// ```dart
/// const codec = StateDeliveryResponseCodec();
///
/// final acknowledgment = codec.decode({
///   'subscription_id': 'subscription-1',
///   'generation': 'generation-1',
///   'revision': 7,
/// });
///
/// print(acknowledgment.revision);
/// ```
final class StateDeliveryResponseCodec
    implements MessageCodec<StateDeliveryResponse> {
  /// Creates the stateless delivery acknowledgment codec.
  const StateDeliveryResponseCodec();

  /// Stable version 1 wire identifier.
  @override
  String get type_id => 'rudra.state.delivery.response.v1';

  /// Returns the acknowledged publication position from [message].
  @override
  Map<String, Object?> encode(StateDeliveryResponse message) {
    return {
      'subscription_id': message.subscription_id,
      'generation': message.generation,
      'revision': message.revision,
    };
  }

  /// Reconstructs a delivery acknowledgment from [payload].
  ///
  /// Throws [FormatException] for invalid identifiers or revisions.
  @override
  StateDeliveryResponse decode(Object? payload) {
    final fields = _require_fields(payload, {
      'subscription_id',
      'generation',
      'revision',
    });

    return StateDeliveryResponse(
      subscription_id: _identifier(fields, 'subscription_id'),
      generation: _identifier(fields, 'generation'),
      revision: _revision(fields),
    );
  }
}

/// Serializes explicit subscription cancellation requests.
///
/// Example:
/// ```dart
/// const codec = StateUnsubscribeRequestCodec();
///
/// final request = codec.decode({
///   'subscription_id': 'subscription-1',
/// });
///
/// print(request.subscription_id);
/// ```
final class StateUnsubscribeRequestCodec
    implements MessageCodec<StateUnsubscribeRequest> {
  /// Creates the stateless cancellation request codec.
  const StateUnsubscribeRequestCodec();

  /// Stable version 1 wire identifier.
  @override
  String get type_id => 'rudra.state.unsubscribe.request.v1';

  /// Returns the requested subscription identifier from [message].
  @override
  Map<String, Object?> encode(StateUnsubscribeRequest message) {
    return {'subscription_id': message.subscription_id};
  }

  /// Reconstructs a cancellation request from [payload].
  ///
  /// Throws [FormatException] for invalid fields or identifiers.
  @override
  StateUnsubscribeRequest decode(Object? payload) {
    final fields = _require_fields(payload, {'subscription_id'});

    return StateUnsubscribeRequest(
      subscription_id: _identifier(fields, 'subscription_id'),
    );
  }
}

/// Serializes completed subscription cancellation responses.
///
/// Example:
/// ```dart
/// const codec = StateUnsubscribeResponseCodec();
///
/// final response = codec.decode({
///   'subscription_id': 'subscription-1',
/// });
///
/// print(response.subscription_id);
/// ```
final class StateUnsubscribeResponseCodec
    implements MessageCodec<StateUnsubscribeResponse> {
  /// Creates the stateless cancellation response codec.
  const StateUnsubscribeResponseCodec();

  /// Stable version 1 wire identifier.
  @override
  String get type_id => 'rudra.state.unsubscribe.response.v1';

  /// Returns the drained subscription identifier from [message].
  @override
  Map<String, Object?> encode(StateUnsubscribeResponse message) {
    return {'subscription_id': message.subscription_id};
  }

  /// Reconstructs cancellation confirmation from [payload].
  ///
  /// Throws [FormatException] for invalid fields or identifiers.
  @override
  StateUnsubscribeResponse decode(Object? payload) {
    final fields = _require_fields(payload, {'subscription_id'});

    return StateUnsubscribeResponse(
      subscription_id: _identifier(fields, 'subscription_id'),
    );
  }
}

/// Validates the exact expected [keys] of a subscription [payload].
///
/// Returns the structured message fields.
/// Throws [FormatException] for missing or unexpected fields.
Map<String, Object?> _require_fields(Object? payload, Set<String> keys) {
  if (payload is! Map<String, Object?> ||
      payload.length != keys.length ||
      !keys.every(payload.containsKey)) {
    throw const FormatException('Invalid state subscription payload.');
  }

  return payload;
}

/// Reads a nonblank identifier identified by [key] from [fields].
///
/// Returns its original value or throws [FormatException].
String _identifier(Map<String, Object?> fields, String key) {
  final value = fields[key];

  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid state subscription field: $key.');
  }

  return value;
}

/// Reads the positive publication revision from [fields].
///
/// Returns the revision or throws [FormatException].
int _revision(Map<String, Object?> fields) {
  final value = fields['revision'];

  if (value is! int || value <= 0) {
    throw const FormatException('Invalid state publication revision.');
  }

  return value;
}
