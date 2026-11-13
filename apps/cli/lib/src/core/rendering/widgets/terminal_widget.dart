import '../theme.dart';

/// Immutable layout constraints supplied to terminal widgets.
///
/// [columns] determines whether horizontal output is bounded.
///
/// A non-null value limits each rendered line to that number
/// of estimated terminal display columns.
///
/// Null represents unbounded output, appropriate for redirected
/// command output, logs, and non-interactive presentation.
///
/// Unbounded output is still sanitized. It is never truncated
/// solely to an arbitrary terminal width.
///
/// Widgets requiring an interactive viewport must call
/// [require_bounded_columns] instead of assuming a width.
///
/// Example:
/// ```dart
/// final interactive = TerminalConstraints(columns: 80);
/// final redirected = TerminalConstraints();
///
/// print(interactive.require_bounded_columns());
/// // 80
///
/// print(redirected.columns);
/// // null
/// ```
final class TerminalConstraints {
  /// Creates immutable terminal constraints.
  ///
  /// Null means unbounded. Zero is a valid bounded width.
  ///
  /// Throws [RangeError] for a negative width.
  TerminalConstraints({this.columns}) {
    final width = columns;

    if (width != null && width < 0) {
      throw RangeError.value(
        width,
        'columns',
        'Terminal width cannot be negative.',
      );
    }
  }

  /// Maximum display columns, or null for unbounded output.
  final int? columns;

  /// Whether the rendering backend imposes a width limit.
  bool get is_bounded => columns != null;

  /// Returns the required fixed terminal width.
  ///
  /// Interactive widgets use this method to fail explicitly
  /// when accidentally rendered in an unbounded context.
  ///
  /// Throws [StateError] when no bounded width was supplied.
  int require_bounded_columns() {
    final width = columns;

    if (width == null) {
      throw StateError(
        'This widget requires bounded terminal columns.',
      );
    }

    return width;
  }
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
