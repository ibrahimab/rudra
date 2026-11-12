import '../theme.dart';

/// Immutable constraints supplied by a terminal rendering backend.
///
/// Widgets receive the available terminal width without reading
/// process or platform-specific terminal properties themselves.
///
/// Example:
/// ```dart
/// final constraints = TerminalConstraints(columns: 80);
/// print(constraints.columns);
/// // 80
/// ```
final class TerminalConstraints {
  /// Creates validated terminal layout constraints.
  ///
  /// Zero columns are supported. Negative widths are rejected.
  TerminalConstraints({required this.columns}) {
    if (columns < 0) {
      throw RangeError.value(
        columns,
        'columns',
        'Terminal width cannot be negative.',
      );
    }
  }

  /// Available terminal display columns.
  final int columns;
}

/// One unstyled line produced by a terminal widget.
///
/// The line contains display data and a semantic styling role.
/// It contains no backend-specific ANSI escape sequences.
///
/// Text sanitization, width limiting, and styling belong to
/// the rendering backend.
final class TerminalLine {
  /// Creates an immutable terminal presentation line.
  const TerminalLine(
    this.text, {
    this.role = TerminalRole.text,
  });

  /// Unstyled display text.
  final String text;

  /// Semantic styling role.
  final TerminalRole role;
}

/// Common contract for composable Rudra terminal widgets.
///
/// A widget describes presentation only.
///
/// [height] is the exact number of terminal rows produced by
/// [build], independently of terminal width. Long text must
/// therefore be truncated rather than automatically wrapped.
///
/// A widget may contain child widgets and compose their output.
///
/// The terminal backend validates that the actual number of
/// generated lines matches the declared height.
///
/// Implementations must not access SDK services, perform
/// filesystem operations, or manage terminal modes.
///
/// Example:
/// ```dart
/// final widget = TerminalLabel(
///   'RUDRA',
///   role: TerminalRole.title,
/// );
///
/// print(widget.height);
/// // 1
/// ```
abstract interface class TerminalWidget {
  /// Exact number of terminal rows occupied by this widget.
  int get height;

  /// Builds presentation lines for the supplied constraints.
  ///
  /// Implementations must produce exactly [height] lines.
  ///
  /// Building a widget does not write to a terminal.
  Iterable<TerminalLine> build(TerminalConstraints constraints);
}
