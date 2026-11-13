import 'package:rudra_cli/src/core/rendering/theme.dart';
import 'package:rudra_cli/src/core/rendering/widgets/terminal_widget.dart';

import 'package:rudra_cli/src/features/explorer/presentation/explorer_view_model.dart';

import 'package:rudra_cli/src/features/explorer/presentation/widgets/directory/explorer_directory.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/directory/explorer_directory_view_model.dart';

import 'package:rudra_cli/src/features/explorer/presentation/widgets/footer/explorer_footer.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/footer/explorer_footer_view_model.dart';

import 'package:rudra_cli/src/features/explorer/presentation/widgets/header/explorer_header.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/header/explorer_header_view_model.dart';

import 'package:test/test.dart';

/// Tests Explorer components independently of the screen.
///
/// The tests verify each widget's own presentation contract,
/// immutable data, and composition without a shared flat model.
///
/// No SDK services, terminal modes, or filesystem I/O are used.
void main() {
  final constraints = TerminalConstraints(columns: 80);

  group('ExplorerHeaderViewModel', () {
    test('renders independently using its own data', () {
      final model = ExplorerHeaderViewModel(
        current_directory: '/workspace/src',
      );

      final widget = ExplorerHeader(model);
      final lines = widget.build(constraints).toList();

      expect(widget.height, 2);
      expect(lines[0].text, contains('RUDRA / EXPLORER'));
      expect(lines[1].text, 'Directory: /workspace/src');
      expect(lines[1].role, TerminalRole.path);
    });

    test('rejects an empty current directory', () {
      expect(
        () => ExplorerHeaderViewModel(current_directory: ''),
        throwsArgumentError,
      );
    });
  });

  group('ExplorerDirectoryViewModel', () {
    test('renders an empty viewport independently', () {
      final model = _empty_directory();
      final widget = ExplorerDirectory(model);

      final lines = widget.build(constraints).toList();

      expect(model.is_empty, isTrue);
      expect(widget.height, 4);
      expect(lines[0].text, contains('NAME'));
      expect(lines[1].text, contains('(empty directory)'));
      expect(lines[2].text, isEmpty);
      expect(lines[3].text, isEmpty);
    });

    test('retains immutable viewport rows', () {
      final model = _empty_directory();

      expect(
        () => model.visible_rows.clear(),
        throwsUnsupportedError,
      );
    });

    test('rejects viewport and entry-count inconsistencies', () {
      expect(
        () => ExplorerDirectoryViewModel(
          total_entries: 1,
          visible_row_limit: 1,
          first_visible_index: 0,
          selected_index: 0,
          selected_visible_index: 0,
          visible_rows: [],
          is_complete: true,
        ),
        throwsArgumentError,
      );
    });

    test('does not describe incomplete observations as empty', () {
      final model = ExplorerDirectoryViewModel(
        total_entries: 0,
        visible_row_limit: 1,
        first_visible_index: 0,
        selected_index: null,
        selected_visible_index: null,
        visible_rows: [],
        is_complete: false,
      );

      expect(model.is_empty, isFalse);
      expect(model.is_incomplete, isTrue);
    });
  });

  group('ExplorerFooterViewModel', () {
    test('renders independently using prepared display lines', () {
      final model = ExplorerFooterViewModel(
        summary: '3 observed entries',
        inspection_status: 'WARNING: Directory inspection incomplete.',
        is_warning: true,
        navigation_hints: 'Q Quit',
      );

      final widget = ExplorerFooter(model);
      final lines = widget.build(constraints).toList();

      expect(widget.height, 3);
      expect(lines[0].text, '3 observed entries');
      expect(lines[1].role, TerminalRole.warning);
      expect(lines[2].text, 'Q Quit');
    });

    test('rejects empty display lines', () {
      expect(
        () => ExplorerFooterViewModel(
          summary: '',
          inspection_status: 'Ready',
          is_warning: false,
          navigation_hints: 'Q Quit',
        ),
        throwsArgumentError,
      );
    });
  });

  group('ExplorerViewModel', () {
    test('contains only independently composed component models', () {
      final header = ExplorerHeaderViewModel(
        current_directory: '/workspace',
      );

      final directory = _empty_directory();

      final footer = ExplorerFooterViewModel(
        summary: '0 observed entries',
        inspection_status: 'Read-only exploration.',
        is_warning: false,
        navigation_hints: 'Q Quit',
      );

      final screen_model = ExplorerViewModel(
        header: header,
        directory: directory,
        footer: footer,
      );

      expect(screen_model.header, same(header));
      expect(screen_model.directory, same(directory));
      expect(screen_model.footer, same(footer));
    });
  });
}

/// Creates an independent empty-directory presentation.
///
/// The viewport allocates three entry rows.
ExplorerDirectoryViewModel _empty_directory() {
  return ExplorerDirectoryViewModel(
    total_entries: 0,
    visible_row_limit: 3,
    first_visible_index: 0,
    selected_index: null,
    selected_visible_index: null,
    visible_rows: [],
    is_complete: true,
  );
}
