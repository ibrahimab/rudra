import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_target_inspection/rudra_target_inspection.dart';

import '../../identity/macos/macos_identity.dart';
import '../../lifecycle/macos/macos_host_shutdown.dart';
import '../../ownership/macos/macos_host_ownership_provider.dart';
import '../../storage/macos/macos_host_storage.dart';
import '../host_composition.dart';

/// Stable filesystem target identity retained in macOS observations and history.
const _target_id = 'local-macos';

/// Runs the native composition with trusted macOS capabilities.
///
/// [on_ready] receives verified state before authenticated admission.
/// [transport_configuration] optionally selects the listening endpoints.
/// Startup and disposal failures propagate to the caller.
///
/// Example:
/// ```dart
/// await run_macos_host(on_ready: (owner, workflow) => print(owner));
/// ```
Future<void> run_macos_host({
  required HostReadyCallback on_ready,
  TransportConfiguration? transport_configuration,
}) async {
  final composition = HostComposition(
    identity_provider: const MacOsHostIdentity(),
    ownership_provider: const MacOsHostOwnershipProvider(),
    resolve_database: const MacOsHostStorage().resolve,
    require_existing_wal: true,
    target_id: _target_id,
    inspector: MacOsTargetInspector(),
    transport_configuration: transport_configuration,
  );

  // Catch termination signals before acquiring host resources.
  await const MacOsHostShutdown().run(
    (shutdown) => composition.run(shutdown: shutdown, on_ready: on_ready),
  );
}
