import 'package:rudra_cli/src/core/rendering/theme.dart';
import 'package:rudra_cli/src/core/rendering/widgets/terminal_widget.dart';
import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/header/explorer_header.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/header/explorer_header_view_model.dart';
import 'package:rudra_cli/src/features/workflow/explorer/workflow_explorer_view_model.dart';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests Explorer header rendering from navigation and workflow snapshots.
void main() {
  final constraints = TerminalConstraints(columns: 100);

  group('ExplorerHeader', () {
    test('displays the current directory without workflow integration', () {
      final header = ExplorerHeader(
        ExplorerHeaderViewModel(explorer: _explorer(), workflow: null),
      );

      final lines = header.build(constraints).toList();

      expect(header.height, ExplorerHeader.fixed_rows);
      expect(lines, hasLength(3));
      expect(lines[0].text, contains('RUDRA / EXPLORER'));
      expect(lines[1].text, 'Directory: /workspace');
      expect(lines[1].role, TerminalRole.path);
      expect(lines[2].text, 'Explorer ready.');
      expect(lines[2].role, TerminalRole.muted);
    });

    test('distinguishes an absent workflow from no integration', () {
      final header = ExplorerHeader(
        ExplorerHeaderViewModel(
          explorer: _explorer(),
          workflow: const WorkflowExplorerViewModel(current_workflow: null),
        ),
      );

      final lines = header.build(constraints).toList();

      expect(lines[2].text, 'Workflow: NONE');
      expect(lines[2].role, TerminalRole.muted);
    });

    test('renders the confirmed active workflow', () {
      final active = WorkflowSnapshot(
        identity: WorkflowIdentity(
          workflow_id: 'workflow-1',
          os_user_id: 'fixture-user',
          target_id: 'fixture-target',
          root: TargetPath('/workspace'),
        ),
        version: 1,
        lifecycle: WorkflowLifecycle(
          id: 'rudra.workflow.active',
          is_terminal: false,
        ),
      );

      final header = ExplorerHeader(
        ExplorerHeaderViewModel(
          explorer: _explorer(),
          workflow: WorkflowExplorerViewModel(current_workflow: active),
        ),
      );

      final lines = header.build(constraints).toList();

      expect(lines[2].text, contains('Workflow: ACTIVE'));
      expect(lines[2].text, contains('ID: workflow-1'));
      expect(lines[2].text, contains('Version: 1'));
      expect(lines[2].text, contains('Target: fixture-target'));
      expect(lines[2].role, TerminalRole.heading);
    });
  });
}

/// Creates a navigation snapshot without filesystem I/O.
ExplorerModel _explorer() {
  final root = TargetPath('/workspace');

  return ExplorerModel(
    root_directory: root,
    listing: DirectoryListing(
      target_id: 'fixture-target',
      directory: root,
      entries: const [],
      is_complete: true,
    ),
  );
}
