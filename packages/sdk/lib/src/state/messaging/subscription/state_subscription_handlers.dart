import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart';

import '../../publication/state_publication.dart';
import '../../publication/state_publication_snapshot.dart';

import 'state_subscription_messages.dart';

/// Adapts authoritative state publication to authenticated sessions.
///
/// Each participating session owns at most one active or draining
/// subscription. Publication owns the underlying delivery resources.
///
/// Authorization is established by the application request-handler
/// contribution before invoking this adapter.
///
/// Example:
/// ```dart
/// final handlers = StateSubscriptionHandlers(
///   publication: publication,
/// );
///
/// final accepted = handlers.subscribe(
///   StateSubscribeRequest(subscription_id: subscription_id),
///   authorized_session,
/// );
///
/// await handlers.unsubscribe(
///   StateUnsubscribeRequest(
///     subscription_id: accepted.subscription_id,
///   ),
///   authorized_session,
/// );
/// ```
final class StateSubscriptionHandlers {
  /// Creates a session adapter borrowing [publication].
  ///
  /// The publication owner must retain it throughout communication
  /// execution and drain it during host disposal.
  ///
  /// Construction does not subscribe or acquire communication resources.
  StateSubscriptionHandlers({required StatePublication publication})
    : _publication = publication;

  /// Borrowed authoritative publication capability.
  final StatePublication _publication;

  /// Session-local coordination objects indexed by object identity.
  ///
  /// Weak keys prevent the adapter from retaining completed sessions.
  /// Each participating session establishes one termination observer.
  final Expando<_SessionSubscription> _sessions = Expando(
    'rudra.state.subscription',
  );

  /// Admits the requested subscription on authenticated [session].
  ///
  /// [request] supplies its connection-scoped identifier.
  /// Returns the accepted identifier and publication generation.
  ///
  /// Throws [StateError] when the session already retains a subscription
  /// or publication cannot admit another consumer.
  StateSubscribeResponse subscribe(
    StateSubscribeRequest request,
    MessageSession session,
  ) {
    final binding = _sessions[session] ??= _SessionSubscription(session);

    binding.subscribe(
      subscription_id: request.subscription_id,
      publication: _publication,
    );

    return StateSubscribeResponse(
      subscription_id: request.subscription_id,
      generation: _publication.generation,
    );
  }

  /// Terminates the subscription identified by [request] on [session].
  ///
  /// Returns confirmation after its admitted delivery has drained.
  ///
  /// Throws [StateError] when the requested subscription is not owned
  /// by the supplied session.
  Future<StateUnsubscribeResponse> unsubscribe(
    StateUnsubscribeRequest request,
    MessageSession session,
  ) async {
    final binding = _sessions[session];

    if (binding == null) {
      throw StateError('State subscription is unavailable.');
    }

    await binding.unsubscribe(request.subscription_id);

    return StateUnsubscribeResponse(subscription_id: request.subscription_id);
  }
}

/// Retains an admitted subscription and its connection-scoped identity.
typedef _SubscriptionBinding = ({String id, StateSubscription subscription});

/// Coordinates publication admission and cancellation for one session.
///
/// The session remains owned by Communication. This component borrows
/// its messaging and termination capabilities.
///
/// Example:
/// ```dart
/// final binding = _SessionSubscription(session);
///
/// binding.subscribe(
///   subscription_id: subscription_id,
///   publication: publication,
/// );
///
/// await binding.unsubscribe(subscription_id);
/// ```
final class _SessionSubscription {
  /// Establishes a coordination lifecycle for [_session].
  ///
  /// Session termination automatically drains its retained subscription.
  _SessionSubscription(this._session) {
    _session.done
        .then<void>(
          (_) => _disconnect(),
          onError: (Object error, StackTrace stack_trace) {
            return _disconnect();
          },
        )
        .ignore();
  }

  /// Borrowed authenticated communication session.
  final MessageSession _session;

  /// Currently active or draining subscription.
  _SubscriptionBinding? _binding;

  /// Whether the communication lifecycle has terminated.
  bool _terminated = false;

  /// Establishes [subscription_id] against authoritative [publication].
  ///
  /// Throws [StateError] after session termination or while an existing
  /// subscription retains the session's admission slot.
  ///
  /// Publication admission failures propagate to the request handler.
  void subscribe({
    required String subscription_id,
    required StatePublication publication,
  }) {
    if (_terminated || _binding != null) {
      throw StateError('Session cannot admit another state subscription.');
    }

    final subscription = publication.subscribe(
      deliver: (snapshot) => _deliver(subscription_id, snapshot),
    );

    _binding = (id: subscription_id, subscription: subscription);

    // Delivery failure invalidates the client's synchronization.
    // Closing the session also releases any outstanding correlation.
    subscription.done
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stack_trace) {
            _session.close().ignore();
          },
        )
        .ignore();
  }

  /// Delivers [publication] to [subscription_id] and validates its
  /// acknowledgment.
  ///
  /// Returns after the exact publication has been acknowledged.
  ///
  /// Throws [StateError] for an acknowledgment that disagrees with
  /// the delivered subscription or publication position.
  ///
  /// Delivery failures initiate session termination and propagate
  /// even when subscription cancellation is already in progress.
  Future<void> _deliver(
    String subscription_id,
    StatePublicationSnapshot publication,
  ) async {
    try {
      final response = await _session.request(
        StateDeliveryRequest(
          subscription_id: subscription_id,
          publication: publication,
        ),
      );

      if (response.subscription_id != subscription_id ||
          response.generation != publication.generation ||
          response.revision != publication.revision) {
        throw StateError('State delivery acknowledgment mismatch.');
      }
    } catch (_) {
      _session.close().ignore();

      rethrow;
    }
  }

  /// Terminates the retained subscription identified by [subscription_id].
  ///
  /// Returns after its admitted delivery has settled.
  ///
  /// Throws [StateError] if the identifier does not match the retained
  /// subscription.
  Future<void> unsubscribe(String subscription_id) async {
    final binding = _binding;

    if (binding == null || binding.id != subscription_id) {
      throw StateError('State subscription is unavailable.');
    }

    await _retire(binding);
  }

  /// Prohibits additional admission and drains the retained subscription.
  ///
  /// Invoked once when the associated session terminates.
  Future<void> _disconnect() async {
    _terminated = true;

    final binding = _binding;

    if (binding != null) {
      await _retire(binding);
    }
  }

  /// Cancels [binding] and releases its session admission slot.
  ///
  /// Retains the slot until its outstanding delivery has settled,
  /// preventing replacement admission during cancellation.
  Future<void> _retire(_SubscriptionBinding binding) async {
    await binding.subscription.cancel();

    // Explicit cancellation and disconnection may overlap.
    if (identical(_binding?.subscription, binding.subscription)) {
      _binding = null;
    }
  }
}
