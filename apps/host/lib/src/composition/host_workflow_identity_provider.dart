import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:uuid/uuid.dart';

/// Proposes workflow identities within a trusted host ownership scope.
///
/// Associates each proposed workflow with the authenticated
/// operating-system user established during host composition.
///
/// The proposed identity becomes authoritative only after
/// successful validation and durable commitment by the SDK.
///
/// Example:
/// ```dart
/// final provider = HostWorkflowIdentityProvider(
///   os_user_id: 'macos-uid:501',
/// );
///
/// final identity = await provider.propose_identity(submission);
/// print(identity.workflow_id);
/// ```
final class HostWorkflowIdentityProvider implements WorkflowIdentityProvider {
  /// Creates a provider bound to the trusted [os_user_id].
  ///
  /// The identity must originate from an authoritative host
  /// platform implementation.
  const HostWorkflowIdentityProvider({required this.os_user_id});

  /// Authenticated owner assigned to proposed workflow identities.
  final String os_user_id;

  /// Proposes an identity for the pending [submission].
  ///
  /// Returns a new [WorkflowIdentity] containing a generated
  /// UUID, the trusted owner and the requested filesystem binding.
  ///
  /// Throws [StateError] when the submission does not represent
  /// a workflow establishment command.
  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final command = submission.command;

    if (command is! WorkflowStartEvent) {
      throw StateError('Unsupported workflow identity request.');
    }

    // Ownership originates from trusted host composition,
    // while the accepted command supplies the filesystem binding.
    return WorkflowIdentity(
      workflow_id: Uuid().v4(),
      os_user_id: os_user_id,
      target_id: command.target_id,
      root: command.root,
    );
  }
}
