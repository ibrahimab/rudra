import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';

import 'host_composition.dart';
import 'macos/macos_host_composition.dart';

/// Composes and runs the host for the current operating system.
///
/// Resolves the provisioned machine-wide database and per-user ownership
/// through native capabilities. [transport_configuration] selects the listening
/// endpoints independently of persistence and exclusive host ownership.
///
/// [on_ready] receives verified application state after startup
/// operations have completed.
///
/// Returns after graceful host termination and resource disposal.
///
/// Throws [UnsupportedError] when no native host implementation
/// is available for the current operating system. Initialization,
/// workflow and persistence failures propagate to the caller.
///
/// Example:
/// ```dart
/// await run_local_host(
///   on_ready: (os_user_id, workflow) {
///     print(os_user_id);
///     print(workflow?.identity.workflow_id);
///   },
/// );
/// ```
Future<void> run_local_host({
  required HostReadyCallback on_ready,
  TransportConfiguration? transport_configuration,
}) async {
  // Select native implementations at the application composition
  // boundary, preserving the SDK runtime's platform independence.
  if (!Platform.isMacOS) {
    throw UnsupportedError(
      'A native host adapter is not available for this platform.',
    );
  }

  await run_macos_host(
    on_ready: on_ready,
    transport_configuration: transport_configuration,
  );
}
