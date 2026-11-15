import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import 'explorer_header_view_model.dart';

/// Renders the Explorer title, current directory, and workflow summary.
///
/// This widget consumes prepared presentation data only.
/// It does not access the SDK, submit events, or load persistence.
///
/// All three rows have fixed height. Long values are sanitized
/// and truncated by the shared terminal rendering backend.
final class ExplorerHeader implements TerminalWidget {
  /// Creates the header from its independent presentation model.
  const ExplorerHeader(this.view_model);

  /// Immutable presentation snapshot.
  final ExplorerHeaderViewModel view_model;

  /// Fixed layout height, including the workflow summary.
  static const int fixed_rows = 3;

  @override
  int get height => fixed_rows;

  /// Builds exactly three terminal lines.
  ///
  /// Workflow status is descriptive. It must not be treated
  /// as authorization to perform filesystem operations.
  @override
  Iterable<TerminalLine> build(TerminalConstraints constraints) sync* {
    yield const TerminalLine(
      'RUDRA / EXPLORER  |  FILESYSTEM READ ONLY',
      role: TerminalRole.title,
    );

    yield TerminalLine(
      'Directory: ${view_model.current_directory}',
      role: TerminalRole.path,
    );

    if (view_model.has_active_workflow) {
      yield TerminalLine(
        'Workflow: ACTIVE'
        '  |  ID: ${view_model.workflow_id}'
        '  |  Version: ${view_model.workflow_version}'
        '  |  Target: ${view_model.workflow_target_id}',
        role: TerminalRole.heading,
      );

      return;
    }

    if (view_model.has_pending_workflow) {
      yield TerminalLine(
        'Workflow: PENDING'
        '  |  Submission: ${view_model.pending_submission_id}',
        role: TerminalRole.muted,
      );

      return;
    }

    yield const TerminalLine('Workflow: NOT LOADED', role: TerminalRole.muted);
  }
}
