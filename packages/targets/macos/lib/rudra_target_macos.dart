/// Read-only macOS filesystem inspection adapter for Rudra.
///
/// Implements the platform-independent [TargetInspector] contract
/// using native Darwin filesystem operations.
///
/// Supported operations:
/// - [MacOsTargetInspector.capabilities_for]: Discover inspection
///   capabilities applicable to a filesystem location.
/// - [MacOsTargetInspector.inspect]: Inspect one filesystem entry
///   without following its final symbolic link.
/// - [MacOsTargetInspector.list_directory]: Lazily enumerate the
///   immediate children of a directory.
/// - [MacOsTargetInspector.read_symbolic_link]: Read a symbolic
///   link's stored destination without resolving it.
///
/// The adapter reports filesystem observations only.
///
/// It does not:
/// - Recursively traverse directories.
/// - Calculate aggregate directory sizes.
/// - Estimate recoverable disk space.
/// - Make cleanup or deletion decisions.
/// - Modify or delete filesystem contents.
///
/// Important limitations:
/// - Requires a supported 64-bit macOS environment.
/// - Intermediate symbolic links may still be traversed.
/// - Filesystem observations are not atomic snapshots.
/// - Directory contents may change during enumeration.
/// - Filesystem metadata may be incomplete or unavailable.
/// - Inspection does not establish session-root containment.
///
/// Native errors are translated into platform-independent
/// [TargetInspectionException] values.
///
/// The SDK remains responsible for recursive traversal,
/// aggregation, session management, and cleanup safety.
///
/// Example:
/// ```dart
/// final TargetInspector inspector = MacOsTargetInspector();
///
/// final capabilities = await inspector.capabilities_for(
///   TargetPath('/tmp'),
/// );
///
/// final entry = await inspector.inspect(
///   TargetPath('/tmp'),
/// );
///
/// print(entry.kind);
/// print(capabilities.statuses);
/// ```
///
/// No cleanup execution functionality is exposed by this package.
library;

import 'package:rudra_target_contracts/rudra_target_contracts.dart';

export 'src/mac_os_target_inspector.dart';
