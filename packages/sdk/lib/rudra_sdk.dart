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
/// final directory = TargetPath('/Users/example');
///
/// final listing = DirectoryListing(
///   target_id: 'local-macos',
///   directory: directory,
///   entries: [],
///   is_complete: true,
/// );
///
/// print(listing.is_complete);
/// // true
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

/// Application messaging contribution and composition contracts.
export 'src/messaging/application_messaging_module.dart';
export 'src/messaging/application_message_codecs.dart';
export 'src/messaging/standard_messaging_modules.dart';

/// Portable host runtime and platform contracts.
export 'src/host/host.dart';

/// Main SDK application facade.
export 'src/rudra_sdk.dart';

/// Human-readable application name.
const String application_name = 'Rudra';
