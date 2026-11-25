/// Authenticated local communication infrastructure.
///
/// Provides a communication facade, typed application messaging,
/// message codec registration, portable transport contracts,
/// native transport implementations and concurrent session management.
///
/// Consumers supply trusted endpoint configuration and retain
/// responsibility for their application-specific behavior.
///
/// Example:
/// ```dart
/// import 'package:rudra_communication/rudra_communication.dart';
///
/// final communication = Communication();
///
/// await communication.run(
///   scope_directory: scope,
///   os_user_id: trusted_owner,
///   shutdown: shutdown.future,
///   handle_connection: handle_connection,
/// );
/// ```
library;

/// Application-facing communication API.
export 'src/communication.dart';

/// Typed application messaging and handler registration.
export 'src/messaging/message.dart';
export 'src/messaging/message_codec.dart';
export 'src/messaging/message_codec_registry.dart';
export 'src/messaging/request_handler_registry.dart';

/// Communication protocol failure classification.
export 'src/messaging/protocol/protocol_exception.dart';

/// Portable transport capability contracts.
export 'src/transport/contracts/transport.dart';
export 'src/transport/contracts/transport_connection.dart';
export 'src/transport/contracts/transport_listener.dart';

/// Object-level communication session contract.
export 'src/sessions/message_session.dart';

/// Concurrent connection lifecycle coordination.
export 'src/sessions/connection_service.dart';

/// Native macOS transport implementation.
export 'src/transport/macos/unix/macos_unix_transport.dart';
