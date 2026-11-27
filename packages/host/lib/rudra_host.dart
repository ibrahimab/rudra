/// Public application API for the Rudra host.
///
/// Exposes host composition and lifecycle operations for integration
/// with application entrypoints, service managers and other trusted
/// execution environments.
///
/// Native platform selection and persistence composition remain
/// encapsulated within the host subsystem.
///
/// Example:
/// ```dart
/// import 'package:rudra_host/rudra_host.dart';
///
/// await run_local_host(
///   on_ready: (owner, workflow) => print('Ready for $owner'),
/// );
/// ```
library;

/// Configurable host application composition.
export 'src/composition/host_composition.dart';

/// Local host execution and readiness contracts.
export 'src/composition/local_host.dart';

/// Listener policy values accepted by host composition.
export 'package:rudra_communication/rudra_communication.dart'
    show TransportConfiguration, TransportEndpoint, TransportRegistry;

/// Native capabilities available to trusted, isolated composition.
export 'src/identity/macos/macos_identity.dart';
export 'src/lifecycle/macos/macos_host_shutdown.dart';
export 'src/ownership/macos/macos_host_ownership_provider.dart';
