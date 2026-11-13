/// Immutable presentation data required by ExplorerHeader.
///
/// The header does not depend on the directory listing,
/// selection state, or Explorer navigation controller.
///
/// The current directory retains its target-native spelling.
/// Sanitization belongs to the terminal rendering backend.
///
/// Example:
/// ```dart
/// final model = ExplorerHeaderViewModel(
///   current_directory: '/workspace',
/// );
///
/// print(model.current_directory);
/// // /workspace
/// ```
final class ExplorerHeaderViewModel {
  /// Creates a header model from an observed directory path.
  ///
  /// Throws [ArgumentError] when the directory is empty.
  ExplorerHeaderViewModel({
    required this.current_directory,
  }) {
    if (current_directory.isEmpty) {
      throw ArgumentError.value(
        current_directory,
        'current_directory',
        'The current directory cannot be empty.',
      );
    }
  }

  /// Directory currently displayed by the Explorer.
  final String current_directory;
}
