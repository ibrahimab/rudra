/// Public application API for the Rudra host.
///
/// Exposes host composition and lifecycle operations for integration
/// with application entrypoints, service managers and other trusted
/// execution environments.
///
/// Native platform selection and persistence composition remain
/// encapsulated within the host application.
///
/// Example:
/// ```dart
/// import 'package:rudra_host/rudra_host.dart';
///
/// final HostRunOperation run_host = run_local_host;
/// ```
library;

/// Configurable host application composition.
export 'src/composition/host_composition.dart';

/// Local host execution and readiness contracts.
export 'src/composition/local_host.dart';
