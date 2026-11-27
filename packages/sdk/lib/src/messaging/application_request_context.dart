import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../workflow/application/workflow_application.dart';

import '../state/publication/state_publication.dart';

import '../filesystem/messaging/list/filesystem_list_handlers.dart';

/// Validates a requested workflow establishment against trusted
/// target configuration.
///
/// [root] preserves the original target-native filesystem path.
///
/// Implementations throw [ArgumentError] for invalid target-native root syntax.
///
/// Validation must not establish workflow state, submit commands
/// or perform cleanup operations.
typedef WorkflowStartValidator = void Function(TargetPath root);

/// Trusted application capabilities available to request handlers.
///
/// All handlers share the same retained application and authenticated
/// owner. Target-specific validation is supplied by host composition.
///
/// The context performs no application execution during construction.
///
/// Example:
/// ```dart
/// final context = ApplicationRequestContext(
///   application: application,
///   publication: publication,
///   target_id: filesystem_application.target_id,
///   validate_start: validate_root,
///   filesystem_handlers: filesystem_handlers,
/// );
/// ```
final class ApplicationRequestContext {
  /// Binds request handlers to trusted application capabilities.
  ///
  /// [application] supplies authoritative application execution.
  /// [publication] supplies verified composite state subscriptions
  /// backed by the same application.
  /// [target_id] supplies the host's configured filesystem identity.
  /// [validate_start] supplies trusted target-specific validation
  /// before an explicit workflow establishment is accepted.
  /// [filesystem_handlers] supplies authoritative filesystem request
  /// execution and session-owned inspection coordination.
  const ApplicationRequestContext({
    required this.application,
    required this.publication,
    required this.target_id,
    required this.validate_start,
    required this.filesystem_handlers,
  });

  /// Authoritative owner-scoped workflow application.
  final WorkflowApplication application;

  /// Host-owned publication of verified composite application state.
  ///
  /// Shares the retained application's observation and owner scope.
  final StatePublication publication;

  /// Authoritative target identifier used for workflow establishment.
  final String target_id;

  /// Trusted target-native root validation capability.
  final WorkflowStartValidator validate_start;

  /// Host-owned filesystem inspection lifecycle and request execution.
  ///
  /// Retains inspection resources across authenticated requests
  /// until their disposal has been confirmed.
  final FilesystemListHandlers filesystem_handlers;

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
