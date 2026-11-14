import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import 'directory_inspection_issues_view_model.dart';

/// Composable presentation of typed filesystem inspection issues.
///
/// Diagnostics originate from SDK inspection results and are
/// converted into display-ready values by the filesystem presenter.
///
/// This widget never interprets native errors or filesystem paths.
///
/// All diagnostic lines use [TerminalRole.error].
///
/// A complete listing without issues occupies zero rows.
///
/// An incomplete listing without reported issues produces one
/// explicit fallback diagnostic so failures remain visible.
///
/// The widget can be composed into a normal screen or rendered
/// separately to a diagnostic output sink.
///
/// Untrusted diagnostic text is sanitized by the bare backend.
///
/// Example:
/// ```dart
/// final model = DirectoryInspectionIssuesViewModel(
///   is_complete: false,
///   issues: [],
/// );
///
/// final widget = DirectoryInspectionIssuesWidget(model);
///
/// print(widget.height);
/// // 1
/// ```
final class DirectoryInspectionIssuesWidget implements TerminalWidget {
  /// Creates a diagnostic widget from its dedicated presentation model.
  ///
  /// Construction performs no filesystem or terminal operations.
  const DirectoryInspectionIssuesWidget(this.view_model);

  /// Immutable diagnostic information consumed by this widget.
  ///
  /// Directory entries and listing layout are intentionally excluded.
  final DirectoryInspectionIssuesViewModel view_model;

  @override
  int get height {
    if (view_model.issues.isNotEmpty) {
      return view_model.issues.length;
    }

    return view_model.is_incomplete ? 1 : 0;
  }

  /// Produces one line per typed inspection issue.
  ///
  /// An incomplete observation lacking specific issues
  /// still produces an explicit diagnostic message.
  ///
  /// The widget performs no terminal or filesystem I/O.
  @override
  Iterable<TerminalLine> build(
    TerminalConstraints constraints,
  ) sync* {
    for (final issue in view_model.issues) {
      yield TerminalLine(
        '${issue.operation}: '
        '${issue.code}: '
        '${issue.path}: '
        '${issue.message}',
        role: TerminalRole.error,
      );
    }

    if (view_model.is_incomplete && view_model.issues.isEmpty) {
      yield const TerminalLine(
        'Filesystem inspection did not complete.',
        role: TerminalRole.error,
      );
    }
  }
}
