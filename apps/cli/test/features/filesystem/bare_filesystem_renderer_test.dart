import 'package:rudra_cli/src/features/filesystem/directory_listing_view_model.dart';
import 'package:rudra_cli/src/core/rendering/bare/ansi_text.dart';
import 'package:rudra_cli/src/features/filesystem/bare_filesystem_renderer.dart';
import 'package:rudra_cli/src/core/rendering/theme.dart';
import 'package:test/test.dart';

/// Verifies Rudra's bare filesystem rendering backend.
///
/// The renderer receives prepared ViewModels rather than SDK
/// services or native filesystem adapters.
///
/// Tests verify output compatibility, semantic styling,
/// diagnostic handling, and untrusted-text sanitization.
///
/// No filesystem or real terminal operations are performed.
void main() {
  group('BareFilesystemRenderer compact layout', () {
    test('preserves the original ls output exactly', () {
      final output = StringBuffer();

      BareFilesystemRenderer(output: output).render(
        _model(layout: DirectoryListingLayout.compact),
      );

      expect(
        output.toString(),
        'TYPE         LOGICAL_BYTES  PATH\n'
        'regularFile           1024  /fixture/README.md\n'
        'directory                ?  /fixture/docs\n',
      );
    });

    test('never styles compact listing content', () {
      final output = StringBuffer();

      BareFilesystemRenderer(
        output: output,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: true),
      ).render(
        _model(layout: DirectoryListingLayout.compact),
      );

      expect(output.toString(), isNot(contains('\x1B')));
      expect(output.toString(), contains('LOGICAL_BYTES'));
    });

    test('renders an empty compact listing', () {
      final output = StringBuffer();

      BareFilesystemRenderer(output: output).render(
        _model(
          layout: DirectoryListingLayout.compact,
          rows: [],
        ),
      );

      expect(
        output.toString(),
        'TYPE  LOGICAL_BYTES  PATH\n',
      );
    });

    test('sanitizes unsafe paths in compact output', () {
      final output = StringBuffer();

      BareFilesystemRenderer(output: output).render(
        _model(
          layout: DirectoryListingLayout.compact,
          rows: [
            _row(
              path: '/fixture/\x1B[2Jbad.txt',
            ),
          ],
        ),
      );

      expect(
        output.toString(),
        contains('/fixture/?[2Jbad.txt'),
      );

      expect(output.toString(), isNot(contains('\x1B')));
    });
  });

  group('BareFilesystemRenderer detailed layout', () {
    test('preserves the established detailed output', () {
      final output = StringBuffer();

      BareFilesystemRenderer(output: output).render(
        _model(
          layout: DirectoryListingLayout.detailed,
          rows: _sample_rows().reversed.toList(),
        ),
      );

      expect(
        output.toString(),
        '  NAME       TYPE            SIZE  PERMISSIONS  MODIFIED (UTC)\n'
        '  ─────────  ─────────  ─────────  ───────────  ────────────────\n'
        '  docs/      Directory          —  d?????????   ?\n'
        '  README.md  File         1.0 KiB  -rw-r--r--   2026-11-10 12:30\n'
        '\n'
        '  2 observed entries · immediate children only\n',
      );
    });

    test('renders an empty detailed listing', () {
      final output = StringBuffer();

      BareFilesystemRenderer(output: output).render(
        _model(
          layout: DirectoryListingLayout.detailed,
          rows: [],
        ),
      );

      expect(output.toString(), contains('NAME'));
      expect(output.toString(), contains('PERMISSIONS'));
      expect(
        output.toString(),
        contains('0 observed entries · immediate children only'),
      );
    });

    test('warns when inspection is incomplete', () {
      final output = StringBuffer();

      BareFilesystemRenderer(output: output).render(
        _model(
          layout: DirectoryListingLayout.detailed,
          is_complete: false,
        ),
      );

      expect(
        output.toString(),
        contains('WARNING: This directory listing is incomplete.'),
      );

      // Incomplete observations remain displayed.
      expect(output.toString(), contains('README.md'));
    });

    test('does not display an incomplete warning for complete data', () {
      final output = StringBuffer();

      BareFilesystemRenderer(output: output).render(
        _model(layout: DirectoryListingLayout.detailed),
      );

      expect(output.toString(), isNot(contains('WARNING')));
    });

    test('uses approximate Unicode column widths', () {
      final output = StringBuffer();

      BareFilesystemRenderer(output: output).render(
        _model(
          layout: DirectoryListingLayout.detailed,
          rows: [
            _row(
              name: '文件/',
              type_label: 'Directory',
              role: TerminalRole.directory,
            ),
            _row(name: 'a'),
          ],
        ),
      );

      final lines = output.toString().split('\n');

      // 文件/ occupies approximately five columns.
      // The shorter name is padded to that same width.
      expect(lines[2], startsWith('  文件/  Directory'));
      expect(lines[3], startsWith('  a      File'));
    });

    test('sanitizes unsafe names before rendering', () {
      final output = StringBuffer();

      BareFilesystemRenderer(output: output).render(
        _model(
          layout: DirectoryListingLayout.detailed,
          rows: [
            _row(
              name: 'bad\x1B[2Jname',
            ),
          ],
        ),
      );

      expect(output.toString(), contains('bad?[2Jname'));
      expect(output.toString(), isNot(contains('\x1B')));
    });
  });

  group('BareFilesystemRenderer diagnostics', () {
    test('writes typed issues to the diagnostic sink', () {
      final output = StringBuffer();
      final errors = StringBuffer();

      BareFilesystemRenderer(
        output: output,
        error_output: errors,
      ).render(
        _model(
          layout: DirectoryListingLayout.compact,
          is_complete: false,
          issues: [_issue()],
        ),
      );

      expect(
        errors.toString(),
        'inspect: permissionDenied: '
        '/fixture/blocked: Permission denied.\n',
      );

      expect(output.toString(), contains('LOGICAL_BYTES'));
      expect(output.toString(), isNot(contains('permissionDenied')));
    });

    test('reports incomplete inspections without issues', () {
      final output = StringBuffer();
      final errors = StringBuffer();

      BareFilesystemRenderer(
        output: output,
        error_output: errors,
      ).render(
        _model(
          layout: DirectoryListingLayout.compact,
          is_complete: false,
          issues: [],
        ),
      );

      expect(
        errors.toString(),
        'Filesystem inspection did not complete.\n',
      );
    });

    test('does not fabricate diagnostics for complete listings', () {
      final errors = StringBuffer();

      BareFilesystemRenderer(
        output: StringBuffer(),
        error_output: errors,
      ).render(
        _model(layout: DirectoryListingLayout.compact),
      );

      expect(errors.toString(), isEmpty);
    });

    test('can render issues independently from listing content', () {
      final output = StringBuffer();
      final errors = StringBuffer();

      final renderer = BareFilesystemRenderer(
        output: output,
      );

      renderer.render_issues(
        _model(
          layout: DirectoryListingLayout.compact,
          is_complete: false,
          issues: [_issue()],
        ),
        output: errors,
      );

      expect(output.toString(), isEmpty);
      expect(errors.toString(), contains('permissionDenied'));
    });

    test('does not duplicate diagnostics without a sink', () {
      final output = StringBuffer();

      BareFilesystemRenderer(output: output).render(
        _model(
          layout: DirectoryListingLayout.detailed,
          is_complete: false,
          issues: [_issue()],
        ),
      );

      expect(output.toString(), contains('WARNING'));
      expect(output.toString(), isNot(contains('permissionDenied')));
    });

    test('sanitizes untrusted diagnostic messages', () {
      final errors = StringBuffer();

      BareFilesystemRenderer(
        output: StringBuffer(),
        error_output: errors,
      ).render(
        _model(
          layout: DirectoryListingLayout.compact,
          is_complete: false,
          issues: [
            _issue(message: 'Failure\x1B[2Jdetected'),
          ],
        ),
      );

      expect(errors.toString(), contains('Failure?[2Jdetected'));
      expect(errors.toString(), isNot(contains('\x1B')));
    });
  });

  group('BareFilesystemRenderer styling', () {
    test('uses semantic ANSI styling for detailed output', () {
      final output = StringBuffer();

      BareFilesystemRenderer(
        output: output,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: true),
      ).render(
        _model(
          layout: DirectoryListingLayout.detailed,
          rows: _sample_rows().reversed.toList(),
        ),
      );

      expect(output.toString(), contains('\x1B[1;36m'));
      expect(output.toString(), contains('\x1B[1;34m'));
      expect(output.toString(), contains('\x1B[0m'));
    });

    test('uses the plain theme without ANSI sequences', () {
      final output = StringBuffer();

      BareFilesystemRenderer(
        output: output,
        theme: TerminalTheme.plain,
        ansi_text: const AnsiText(enabled: true),
      ).render(
        _model(layout: DirectoryListingLayout.detailed),
      );

      expect(output.toString(), isNot(contains('\x1B')));
    });

    test('respects a disabled ANSI encoder', () {
      final output = StringBuffer();

      BareFilesystemRenderer(
        output: output,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: false),
      ).render(
        _model(layout: DirectoryListingLayout.detailed),
      );

      expect(output.toString(), isNot(contains('\x1B')));
    });

    test('styles warnings and errors using semantic roles', () {
      final output = StringBuffer();
      final errors = StringBuffer();

      BareFilesystemRenderer(
        output: output,
        error_output: errors,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: true),
      ).render(
        _model(
          layout: DirectoryListingLayout.detailed,
          is_complete: false,
          issues: [_issue()],
        ),
      );

      expect(output.toString(), contains('\x1B[1;33m'));
      expect(errors.toString(), contains('\x1B[1;31m'));
    });
  });
}

