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
/// [on_ready] receives the verified owner and current workflow.
///
/// The operation retains ownership and application resources until shutdown.
typedef HostRunOperation = Future<void> Function({
  required HostReadyCallback on_ready,
});

/// Composes and runs the host for the current operating system.
///
/// Resolves the provisioned machine-wide database and per-user ownership
/// through native capabilities. Communication selects the native endpoint.
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
Future<void> run_local_host({required HostReadyCallback on_ready}) async {
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
    resolve_database: const MacOsHostStorage().resolve,
    require_existing_wal: true,
    target_id: local_macos_target_id,
    inspector: MacOsTargetInspector(),
  );

  const lifecycle = MacOsHostShutdown();

  // Establish termination handling before acquiring persistence
  // resources so shutdown remains coordinated during initialization.
  await lifecycle.run((shutdown) async {
    await composition.run(shutdown: shutdown, on_ready: on_ready);
  });
}
