import 'dart:io';

import 'package:rudra_host_macos/rudra_host_macos.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_target_macos/rudra_target_macos.dart';

import 'host_composition.dart';

/// Receives verified application state after host initialization.
///
/// The supplied owner identifies the trusted operating-system user.
/// The workflow snapshot represents the restored current workflow,
/// or null when no unfinished workflow exists.
typedef HostReadyCallback = void Function(
  String os_user_id,
  WorkflowSnapshot? workflow,
);

/// Executes a configured local host lifecycle.
///
/// The operation retains application resources until shutdown.
/// Callers supply configuration and receive startup confirmation
/// through the readiness callback.
typedef HostRunOperation = Future<void> Function({
  required Directory data_directory,
  required bool start_workflow,
  required HostReadyCallback on_ready,
});

/// Composes and runs the host for the current operating system.
///
/// [data_directory] identifies an existing, dedicated development
/// persistence directory.
///
/// [start_workflow] explicitly requests workflow establishment
/// at the current absolute working directory.
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
///   data_directory: development_directory,
///   start_workflow: false,
///   on_ready: (os_user_id, workflow) {
///     print(os_user_id);
///     print(workflow?.identity.workflow_id);
///   },
/// );
/// ```
Future<void> run_local_host({
  required Directory data_directory,
  required bool start_workflow,
  required HostReadyCallback on_ready,
}) async {
  // Select native implementations at the application composition
  // boundary, preserving the SDK runtime's platform independence.
  if (!Platform.isMacOS) {
    throw UnsupportedError(
      'A native host adapter is not available for this platform.',
    );
  }

  final composition = HostComposition(
    identity_provider: const MacOsHostIdentity(),
    ownership_provider: const MacOsHostOwnershipProvider(),
    data_directory: data_directory,
    target_id: 'local-macos',
    inspector: MacOsTargetInspector(),
  );

  // Only an explicitly requested development operation may
  // establish a workflow during host initialization.
  final startup_root = start_workflow
      ? TargetPath(Directory.current.absolute.path)
      : null;

  const lifecycle = MacOsHostShutdown();

  // Establish termination handling before acquiring persistence
  // resources so shutdown remains coordinated during initialization.
  await lifecycle.run((shutdown) async {
    await composition.run(
      shutdown: shutdown,
      startup_root: startup_root,
      on_ready: on_ready,
    );
  });
}
