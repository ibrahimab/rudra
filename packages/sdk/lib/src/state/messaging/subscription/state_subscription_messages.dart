import 'package:rudra_communication/rudra_communication.dart';

import '../../publication/state_publication_snapshot.dart';

/// Requests a state subscription on an authenticated session.
///
/// The client prepares its receiver before sending this request,
/// because initial delivery may precede the acceptance response.
///
/// Example:
/// ```dart
/// final response = await session.request(
///   StateSubscribeRequest(
///     subscription_id: prepared_subscription_id,
///   ),
/// );
///
/// print(response.generation);
/// ```
final class StateSubscribeRequest implements Request<StateSubscribeResponse> {
  /// Creates a subscription request identified by [subscription_id].
  ///
  /// Throws [ArgumentError] for a blank identifier.
  StateSubscribeRequest({required this.subscription_id}) {
    _require_identifier(subscription_id, 'subscription_id');
  }

  /// Client-assigned identity scoped to the authenticated session.
  ///
  /// Clients allocate a distinct identifier for each new subscription.
  final String subscription_id;
}

/// Confirms that the host has admitted a state subscription.
///
/// Acceptance and initial state delivery are independent.
///
/// Example:
/// ```dart
/// final response = StateSubscribeResponse(
///   subscription_id: request.subscription_id,
///   generation: publication.generation,
/// );
/// ```
final class StateSubscribeResponse implements Response {
  /// Confirms admission of [subscription_id] to [generation].
  ///
  /// Throws [ArgumentError] for blank identifiers.
  StateSubscribeResponse({
    required this.subscription_id,
    required this.generation,
  }) {
    _require_identifier(subscription_id, 'subscription_id');
    _require_identifier(generation, 'generation');
  }

  /// Identity of the admitted subscription.
  final String subscription_id;

  /// Authoritative publication generation assigned by the host.
  final String generation;
}

/// Delivers one verified application-state publication to a subscriber.
///
/// Delivery is initiated by the host through an existing bidirectional
/// communication session.
///
/// Example:
/// ```dart
/// final response = await session.request(
///   StateDeliveryRequest(
///     subscription_id: subscription_id,
///     publication: snapshot,
///   ),
/// );
///
/// assert(response.revision == snapshot.revision);
/// ```
final class StateDeliveryRequest implements Request<StateDeliveryResponse> {
  /// Creates a delivery of [publication] to [subscription_id].
  ///
  /// Throws [ArgumentError] for a blank subscription identifier.
  StateDeliveryRequest({
    required this.subscription_id,
    required this.publication,
  }) {
    _require_identifier(subscription_id, 'subscription_id');
  }

  /// Identity of the intended receiving subscription.
  final String subscription_id;

  /// Verified immutable state and its publication position.
  final StatePublicationSnapshot publication;
}

/// Acknowledges acceptance of an application-state publication.
///
/// Acknowledgment establishes acceptance by the client-side state
/// consumer, independently of frontend rendering.
///
/// Example:
/// ```dart
/// final acknowledgment = StateDeliveryResponse(
///   subscription_id: request.subscription_id,
///   generation: request.publication.generation,
///   revision: request.publication.revision,
/// );
/// ```
final class StateDeliveryResponse implements Response {
  /// Acknowledges [revision] within [generation] for [subscription_id].
  ///
  /// Throws [ArgumentError] for blank identifiers or a non-positive
  /// publication revision.
  StateDeliveryResponse({
    required this.subscription_id,
    required this.generation,
    required this.revision,
  }) {
    _require_identifier(subscription_id, 'subscription_id');
    _require_identifier(generation, 'generation');

    if (revision <= 0) {
      throw ArgumentError.value(revision, 'revision');
    }
  }

  /// Subscription associated with the accepted delivery.
  final String subscription_id;

  /// Generation of the accepted publication.
  final String generation;

  /// Revision of the accepted publication.
  final int revision;
}

/// Requests cancellation of a subscription on the current session.
///
/// Local state acceptance is retired before requesting host
/// cancellation. Valid outstanding deliveries remain acknowledged
/// until the host confirms cancellation.
///
/// Example:
/// ```dart
/// final response = await session.request(
///   StateUnsubscribeRequest(
///     subscription_id: retired_subscription_id,
///   ),
/// );
/// ```
final class StateUnsubscribeRequest
    implements Request<StateUnsubscribeResponse> {
  /// Creates a cancellation request for [subscription_id].
  ///
  /// Throws [ArgumentError] for a blank identifier.
  StateUnsubscribeRequest({required this.subscription_id}) {
    _require_identifier(subscription_id, 'subscription_id');
  }

  /// Identity of the subscription to terminate.
  final String subscription_id;
}

/// Confirms subscription termination and completion of admitted delivery.
///
/// Example:
/// ```dart
/// final response = StateUnsubscribeResponse(
///   subscription_id: drained_subscription_id,
/// );
/// ```
final class StateUnsubscribeResponse implements Response {
  /// Confirms cancellation of [subscription_id].
  ///
  /// Throws [ArgumentError] for a blank identifier.
  StateUnsubscribeResponse({required this.subscription_id}) {
    _require_identifier(subscription_id, 'subscription_id');
  }

  /// Identity of the fully drained subscription.
  final String subscription_id;
}

/// Validates an opaque identifier without normalizing its value.
///
/// [name] identifies the corresponding argument.
/// Throws [ArgumentError] when [value] is blank.
void _require_identifier(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name);
  }
}
