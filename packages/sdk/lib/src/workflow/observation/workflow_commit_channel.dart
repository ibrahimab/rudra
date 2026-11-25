import 'dart:async';

/// Persistence-facing contract for reporting committed workflow changes.
///
/// A publication indicates that authoritative persisted evidence changed.
/// It does not contain a proposed transition or a workflow snapshot.
abstract interface class WorkflowCommitPublisher {
  /// Publishes a committed change for trusted [os_user_id].
  ///
  /// Persistence invokes this only after a successful transaction.
  ///
  /// Normal delivery and subscriber failures must not throw.
  /// An implementation unable to report a committed change must
  /// invalidate its corresponding observation source rather than
  /// silently lose the notification.
  void publish({required String os_user_id});
}

/// SDK-facing contract for receiving committed workflow change signals.
///
/// A signal is a request to reconcile authoritative persistence, not
/// authorization to advance a domain state machine directly.
abstract interface class WorkflowCommitSubscriber {
  /// Watches committed changes for trusted [os_user_id].
  ///
  /// Returns an in-order stream of change signals provided by the
  /// implementation.
  ///
  /// Loss of the notification capability must terminate observation
  /// through a stream error or closure.
  ///
  /// Watching performs no persistence writes.
  Stream<void> watch({required String os_user_id});
}

/// In-process commit notification channel shared by trusted composition.
///
/// This channel carries owner-scoped change signals without interpreting
/// domain outcomes. It does not detect commits made through an unrelated
/// channel or another operating-system process.
///
/// Notifications are not durable. Restoring authoritative state remains
/// the SDK application's responsibility.
final class LocalWorkflowCommitChannel
    implements WorkflowCommitPublisher, WorkflowCommitSubscriber {
  /// Creates a channel without performing persistence operations.
  LocalWorkflowCommitChannel();

  /// Shared asynchronous broadcast source for committed owner changes.
  final StreamController<String> _commits =
      StreamController<String>.broadcast();

  /// Publishes a committed change to current local subscribers.
  ///
  /// [os_user_id] must be a trusted, nonblank owner identifier.
  /// A closed channel ignores further publications.
  @override
  void publish({required String os_user_id}) {
    _validate_owner(os_user_id);

    if (_commits.isClosed) {
      return;
    }

    _commits.add(os_user_id);
  }

  /// Observes future commits for the specified trusted owner.
  ///
  /// [os_user_id] must be nonblank. Subscribing does not replay previous
  /// notifications; consumers must restore initial authoritative state.
  @override
  Stream<void> watch({required String os_user_id}) {
    _validate_owner(os_user_id);

    return _commits.stream
        .where((owner) => owner == os_user_id)
        .map<void>((_) {});
  }

  /// Closes the local channel and completes active subscriptions.
  ///
  /// Returns when stream shutdown has completed. The composition owner
  /// should cancel long-lived subscriptions before disposing persistence.
  Future<void> close() => _commits.close();

  /// Validates an authenticated owner identifier supplied by composition.
  ///
  /// Throws [ArgumentError] for a blank [os_user_id].
  static void _validate_owner(String os_user_id) {
    if (os_user_id.trim().isEmpty) {
      throw ArgumentError.value(
        os_user_id,
        'os_user_id',
        'Trusted OS-user identity must not be blank.',
      );
    }
  }
}
