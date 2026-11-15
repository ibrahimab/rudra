import '../workflow_identity.dart';
import 'workflow_processing_models.dart';

/// Supplies identities for workflow command processing.
///
/// Implementations obtain OS-user identity through a trusted
/// platform or application composition boundary.
///
/// A submission scope is not automatically an OS-user identity.
///
/// An identity is only proposed until the workflow committer
/// durably establishes it.
abstract interface class WorkflowIdentityProvider {
  /// Proposes an identity for a pending workflow command.
  ///
  /// A retry may propose another workflow identifier.
  /// Durable identity is determined by successful commitment.
  Future<WorkflowIdentity> propose_identity(PendingWorkflowCommand submission);
}
