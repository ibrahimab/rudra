import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_target_macos/rudra_target_macos.dart';

/// Holds the SDK dependencies assembled for the production CLI.
///
/// ProductSdkComposition is an application composition object,
/// not an SDK service or domain model.
///
/// It associates a configured [RudraSdk] with the target-native
/// working directory used by the CLI frontend.
///
/// Concrete target adapters must be instantiated at this
/// composition boundary, never inside the SDK.
///
/// The current production implementation supports local macOS
/// filesystem inspection.
///
/// Other platforms remain unavailable until corresponding
/// adapters have been implemented and verified.
///
/// Example:
/// ```dart
/// final composition = ProductSdkComposition.for_current_host();
///
/// if (composition != null) {
///   print(composition.sdk.target_id);
/// }
/// ```
final class ProductSdkComposition {
  /// Creates an application composition from supplied dependencies.
  ///
  /// [sdk] must already be configured for the target represented
  /// by [working_directory].
  ///
  /// This constructor supports dependency injection in CLI tests
  /// and alternative application composition environments.
  ///
  /// It performs no filesystem inspection or mutation.
  const ProductSdkComposition({
    required this.sdk,
    required this.working_directory,
  });

  /// SDK configured with the target's inspection adapter.
  ///
  /// All application-level filesystem operations must be
  /// performed through this SDK rather than directly through
  /// the underlying target adapter.
  final RudraSdk sdk;

  /// Initial target-native directory for CLI filesystem commands.
  ///
  /// The path must belong to the environment represented by [sdk].
  ///
  /// It must not be interpreted using unrelated platform rules.
  final TargetPath working_directory;

  /// Creates the production SDK composition for the local host.
  ///
  /// Currently macOS is the only implemented production target.
  ///
  /// On macOS:
  /// - Creates a [MacOsTargetInspector].
  /// - Injects it into [RudraSdk].
  /// - Associates the SDK with the local macOS target.
  /// - Captures the process working directory.
  ///
  /// On other platforms, returns null because no verified
  /// production target adapter is available yet.
  ///
  /// Unsupported platforms are never silently assigned the
  /// macOS adapter or given fabricated inspection capabilities.
  ///
  /// Native adapter initialization failures are propagated.
  /// They are not disguised as an unsupported target.
  ///
  /// No directory enumeration or entry inspection is performed.
  ///
  /// Example:
  /// ```dart
  /// final composition = ProductSdkComposition.for_current_host();
  ///
  /// if (composition != null) {
  ///   final listing = await composition.sdk.filesystem.list(
  ///     directory: composition.working_directory,
  ///   );
  ///
  ///   print(listing.is_complete);
  /// }
  /// ```
  static ProductSdkComposition? for_current_host() {
    if (!Platform.isMacOS) {
      return null;
    }

    // Only the application composition layer creates concrete
    // platform adapters. The SDK receives the shared contract.
    final TargetInspector inspector = MacOsTargetInspector();

    final sdk = RudraSdk(
      target_id: 'local-macos',
      inspector: inspector,
    );

    // The production adapter inspects the local filesystem,
    // so the process working directory is a valid target-local
    // starting point for the CLI.
    final working_directory = TargetPath(
      Directory.current.absolute.path,
    );

    return ProductSdkComposition(
      sdk: sdk,
      working_directory: working_directory,
    );
  }
}
