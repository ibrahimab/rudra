import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import 'filesystem/filesystem_service.dart';

/// The public application facade for Rudra's shared SDK.
///
/// RudraSdk provides a single entry point for application
/// services consumed by CLI, Flutter, and other frontends.
///
/// The SDK owns application-level orchestration and domain
/// behavior while concrete target implementations are supplied
/// through dependency injection.
///
/// This facade currently exposes filesystem inspection through
/// [filesystem].
///
/// Additional services will be introduced incrementally as
/// their domain contracts and implementations are established.
///
/// Each instance is bound to one configured filesystem target.
///
/// The SDK does not:
/// - Detect or instantiate native platform adapters.
/// - Depend on CLI or Flutter presentation frameworks.
/// - Access SQLite or other concrete persistence adapters.
/// - Perform filesystem operations during construction.
/// - Create or modify inspection sessions implicitly.
/// - Authorize or execute filesystem cleanup.
///
/// Constructing an SDK does not inspect or modify the target.
///
/// Example:
/// ```dart
/// final sdk = RudraSdk(
///   target_id: 'local-macos',
///   inspector: target_inspector,
/// );
///
/// final listing = await sdk.filesystem.list(
///   directory: TargetPath('/Users/example'),
/// );
///
/// print(listing.target_id);
/// print(listing.is_complete);
/// ```
final class RudraSdk {
  /// Creates an SDK configured for one filesystem target.
  ///
  /// [target_id] identifies the configured target environment.
  ///
  /// [inspector] provides read-only filesystem observations
  /// through the platform-independent [TargetInspector] contract.
  ///
  /// The application composition boundary is responsible for
  /// supplying an inspector that corresponds to [target_id].
  ///
  /// Throws [ArgumentError] when [target_id] is blank.
  ///
  /// No filesystem inspection, session initialization,
  /// persistence access, or cleanup is performed.
  ///
  /// Example:
  /// ```dart
  /// final sdk = RudraSdk(
  ///   target_id: 'local-macos',
  ///   inspector: target_inspector,
  /// );
  ///
  /// print(sdk.target_id);
  /// // local-macos
  /// ```
  RudraSdk({
    required String target_id,
    required TargetInspector inspector,
  }) : filesystem = FilesystemService(
          target_id: target_id,
          inspector: inspector,
        );

  /// Provides platform-independent filesystem operations.
  ///
  /// This service is initialized with the target inspector
  /// supplied during SDK construction.
  ///
  /// It exposes standardized filesystem results without
  /// requiring frontend consumers to coordinate native
  /// inspection operations themselves.
  ///
  /// Filesystem inspection is read-only.
  ///
  /// Accessing this property performs no filesystem operations.
  final FilesystemService filesystem;

  /// Identifies the target associated with this SDK instance.
  ///
  /// The identifier is delegated to [filesystem] to avoid
  /// maintaining duplicate target configuration state.
  ///
  /// The identifier is scoped to the application's configured
  /// targets and is not guaranteed to be globally unique.
  String get target_id => filesystem.target_id;
}
