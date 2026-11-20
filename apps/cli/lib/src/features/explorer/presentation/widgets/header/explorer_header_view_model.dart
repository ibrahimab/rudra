/// Immutable presentation data for the Explorer header.
///
/// The header contains the current directory and one
/// feature-contributed status line.
///
/// Explorer does not interpret the meaning of that status.
/// Workflow, filesystem or future application features
/// prepare their own status projections before rendering.
///
/// Presentation values have no application authority.
/// They do not authorize operations or represent
/// persistence locks.
///
/// Text sanitization and truncation remain the
/// responsibility of the terminal rendering backend.
///
/// Example:
/// ```dart
/// final header = ExplorerHeaderViewModel(
///   current_directory: '/workspace',
///   status_line: 'Workflow: ACTIVE',
///   emphasized: true,
/// );
/// ```
final class ExplorerHeaderViewModel {
  /// Creates an immutable header presentation snapshot.
  ///
  /// [current_directory] is the currently displayed path.
  ///
  /// [status_line] contains generic, already prepared
  /// status text supplied by the presentation layer.
  ///
  /// [emphasized] requests heading styling for the status.
  ///
  /// Empty directory and status values are invalid.
  ExplorerHeaderViewModel({
    required this.current_directory,
    this.status_line = 'Explorer ready.',
    this.emphasized = false,
  }) {
    if (current_directory.isEmpty || status_line.isEmpty) {
      throw ArgumentError('Explorer header values cannot be empty.');
    }
  }

  /// Directory currently displayed by Explorer.
  final String current_directory;

  /// Prepared feature status, without Explorer interpretation.
  final String status_line;

  /// Whether status presentation should use heading styling.
  final bool emphasized;
}
