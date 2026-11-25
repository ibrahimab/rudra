/// Authenticated local communication infrastructure.
///
/// Provides portable transport contracts, native transport
/// implementations and concurrent connection coordination.
///
/// Consumers supply trusted endpoint configuration and remain
/// responsible for their application-specific behavior.
///
/// Example:
/// ```dart
/// import 'package:rudra_communication/rudra_communication.dart';
///
/// final transport = MacOsUnixTransport();
///
/// final listener = await transport.listen(
///   scope_directory: directory,
///   os_user_id: trusted_owner,
/// );
///
/// await listener.close();
/// ```
library;

/// Portable transport capability contracts.
export 'src/transport/contracts/transport.dart';
export 'src/transport/contracts/transport_connection.dart';
export 'src/transport/contracts/transport_listener.dart';

/// Concurrent connection lifecycle coordination.
export 'src/sessions/connection_service.dart';

/// Native macOS transport implementation.
export 'src/transport/macos/unix/macos_unix_transport.dart';
