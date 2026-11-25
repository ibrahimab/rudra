import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../workflow/application/workflow_application.dart';

/// Validates a requested workflow establishment against trusted
/// target configuration.
///
/// [target_id] identifies the requested configured filesystem target.
/// [root] preserves the original target-native filesystem path.
///
/// Implementations throw [ArgumentError] for unsupported targets
/// or invalid root syntax.
///
/// Validation must not establish workflow state, submit commands
/// or perform cleanup operations.
typedef WorkflowStartValidator = void Function(
  String target_id,
  TargetPath root,
);

/// Trusted application capabilities available to request handlers.
///
/// All handlers share the same retained application and authenticated
/// owner. Target-specific validation is supplied by host composition.
///
/// The context performs no application execution during construction.
final class ApplicationRequestContext {
  /// Binds request handlers to the retained [application].
  ///
  /// [validate_start] supplies trusted target-specific validation
  /// before an explicit workflow establishment is accepted.
  const ApplicationRequestContext({
    required this.application,
    required this.validate_start,
  });

  /// Authoritative owner-scoped workflow application.
  final WorkflowApplication application;

  /// Trusted target and root validation capability.
  final WorkflowStartValidator validate_start;

  /// Verifies that [session] belongs to this application's owner.
  ///
  /// Throws [StateError] before application execution when the
  /// authenticated peer identity disagrees with the retained owner.
  void require_authorized_peer(MessageSession session) {
    if (session.os_user_id != application.os_user_id) {
      throw StateError('Authenticated peer does not own this application.');
    }
  }
}
