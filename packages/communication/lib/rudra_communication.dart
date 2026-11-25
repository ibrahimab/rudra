/// Authenticated object-level application communication.
///
/// Provides typed application messaging, codec and handler
/// registration, portable transport contracts and native
/// communication implementations.
///
/// Communication owns session construction, protocol processing,
/// request correlation and resource disposal.
///
/// Consumers supply trusted endpoint configuration and their
/// application-specific message representations and behavior.
///
/// Example:
/// ```dart
/// import 'package:rudra_communication/rudra_communication.dart';
///
/// final communication = Communication(
///   codecs: codecs,
///   handlers: handlers,
/// );
///
/// final session = await communication.connect(
///   scope_directory: scope,
///   os_user_id: trusted_owner,
/// );
///
/// try {
///   final response = await session.request(
///     const EchoRequest('Hello'),
///   );
/// } finally {
///   try {
///     await session.close();
///   } finally {
///     await communication.done;
///   }
/// }
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

/// Object-level communication session contracts and configuration.
export 'src/sessions/message_session.dart';
export 'src/sessions/message_session_exception.dart';
export 'src/sessions/message_session_options.dart';

/// Explicitly selectable native macOS transport implementation.
export 'src/transport/macos/unix/macos_unix_transport.dart';
