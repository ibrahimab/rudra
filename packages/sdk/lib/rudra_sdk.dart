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

/// Platform-independent target contracts and filesystem models.
export 'package:rudra_target_contracts/rudra_target_contracts.dart';

/// Standardized filesystem inspection response models.
export 'src/filesystem/directory_listing.dart';
export 'src/filesystem/inspection_issue.dart';

/// Workflow domain events, identity, and immutable lifecycle states.
export 'src/workflow/workflow_identity.dart';
export 'src/workflow/workflow_event.dart';
export 'src/workflow/workflow_state.dart';

export 'src/rudra_sdk.dart';
export 'src/filesystem/filesystem_service.dart';

/// Human-readable name of the Rudra application.
///
/// This constant is independent of platform and presentation.
const String application_name = 'Rudra';
