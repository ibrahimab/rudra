/// Immutable presentation data required by ExplorerFooter.
///
/// The footer contains three prepared display lines and the
/// severity of the inspection-status line.
///
/// Its data is prepared by ExplorerPresenter from authoritative
/// SDK observations and the current directory viewport.
///
/// The footer neither reconstructs navigation state nor
/// independently interprets workflow events.
///
/// The strings remain unescaped until the terminal backend
/// sanitizes and renders them.
///
/// Example:
/// ```dart
/// final footer = ExplorerFooterViewModel(
///   summary: '0 observed entries',
///   inspection_status: 'Read-only exploration.',
///   is_warning: false,
///   navigation_hints: 'Q Quit',
/// );
/// ```
final class ExplorerFooterViewModel {
  /// Creates an immutable footer presentation.
  ///
  /// Each text value must be nonempty.
  ///
  /// Throws [ArgumentError] for empty display lines.
  ExplorerFooterViewModel({
    required this.summary,
    required this.inspection_status,
    required this.is_warning,
    required this.navigation_hints,
  }) {
    if (summary.isEmpty ||
        inspection_status.isEmpty ||
        navigation_hints.isEmpty) {
      throw ArgumentError(
        'Explorer footer display lines must not be empty.',
      );
    }
  }

  /// Observed-entry count, selection, and scroll summary.
  final String summary;

  /// Inspection completeness or diagnostic message.
  final String inspection_status;

  /// Whether [inspection_status] requires warning styling.
  final bool is_warning;

  /// Keyboard instructions or closed-Explorer message.
  final String navigation_hints;
}
