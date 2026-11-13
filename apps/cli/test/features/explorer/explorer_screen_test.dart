import 'package:rudra_cli/src/core/rendering/widgets/terminal_widget.dart';

import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';

import 'package:rudra_cli/src/features/explorer/presentation/bare_explorer_renderer.dart';
import 'package:rudra_cli/src/features/explorer/presentation/explorer_presenter.dart';
import 'package:rudra_cli/src/features/explorer/presentation/explorer_view_model.dart';

import 'package:rudra_cli/src/features/explorer/presentation/widgets/directory/explorer_directory.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/footer/explorer_footer.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/header/explorer_header.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/explorer_screen.dart';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests Explorer's widget composition and layout contracts.
///
/// These tests are independent of terminal modes, native
/// filesystem access, persistence, and workflow processing.
void main() {
  group('ExplorerScreen', () {
    test('derives fixed height from its child widgets', () {
      final view_model = _view_model(
        visible_row_limit: 2,
      );

      final header = ExplorerHeader(view_model.header);
      final directory = ExplorerDirectory(view_model.directory);
      final footer = ExplorerFooter(view_model.footer);
      final screen = ExplorerScreen(view_model);

      expect(
        ExplorerScreen.fixed_rows,
        header.height + ExplorerDirectory.heading_rows + footer.height,
      );

      expect(
        screen.height,
        header.height + directory.height + footer.height,
      );

      expect(
        screen.height,
        ExplorerScreen.fixed_rows + view_model.directory.visible_row_limit,
      );
    });

    test('composes children in the expected order', () {
      final screen = ExplorerScreen(
        _view_model(visible_row_limit: 2),
      );

      final lines = screen
          .build(
            TerminalConstraints(columns: 80),
          )
          .toList();

      expect(lines, hasLength(screen.height));

      expect(lines[0].text, 'RUDRA / EXPLORER  |  READ ONLY');
      expect(lines[1].text, 'Directory: /fixture');
      expect(lines[2].text, contains('NAME'));

      expect(lines[3].text, contains('(empty directory)'));
      expect(lines[4].text, isEmpty);

      expect(lines[5].text, contains('0 observed entries'));
      expect(lines[6].text, contains('No filesystem changes.'));
      expect(lines[7].text, contains('Q Quit'));
    });

    test('supports a zero-height entry viewport', () {
      final view_model = _view_model(
        visible_row_limit: 0,
      );

      final directory = ExplorerDirectory(view_model.directory);
      final screen = ExplorerScreen(view_model);

      expect(directory.height, ExplorerDirectory.heading_rows);
      expect(screen.height, ExplorerScreen.fixed_rows);

      final lines = screen
          .build(
            TerminalConstraints(columns: 80),
          )
          .toList();

      expect(lines, hasLength(ExplorerScreen.fixed_rows));

      // No entry placeholder is emitted without an entry row.
      expect(
        lines.any(
          (line) => line.text.contains('(empty directory)'),
        ),
        isFalse,
      );
    });

    test('the bare renderer reports composed fixed height', () {
      final output = StringBuffer();

      final renderer = BareExplorerRenderer(
        output: output,
        terminal_columns: () => 80,
      );

      final view_model = _view_model(
        visible_row_limit: 2,
      );

      expect(renderer.fixed_rows, ExplorerScreen.fixed_rows);

      renderer.render(view_model);

      final rendered_lines = output.toString().split('\n');

      // The final split item represents the trailing newline.
      expect(
        rendered_lines.length,
        ExplorerScreen.fixed_rows + 2 + 1,
      );

      expect(rendered_lines.first, contains('RUDRA / EXPLORER'));
      expect(rendered_lines[1], 'Directory: /fixture');
      expect(rendered_lines.last, isEmpty);
    });

    test('the composed screen preserves terminal output semantics', () {
      final view_model = _view_model(
        visible_row_limit: 1,
        root: '/fixture/unsafe\x1B[2J',
      );

      final output = StringBuffer();

      final renderer = BareExplorerRenderer(
        output: output,
        terminal_columns: () => 80,
      );

      renderer.render(view_model);

      expect(output.toString(), contains('unsafe?[2J'));
      expect(output.toString(), isNot(contains('\x1B[2J')));
    });
  });
}

/// Creates an immutable Explorer presentation for widget tests.
///
/// The observed directory is empty and entirely in memory.
///
/// No filesystem operation occurs during construction.
ExplorerViewModel _view_model({
  required int visible_row_limit,
  String root = '/fixture',
}) {
  final directory = TargetPath(root);

  final model = ExplorerModel(
    root_directory: directory,
    listing: DirectoryListing(
      target_id: 'fixture-target',
      directory: directory,
      entries: const [],
      is_complete: true,
    ),
  );

  return const ExplorerPresenter().present(
    model,
    visible_row_limit: visible_row_limit,
  );
}