/// Creates one deterministic filesystem presentation row.
///
/// Defaults to a regular file with observed size, permissions,
/// and modification timestamp.
DirectoryEntryViewModel _row({
  String path = '/fixture/README.md',
  String name = 'README.md',
  String compact_type = 'regularFile',
  String type_label = 'File',
  String logical_bytes = '1024',
  String size_label = '1.0 KiB',
  String permissions = '-rw-r--r--',
  String modified_utc = '2026-11-10 12:30',
  TerminalRole role = TerminalRole.regular_file,
}) {
  return DirectoryEntryViewModel(
    path: path,
    name: name,
    compact_type: compact_type,
    type_label: type_label,
    logical_bytes: logical_bytes,
    size_label: size_label,
    permissions: permissions,
    modified_utc: modified_utc,
    role: role,
  );
}

/// Returns file and directory observations in a fixed order.
///
/// Compact renderers preserve this order.
/// Detailed renderers receive pre-sorted ViewModel rows.
List<DirectoryEntryViewModel> _sample_rows() {
  return [
    _row(),
    _row(
      path: '/fixture/docs',
      name: 'docs/',
      compact_type: 'directory',
      type_label: 'Directory',
      logical_bytes: '?',
      size_label: '—',
      permissions: 'd?????????',
      modified_utc: '?',
      role: TerminalRole.directory,
    ),
  ];
}

/// Creates an immutable directory listing presentation.
///
/// No SDK invocation or filesystem inspection is performed.
DirectoryListingViewModel _model({
  required DirectoryListingLayout layout,
  List<DirectoryEntryViewModel>? rows,
  List<DirectoryInspectionIssueViewModel>? issues,
  bool is_complete = true,
}) {
  return DirectoryListingViewModel(
    layout: layout,
    directory_path: '/fixture',
    target_id: 'fixture-target',
    is_complete: is_complete,
    rows: rows ?? _sample_rows(),
    issues: issues ?? const [],
  );
}

/// Creates one typed inspection diagnostic presentation.
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
