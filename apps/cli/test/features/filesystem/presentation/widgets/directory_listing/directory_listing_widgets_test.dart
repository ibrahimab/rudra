
import 'package:rudra_cli/src/core/rendering/bare/ansi_text.dart';
import 'package:rudra_cli/src/core/rendering/bare/bare_widget_renderer.dart';
import 'package:rudra_cli/src/core/rendering/theme.dart';
import 'package:rudra_cli/src/core/rendering/widgets/terminal_column.dart';
import 'package:rudra_cli/src/core/rendering/widgets/terminal_label.dart';
import 'package:rudra_cli/src/core/rendering/widgets/terminal_widget.dart';
import 'package:rudra_cli/src/core/rendering/terminal_text.dart';

import 'package:rudra_cli/src/features/filesystem/bare_filesystem_renderer.dart';
import 'package:rudra_cli/src/features/filesystem/presentation/widgets/directory_listing/directory_listing_view_model.dart';
import 'package:rudra_cli/src/features/filesystem/presentation/widgets/directory_inspection_issues/directory_inspection_issues_widget.dart';
import 'package:rudra_cli/src/features/filesystem/presentation/widgets/directory_listing/directory_listing_widget.dart';

import 'package:test/test.dart';

/// Verifies independently composable filesystem presentation.
///
/// These tests require no Rudra SDK service, native filesystem
/// adapter, terminal host, or application command.
///
/// They exercise layout contracts, unbounded output, diagnostics,
/// terminal sanitization, and use inside another widget tree.
void main() {
  group('DirectoryListingWidget', () {
    test('renders compact listing with exact declared height', () {
      final model = _listing(
        layout: DirectoryListingLayout.compact,
        rows: [_row()],
      );

      final widget = DirectoryListingWidget(model);

      final lines = widget.build(
        TerminalConstraints(),
      ).toList();

      expect(widget.height, 2);
      expect(lines, hasLength(widget.height));
      expect(lines.first.text, contains('LOGICAL_BYTES'));
      expect(lines.last.text, contains('/fixture/readme.txt'));
    });

    test('renders detailed metadata and summary', () {
      final model = _listing(
        layout: DirectoryListingLayout.detailed,
        rows: [_row()],
      );

      final widget = DirectoryListingWidget(model);

      final lines = widget.build(
        TerminalConstraints(),
      ).toList();

      expect(widget.height, 5);
      expect(lines, hasLength(widget.height));

      expect(lines[0].text, contains('PERMISSIONS'));
      expect(lines[0].role, TerminalRole.heading);
      expect(lines[1].text, contains('─'));
      expect(lines[2].text, contains('readme.txt'));
      expect(lines[2].text, contains('1.0 KiB'));
      expect(lines[2].text, contains('-rw-r--r--'));
      expect(lines[3].text, isEmpty);
      expect(lines[4].text, contains('1 observed entries'));
    });

    test('adds an explicit warning for incomplete listings', () {
      final model = _listing(
        layout: DirectoryListingLayout.detailed,
        is_complete: false,
        rows: [_row()],
      );

      final widget = DirectoryListingWidget(model);

      final lines = widget.build(
        TerminalConstraints(),
      ).toList();

      expect(widget.height, 6);
      expect(lines, hasLength(6));
      expect(lines.last.role, TerminalRole.warning);
      expect(lines.last.text, contains('incomplete'));
    });

    test('does not truncate long paths in command output', () {
      final filename = '${List<String>.filled(240, 'x').join()}.txt';
      final path = '/fixture/$filename';

      final model = _listing(
        layout: DirectoryListingLayout.compact,
        rows: [_row(
          path: path,
          name: filename,
        )],
      );

      final output = StringBuffer();

      BareFilesystemRenderer(
        output: output,
      ).render(model);

      expect(output.toString(), contains(path));
      expect(output.toString(), isNot(contains('…')));
    });

    test('sanitizes malicious names in unbounded output', () {
      final model = _listing(
        layout: DirectoryListingLayout.detailed,
        rows: [
          _row(name: 'unsafe\x1B[2Jname.txt'),
        ],
      );

      final output = StringBuffer();

      BareWidgetRenderer(
        output: output,
      ).render(
        DirectoryListingWidget(model),
      );

      expect(output.toString(), contains('unsafe?[2Jname.txt'));
      expect(output.toString(), isNot(contains('\x1B[2J')));
    });

    test('supports bounded output when explicitly requested', () {
      final model = _listing(
        layout: DirectoryListingLayout.compact,
        rows: [_row()],
      );

      final output = StringBuffer();

      BareWidgetRenderer(
        output: output,
        terminal_columns: () => 12,
      ).render(
        DirectoryListingWidget(model),
      );

      for (final line in output.toString().split('\n')) {
        expect(
          TerminalText.estimated_columns(line),
          lessThanOrEqualTo(12),
        );
      }
    });

    test('participates in another feature widget composition', () {
      final model = _listing(
        layout: DirectoryListingLayout.detailed,
        rows: [_row()],
      );

      final screen = TerminalColumn(
        children: [
          const TerminalLabel(
            'WELCOME',
            role: TerminalRole.title,
          ),
          DirectoryListingWidget(model),
          const TerminalLabel('Available commands:'),
        ],
      );

      final lines = screen.build(
        TerminalConstraints(),
      ).toList();

      expect(screen.height, 7);
      expect(lines, hasLength(screen.height));
      expect(lines.first.text, 'WELCOME');
      expect(lines.any((line) => line.text.contains('readme.txt')), isTrue);
      expect(lines.last.text, 'Available commands:');
    });

    test('preserves semantic styling for detailed entries', () {
      final model = _listing(
        layout: DirectoryListingLayout.detailed,
        rows: [
          _row(
            name: 'docs/',
            role: TerminalRole.directory,
          ),
        ],
      );

      final output = StringBuffer();

      BareWidgetRenderer(
        output: output,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: true),
      ).render(
        DirectoryListingWidget(model),
      );

      expect(output.toString(), contains('\x1B[1;36m'));
      expect(output.toString(), contains('\x1B[1;34m'));
    });
  });

  group('DirectoryInspectionIssuesWidget', () {
    test('occupies no rows without diagnostic issues', () {
      final widget = DirectoryInspectionIssuesWidget(
        _listing(layout: DirectoryListingLayout.compact),
      );

      expect(widget.height, 0);
      expect(widget.build(TerminalConstraints()), isEmpty);
    });

    test('preserves typed diagnostic information', () {
      final widget = DirectoryInspectionIssuesWidget(
        _listing(
          layout: DirectoryListingLayout.compact,
          is_complete: false,
          issues: [_issue()],
        ),
      );

      final lines = widget.build(
        TerminalConstraints(),
      ).toList();

      expect(widget.height, 1);
      expect(lines.single.role, TerminalRole.error);
      expect(lines.single.text, contains('inspect'));
      expect(lines.single.text, contains('permissionDenied'));
      expect(lines.single.text, contains('/fixture/blocked'));
    });

    test('reports incomplete inspection without typed issues', () {
      final widget = DirectoryInspectionIssuesWidget(
        _listing(
          layout: DirectoryListingLayout.compact,
          is_complete: false,
        ),
      );

      final lines = widget.build(
        TerminalConstraints(),
      ).toList();

      expect(widget.height, 1);
      expect(
        lines.single.text,
        'Filesystem inspection did not complete.',
      );
    });

    test('renders diagnostics to an independent output sink', () {
      final output = StringBuffer();
      final errors = StringBuffer();

      BareFilesystemRenderer(
        output: output,
        error_output: errors,
      ).render(
        _listing(
          layout: DirectoryListingLayout.compact,
          is_complete: false,
          rows: [_row()],
          issues: [_issue()],
        ),
      );

      expect(output.toString(), contains('readme.txt'));
      expect(output.toString(), isNot(contains('permissionDenied')));

      expect(errors.toString(), contains('permissionDenied'));
      expect(errors.toString(), contains('/fixture/blocked'));
    });

    test('sanitizes diagnostic control sequences', () {
      final errors = StringBuffer();

      BareWidgetRenderer(
        output: errors,
      ).render(
        DirectoryInspectionIssuesWidget(
          _listing(
            layout: DirectoryListingLayout.compact,
            is_complete: false,
            issues: [
              _issue(message: 'unsafe\x1B[2Jmessage'),
            ],
          ),
        ),
      );

      expect(errors.toString(), contains('unsafe?[2Jmessage'));
      expect(errors.toString(), isNot(contains('\x1B[2J')));
    });
  });
}

