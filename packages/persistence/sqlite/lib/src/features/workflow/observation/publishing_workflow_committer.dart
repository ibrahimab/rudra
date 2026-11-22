import 'package:rudra_sdk/rudra_sdk.dart';

/// Publishes successful workflow commitments from a persistence adapter.
///
/// The delegate owns transactional validation and durability. Publication
/// occurs only after its commit completes successfully.
final class PublishingWorkflowCommitter implements WorkflowCommitter {
  /// Wraps [delegate] with post-commit notifications through [publisher].
  ///
  /// [os_user_id] is the authenticated owner supplied by trusted composition.
  /// The publisher must not throw for a valid trusted owner.
  PublishingWorkflowCommitter({
    required WorkflowCommitter delegate,
    required WorkflowCommitPublisher publisher,
    required String os_user_id,
  }) : _delegate = delegate,
       _publisher = publisher,
       _os_user_id = _require_owner(os_user_id);

  final WorkflowCommitter _delegate;
  final WorkflowCommitPublisher _publisher;
  final String _os_user_id;

  /// Commits [plan], then publishes one committed-change notification.
  ///
  /// Failed transactions propagate without publishing. A notification is
  /// never sent for a proposed or partially committed transition.
  @override
  Future<void> commit(WorkflowProcessingPlan plan) async {
    await _delegate.commit(plan);
    _publisher.publish(os_user_id: _os_user_id);
  }

  /// Validates the owner before any transaction can be attempted.
  ///
  /// Returns the original [os_user_id] or throws [ArgumentError].
  static String _require_owner(String os_user_id) {
    if (os_user_id.trim().isEmpty) {
      throw ArgumentError.value(os_user_id, 'os_user_id');
    }
    return os_user_id;
  }
}
