/// Native macOS implementations of Rudra host capabilities.
///
/// Provides implementations of SDK-owned host contracts for
/// injection at the host application's composition boundary.
library;

/// Native macOS operating-system identity resolution.
export 'src/macos_identity.dart';

/// Native macOS process termination coordination.
export 'src/macos_host_shutdown.dart';

/// Native macOS host ownership acquisition.
export 'src/ownership/macos_host_ownership_provider.dart';

/// Authenticated macOS Unix-domain transport.
export 'src/transports/unix/macos_unix_transport.dart';
