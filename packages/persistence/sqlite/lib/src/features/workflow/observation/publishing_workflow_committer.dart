import 'dart:developer' as developer;

import 'package:rudra_sdk/rudra_sdk.dart';

/// Adds committed-change publication to an existing workflow committer.
///
/// The delegate remains responsible for transactional validation and durable
/// persistence. The publisher only reports successfully committed changes.
///
/// Publication failures are logged as diagnostics and cannot change the
/// result of a transaction that has already committed.
///
/// Example:
/// ```dart
/// final committer = PublishingWorkflowCommitter(
///   delegate: sqlite_committer,
///   publisher: commit_channel,
///   os_user_id: trusted_os_user_id,
/// );
///
/// await committer.commit(plan);
/// ```
final class PublishingWorkflowCommitter implements WorkflowCommitter {
  /// Creates a post-commit publishing decorator.
  ///
  /// [delegate] validates and commits workflow processing plans.
  /// [publisher] receives notifications after successful commitments.
  /// [os_user_id] identifies the authenticated owner from trusted composition.
  ///
  /// Throws [ArgumentError] if [os_user_id] is blank.
  /// Construction performs no persistence or publication.
  PublishingWorkflowCommitter({
    required WorkflowCommitter delegate,
    required WorkflowCommitPublisher publisher,
    required String os_user_id,
  }) : _delegate = delegate,
       _publisher = publisher,
       _os_user_id = _require_owner(os_user_id);

  /// Authoritative persistence committer receiving proposed changes.
  final WorkflowCommitter _delegate;

  /// SDK-defined port used to report successful commitments.
  final WorkflowCommitPublisher _publisher;

  /// Authenticated owner associated with this committer.
  final String _os_user_id;

  /// Commits [plan] and reports one durable workflow-state change.
  ///
  /// Returns after the delegate commits and publication is attempted.
  /// Delegate failures propagate without publishing.
  ///
  /// If publication throws after commitment, the failure is logged.
  /// The committed transaction remains successful and recoverable from
  /// authoritative history, although live observers may require recovery.
  @override
  Future<void> commit(WorkflowProcessingPlan plan) async {
    await _delegate.commit(plan);

    try {
      _publisher.publish(os_user_id: _os_user_id);
    } catch (error, stack_trace) {
      developer.log(
        'Workflow committed, but change publication failed.',
        name: 'rudra.persistence.sqlite.workflow',
        error: error,
        stackTrace: stack_trace,
      );
    }
  }

  /// Validates the authenticated [os_user_id] without normalizing it.
  ///
  /// Returns the original identifier or throws [ArgumentError] when blank.
  static String _require_owner(String os_user_id) {
    if (os_user_id.trim().isEmpty) {
      throw ArgumentError.value(os_user_id, 'os_user_id');
    }
    return os_user_id;
  }
}
