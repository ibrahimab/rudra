import 'package:rudra_cli/src/core/rendering/theme.dart';
import 'package:rudra_cli/src/core/rendering/widgets/terminal_widget.dart';
import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/actions/explorer_actions_view_model.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/directory/explorer_directory_view_model.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/footer/explorer_footer.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/footer/explorer_footer_view_model.dart';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests Explorer footer summaries and inspection diagnostics.
void main() {
  final constraints = TerminalConstraints(columns: 120);

  group('ExplorerFooter', () {
    test('summarizes a completed directory observation', () {
      final footer = _footer(_explorer());

      final lines = footer.build(constraints).toList();

      expect(footer.height, 3);
      expect(lines, hasLength(3));
      expect(lines[0].text, contains('0 observed entries'));
      expect(lines[0].text, contains('Selected: none'));
      expect(lines[1].text, contains('No filesystem changes.'));
      expect(lines[1].role, TerminalRole.muted);
      expect(lines[2].text, contains('S Start Workflow'));
    });

    test('shows a warning for an incomplete observation', () {
      final issue = InspectionIssue(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/workspace/private'),
        message: 'Permission denied.',
      );

      final footer = _footer(_explorer(is_complete: false, issues: [issue]));

      final lines = footer.build(constraints).toList();

      expect(lines[1].role, TerminalRole.warning);
      expect(lines[1].text, contains('1 inspection issue(s)'));
      expect(lines[1].text, contains('permissionDenied'));
      expect(lines[1].text, contains('/workspace/private'));
    });

    test('shows an incomplete warning without specific issues', () {
      final footer = _footer(_explorer(is_complete: false));

      final lines = footer.build(constraints).toList();

      expect(lines[1].text, 'WARNING: Directory inspection incomplete.');
      expect(lines[1].role, TerminalRole.warning);
    });

    test('reports one-based selection and scrolling', () {
      final entries = [
        for (final name in ['a', 'b', 'c'])
          FilesystemEntry(
            path: TargetPath('/workspace/$name.txt'),
            kind: FilesystemEntryKind.regularFile,
            metadata: FilesystemMetadata(),
          ),
      ];

      final explorer = _explorer(entries: entries).with_selection(2);
      final footer = _footer(explorer, visible_row_limit: 1);

      final lines = footer.build(constraints).toList();

      expect(lines[0].text, contains('3 observed entries'));
      expect(lines[0].text, contains('Selected: 3/3'));
      expect(lines[0].text, contains('more above'));
    });
  });
}

/// Creates a footer using a shared Explorer navigation snapshot.
///
/// [explorer] supplies selection, entries and inspection diagnostics.
///
/// [visible_row_limit] is the number of allocated entry rows.
ExplorerFooter _footer(ExplorerModel explorer, {int visible_row_limit = 3}) {
  final directory = ExplorerDirectoryViewModel(
    explorer: explorer,
    visible_row_limit: visible_row_limit,
  );

  final actions = ExplorerActionsViewModel(
    explorer: explorer,
    instructions: const ['S Start Workflow'],
  );

  return ExplorerFooter(
    ExplorerFooterViewModel(directory: directory, actions: actions),
  );
}

/// Creates a directory observation entirely in memory.
///
/// [entries] contains successfully observed filesystem entries.
///
/// [is_complete] identifies whether inspection completed.
///
/// [issues] contains the corresponding typed diagnostics.
ExplorerModel _explorer({
  List<FilesystemEntry> entries = const [],
  bool is_complete = true,
  List<InspectionIssue> issues = const [],
}) {
  final root = TargetPath('/workspace');

  return ExplorerModel(
    root_directory: root,
    listing: DirectoryListing(
      target_id: 'fixture-target',
      directory: root,
      entries: entries,
      is_complete: is_complete,
      issues: issues,
    ),
  );
}
