import 'dart:async';

import 'package:rudra_sdk/rudra_sdk.dart';

/// Observes durable application acceptance and controls commitment timing.
///
/// All persistence operations delegate to the supplied implementation.
/// The fixture neither fabricates application outcomes nor substitutes
/// transaction validation.
///
/// The caller retains ownership of the delegate's resource lifecycle.
final class ControlledWorkflowPersistence
    implements WorkflowApplicationPersistence, EventSubmissionStore {
  /// Creates a fixture around authoritative [delegate] persistence.
  ControlledWorkflowPersistence(this.delegate);

  /// Authoritative persistence implementation.
  final WorkflowApplicationPersistence delegate;

  /// Accepted receipts grouped by logical operation key.
  final Map<String, List<EventSubmissionReceipt>> _accepted = {};

  /// Waiters indexed by operation key and acceptance occurrence.
  final Map<(String, int), Completer<EventSubmissionReceipt>> _waiters = {};

  /// Optional barrier controlling the next commitment.
  WorkflowCommitBarrier? _commit_barrier;

  /// Installs and returns a barrier for the next commitment.
  ///
  /// Throws [StateError] when a previously installed barrier remains
  /// unreleased.
  WorkflowCommitBarrier hold_next_commit() {
    final previous = _commit_barrier;

    if (previous != null && !previous.is_released) {
      throw StateError('A commitment barrier is already active.');
    }

    final barrier = WorkflowCommitBarrier();

    _commit_barrier = barrier;

    return barrier;
  }

  /// Releases any suspended commitment for deterministic cleanup.
  void release_commit() {
    _commit_barrier?.release();
  }

  /// Waits for durable acceptance of the specified [idempotency_key].
  ///
  /// [occurrence] identifies the acceptance invocation, beginning at one.
  /// Identical retries may produce the same durable receipt.
  ///
  /// Returns only after the authoritative acceptance operation succeeds.
  ///
  /// Throws [ArgumentError] when occurrence is not positive.
  Future<EventSubmissionReceipt> accepted(
    String idempotency_key, {
    int occurrence = 1,
  }) {
    if (occurrence <= 0) {
      throw ArgumentError.value(occurrence, 'occurrence');
    }

    final receipts = _accepted[idempotency_key];

    if (receipts != null && receipts.length >= occurrence) {
      return Future.value(receipts[occurrence - 1]);
    }

    return _waiters.putIfAbsent((
      idempotency_key,
      occurrence,
    ), () => Completer<EventSubmissionReceipt>()).future;
  }

  /// Exposes the observed durable submission boundary.
  @override
  EventSubmissionStore get event_submission_store => this;

  /// Durably accepts [event] using the supplied [idempotency_key].
  ///
  /// Records successful acceptance only after the delegate returns.
  /// Submission failures propagate unchanged.
  @override
  Future<EventSubmissionReceipt> accept(
    WorkflowCommandEvent event, {
    String? idempotency_key,
  }) async {
    final receipt = await delegate.event_submission_store.accept(
      event,
      idempotency_key: idempotency_key,
    );

    if (idempotency_key != null) {
      final receipts = _accepted.putIfAbsent(
        idempotency_key,
        () => <EventSubmissionReceipt>[],
      );

      receipts.add(receipt);

      _waiters.remove((idempotency_key, receipts.length))?.complete(receipt);
    }

    return receipt;
  }

  /// Supplies authoritative committed history.
  @override
  WorkflowHistoryStore get workflow_history_store =>
      delegate.workflow_history_store;

  /// Supplies authoritative committed-change notifications.
  @override
  WorkflowCommitSubscriber get workflow_commit_subscriber =>
      delegate.workflow_commit_subscriber;

  /// Supplies the authoritative resolution reader for [os_user_id].
  @override
  WorkflowSubmissionStatusReader workflow_status_reader_for({
    required String os_user_id,
  }) {
    return delegate.workflow_status_reader_for(os_user_id: os_user_id);
  }

  /// Supplies authoritative rejection persistence.
  @override
  WorkflowSubmissionRejector get workflow_rejector =>
      delegate.workflow_rejector;

  /// Supplies authoritative quarantine persistence.
  @override
  WorkflowSubmissionQuarantiner get workflow_quarantiner =>
      delegate.workflow_quarantiner;

  /// Supplies the authoritative pending-command inbox for [os_user_id].
  @override
  WorkflowInbox workflow_inbox_for({required String os_user_id}) {
    return delegate.workflow_inbox_for(os_user_id: os_user_id);
  }

  /// Supplies a controlled committer for trusted [os_user_id].
  ///
  /// Actual commitment remains the responsibility of the delegate.
  @override
  WorkflowCommitter workflow_committer_for({required String os_user_id}) {
    return _ControlledCommitter(
      delegate.workflow_committer_for(os_user_id: os_user_id),
      this,
    );
  }
}

/// Suspends one validated processing proposal before commitment.
///
/// The proposal remains uncommitted until the fixture releases the barrier.
final class WorkflowCommitBarrier {
  /// Retains the first processing proposal reaching this barrier.
  final Completer<WorkflowProcessingPlan> _entered =
      Completer<WorkflowProcessingPlan>();

  /// Releases the suspended commitment.
  final Completer<void> _released = Completer<void>();

  /// Returns the validated proposal awaiting authoritative commitment.
  Future<WorkflowProcessingPlan> get entered => _entered.future;

  /// Whether the fixture has released the commitment.
  bool get is_released => _released.isCompleted;

  /// Holds the first supplied [plan] before commitment.
  ///
  /// Subsequent invocations are not suspended by this one-shot barrier.
  Future<void> hold(WorkflowProcessingPlan plan) async {
    if (_entered.isCompleted) {
      return;
    }

    _entered.complete(plan);

    await _released.future;
  }

  /// Releases the suspended commitment.
  ///
  /// Repeated release is permitted.
  void release() {
    if (!_released.isCompleted) {
      _released.complete();
    }
  }
}

/// Controls commitment admission while retaining the real committer.
final class _ControlledCommitter implements WorkflowCommitter {
  /// Creates a committer using [delegate] and fixture [control].
  const _ControlledCommitter(this.delegate, this.control);

  /// Authoritative transaction boundary.
  final WorkflowCommitter delegate;

  /// Fixture supplying optional commitment barriers.
  final ControlledWorkflowPersistence control;

  /// Commits [plan] after any configured barrier has been released.
  ///
  /// The delegate performs all transactional validation and persistence.
  /// Commitment failures propagate unchanged.
  @override
  Future<void> commit(WorkflowProcessingPlan plan) async {
    await control._commit_barrier?.hold(plan);

    await delegate.commit(plan);
  }
}
