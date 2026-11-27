import 'package:rudra_cli/src/core/rendering/widgets/terminal_widget.dart';
import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/actions/explorer_actions.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/actions/explorer_actions_view_model.dart';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests the keyboard instructions displayed by Explorer.
void main() {
  final constraints = TerminalConstraints(columns: 120);

  group('ExplorerActions', () {
    test('renders navigation and Quit without contributions', () {
      final actions = _actions();

      final lines = actions.build(constraints).toList();

      expect(actions.height, 1);
      expect(lines, hasLength(1));
      expect(lines.single.text, contains('Up/Down Select'));
      expect(lines.single.text, contains('Q Quit'));
      expect(lines.single.text, isNot(contains('Start Workflow')));
      expect(lines.single.text, isNot(contains('Stop Workflow')));
    });

    test('renders the supplied Start hint', () {
      final actions = _actions(instructions: const ['S Start Workflow']);

      final line = actions.build(constraints).single.text;

      expect(line, contains('S Start Workflow'));
      expect(line, isNot(contains('X Stop Workflow')));
    });

    test('renders multiple contributed shortcuts in order', () {
      final actions = _actions(
        instructions: const ['X Stop Workflow', 'P Probe'],
      );

      final line = actions.build(constraints).single.text;

      expect(line, contains('X Stop Workflow  P Probe  Q Quit'));
      expect(line, isNot(contains('S Start Workflow')));
    });

    test('shows the closed message without keyboard instructions', () {
      final explorer = _explorer().close();

      final actions = ExplorerActions(
        ExplorerActionsViewModel(
          explorer: explorer,
          instructions: const ['S Start Workflow'],
        ),
      );

      final line = actions.build(constraints).single.text;

      expect(line, 'Explorer closed.');
      expect(line, isNot(contains('Q Quit')));
    });
  });
}

/// Creates the keyboard-instruction widget.
///
/// [instructions] supplies contributed shortcut hints.
ExplorerActions _actions({List<String> instructions = const []}) {
  return ExplorerActions(
    ExplorerActionsViewModel(explorer: _explorer(), instructions: instructions),
  );
}

/// Creates an in-memory Explorer navigation snapshot.
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
