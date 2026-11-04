import 'package:rudra_sdk/rudra_sdk.dart';

/// Immutable presentation state for Rudra's CLI welcome screen.
///
/// WelcomeModel describes the information that a terminal view
/// needs to display before the user starts an inspection.
///
/// It is a CLI-specific presentation model, not an SDK domain
/// model or a persistent inspection session.
///
/// A configured filesystem target is represented by both
/// [target_id] and [starting_directory].
///
/// When no supported target exists, both values are null.
///
/// Invariants:
/// - [product_name] must not be blank.
/// - [target_id] and [starting_directory] must either both
///   be present or both be absent.
/// - A present [target_id] must not be blank.
/// - Target-native paths are preserved without normalization.
/// - Construction performs no filesystem operations.
///
/// Example:
/// ```dart
/// final model = WelcomeModel(
///   product_name: 'Rudra',
///   target_id: 'local-macos',
///   starting_directory: TargetPath('/Users/example'),
/// );
///
/// print(model.can_inspect);
/// // true
/// ```
final class WelcomeModel {
  /// Creates the presentation state for a welcome screen.
  ///
  /// [product_name] identifies the application.
  ///
  /// [target_id] identifies an available configured target.
  ///
  /// [starting_directory] identifies its initial native path.
  ///
  /// The target information must be supplied together or
  /// omitted together.
  ///
  /// Throws [ArgumentError] for invalid configuration.
  ///
  /// This constructor does not inspect the filesystem,
  /// initialize sessions, or perform cleanup operations.
  WelcomeModel({
    required this.product_name,
    this.target_id,
    this.starting_directory,
  }) {
    if (product_name.trim().isEmpty) {
      throw ArgumentError.value(
        product_name,
        'product_name',
        'The product name must not be blank.',
      );
    }

    if ((target_id == null) != (starting_directory == null)) {
      throw ArgumentError(
        'Target ID and starting directory must be supplied together.',
      );
    }

    if (target_id != null && target_id!.trim().isEmpty) {
      throw ArgumentError.value(
        target_id,
        'target_id',
        'The target identifier must not be blank.',
      );
    }
  }

  /// Application name displayed on the welcome screen.
  final String product_name;

  /// Identifier of the configured filesystem target, if any.
  ///
  /// Null means no supported inspection target was configured.
  final String? target_id;

  /// Initial directory in the target's native path syntax.
  ///
  /// Null means no supported inspection target was configured.
  ///
  /// The path is not normalized or resolved by this model.
  final TargetPath? starting_directory;

  /// Whether a filesystem inspection target is available.
  ///
  /// This describes application configuration, not current
  /// permissions or filesystem availability.
  ///
  /// Actual inspection can still fail and must return typed
  /// SDK errors or incomplete results.
  bool get can_inspect => target_id != null;
}
