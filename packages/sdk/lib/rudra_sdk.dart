/// Public application-facing SDK for Rudra.
///
/// This library exposes the shared domain models, application
/// services, and platform-independent contracts consumed by
/// Rudra frontends.
///
/// CLI, Flutter, and other applications should consume SDK
/// functionality through this public library rather than
/// importing internal implementation files.
///
/// The SDK is responsible for application behavior and
/// domain policy. Concrete filesystem and persistence
/// implementations are supplied through dependency injection.
///
/// The SDK must remain independent of:
/// - CLI frameworks and terminal presentation.
/// - Flutter and graphical presentation.
/// - Platform-specific filesystem implementations.
/// - Concrete persistence implementations.
///
/// Filesystem observations are read-only and must never
/// be interpreted as authorization to modify or delete files.
///
/// Example:
/// ```dart
/// import 'package:rudra_sdk/rudra_sdk.dart';
///
/// final sdk = RudraSdk();
/// try {
///   await sdk.connect();
///   final listing = await sdk.filesystem.list(
///     directory: TargetPath('/Users/example'),
///   );
///   print(listing.is_complete);
/// } finally {
///   await sdk.close();
/// }
/// ```
library;

/// Platform-independent target contracts.
export 'package:rudra_target_contracts/rudra_target_contracts.dart';

/// Filesystem inspection API.
export 'src/filesystem/filesystem.dart';

/// Workflow engine and domain API.
export 'src/workflow/workflow.dart';

/// Immutable composite SDK application state.
export 'src/state/rudra_state.dart';

/// Application-state synchronization availability.
export 'src/state/observation/state_synchronization_status.dart';

/// Authoritative application-state publication and subscription contracts.
export 'src/state/publication/state_publication.dart';
export 'src/state/publication/state_publication_snapshot.dart';

/// Composite application state messaging contracts.
export 'src/state/messaging/state_messaging.dart';

/// Application messaging contribution and composition contracts.
export 'src/messaging/application_messaging_module.dart';

/// Trusted application request execution and feature contributions.
export 'src/messaging/application_request_context.dart';
export 'src/messaging/application_request_handler_module.dart';
export 'src/messaging/application_message_codecs.dart';
export 'src/messaging/standard_messaging_modules.dart';

/// Portable host runtime and platform contracts.
export 'src/host/host.dart';

/// Explicit host connectivity configuration.
export 'package:rudra_communication/rudra_communication.dart'
    show ConnectionParams, MacOsUnixTransport;

export 'src/client/client_connection.dart' show ClientCommunicationFactory;

/// Main SDK application facade.
export 'src/rudra_sdk.dart';

/// Human-readable application name.
const String application_name = 'Rudra';
