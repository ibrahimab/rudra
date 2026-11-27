import 'package:rudra_cli/src/core/rendering/theme.dart';
import 'package:rudra_cli/src/core/rendering/widgets/terminal_widget.dart';
import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/header/explorer_header.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/header/explorer_header_view_model.dart';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests Explorer header rendering from navigation and contributed status.
void main() {
  final constraints = TerminalConstraints(columns: 100);

  group('ExplorerHeader', () {
    test('displays the current directory without contributed status', () {
      final header = ExplorerHeader(
        ExplorerHeaderViewModel(explorer: _explorer()),
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

    test('uses the supplied status role', () {
      final header = ExplorerHeader(
        ExplorerHeaderViewModel(
          explorer: _explorer(),
          statuses: const [
            TerminalLine('Workflow: NONE', role: TerminalRole.muted),
          ],
        ),
      );

      final lines = header.build(constraints).toList();

      expect(lines[2].text, 'Workflow: NONE');
      expect(lines[2].role, TerminalRole.muted);
    });

    test('joins contributed statuses in one row', () {
      final header = ExplorerHeader(
        ExplorerHeaderViewModel(
          explorer: _explorer(),
          statuses: const [
            TerminalLine(
              'Workflow: ACTIVE  |  ID: workflow-1  |  Version: 1  |  Target: fixture-target',
              role: TerminalRole.heading,
            ),
            TerminalLine('Probe ready'),
          ],
        ),
      );

      final lines = header.build(constraints).toList();

      expect(lines[2].text, contains('Workflow: ACTIVE'));
      expect(lines[2].text, contains('ID: workflow-1'));
      expect(lines[2].text, contains('Version: 1'));
      expect(lines[2].text, contains('Target: fixture-target'));
      expect(lines[2].text, endsWith('  |  Probe ready'));
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
