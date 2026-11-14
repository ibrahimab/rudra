/// Immutable presentation data for the configured filesystem target.
///
/// Target identity and starting directory are either both
/// available or both absent.
///
/// Absence represents an unsupported inspection target,
/// not a failed filesystem operation.
///
/// Paths retain their target-native spelling and must never
/// be interpreted as operational host filesystem paths.
///
/// Example:
/// ```dart
/// final model = WelcomeTargetViewModel(
///   target_id: 'local-macos',
///   starting_directory: '/workspace',
/// );
///
/// print(model.can_inspect);
/// // true
/// ```
final class WelcomeTargetViewModel {
  /// Creates a validated target presentation.
  ///
  /// Throws [ArgumentError] for missing paired values or
  /// blank target identifiers and directory paths.
  WelcomeTargetViewModel({
    this.target_id,
    this.starting_directory,
  }) {
    if ((target_id == null) != (starting_directory == null)) {
      throw ArgumentError(
        'Target ID and starting directory must be '
        'provided together.',
      );
    }

    if (target_id != null && target_id!.trim().isEmpty) {
      throw ArgumentError.value(
        target_id,
        'target_id',
        'The target identifier must not be blank.',
      );
    }

    if (starting_directory != null && starting_directory!.trim().isEmpty) {
      throw ArgumentError.value(
        starting_directory,
        'starting_directory',
        'The starting directory must not be blank.',
      );
    }
  }

  /// Configured target identifier, when available.
  final String? target_id;

  /// Target-native starting directory, when available.
  final String? starting_directory;

  /// Whether a supported inspection target is configured.
  bool get can_inspect => target_id != null;
}