/// Creates an immutable filesystem listing presentation.
///
/// All data is supplied without invoking the SDK.
DirectoryListingViewModel _listing({
  required DirectoryListingLayout layout,
  List<DirectoryEntryViewModel> rows = const [],
  List<DirectoryInspectionIssueViewModel> issues = const [],
  bool is_complete = true,
}) {
  return DirectoryListingViewModel(
    layout: layout,
    directory_path: '/fixture',
    target_id: 'fixture-target',
    is_complete: is_complete,
    rows: rows,
    issues: issues,
  );
}

/// Creates a prepared entry containing display-only metadata.
///
/// Names and paths may be overridden for security and width tests.
DirectoryEntryViewModel _row({
  String path = '/fixture/readme.txt',
  String name = 'readme.txt',
  TerminalRole role = TerminalRole.regular_file,
}) {
  return DirectoryEntryViewModel(
    path: path,
    name: name,
    compact_type: 'regularFile',
    type_label: 'File',
    logical_bytes: '1024',
    size_label: '1.0 KiB',
    permissions: '-rw-r--r--',
    modified_utc: '2026-11-10 12:30',
    role: role,
  );
}

/// Creates a typed diagnostic presentation fixture.
DirectoryInspectionIssueViewModel _issue({
  String message = 'Permission denied.',
}) {
  return DirectoryInspectionIssueViewModel(
    operation: 'inspect',
    code: 'permissionDenied',
    path: '/fixture/blocked',
    message: message,
  );
}
