import 'package:rudra_cli/src/core/rendering/bare/ansi_text.dart';
import 'package:rudra_cli/src/core/rendering/renderer.dart';
import 'package:rudra_cli/src/core/rendering/theme.dart';
import 'package:rudra_cli/src/core/rendering/bare/bare_widget_renderer.dart';

import 'package:rudra_cli/src/features/filesystem/presentation/filesystem_view_model.dart';
import 'package:rudra_cli/src/features/filesystem/presentation/widgets/directory_inspection_issues/directory_inspection_issues_view_model.dart';
import 'package:rudra_cli/src/features/filesystem/presentation/widgets/directory_listing/directory_listing_view_model.dart';

import 'package:rudra_cli/src/features/welcome/presentation/bare_welcome_renderer.dart';
import 'package:rudra_cli/src/features/welcome/presentation/welcome_view_model.dart';
import 'package:rudra_cli/src/features/welcome/presentation/widgets/commands/welcome_commands_view_model.dart';
import 'package:rudra_cli/src/features/welcome/presentation/widgets/footer/welcome_footer_view_model.dart';
import 'package:rudra_cli/src/features/welcome/presentation/widgets/header/welcome_header_view_model.dart';
import 'package:rudra_cli/src/features/welcome/presentation/widgets/target/welcome_target_view_model.dart';
import 'package:rudra_cli/src/features/welcome/presentation/widgets/welcome_screen.dart';

import 'package:test/test.dart';

/// Verifies the bare welcome-screen rendering backend.
///
/// Tests consume immutable presentation models directly.
///
/// The renderer delegates Welcome screen composition to
/// [WelcomeScreen] and terminal encoding to [BareWidgetRenderer].
///
/// Filesystem listings and diagnostics use independent widgets.
///
/// No filesystem adapter, SDK service, or terminal session
/// is required.
void main() {
  group('BareWelcomeRenderer composition', () {
    test('preserves unsupported-target output exactly', () {
      final output = StringBuffer();

      BareWelcomeRenderer(output: output).render(
        _welcome(
          target_id: null,
          starting_directory: null,
        ),
      );

      expect(
        output.toString(),
        '\n'
        'RUDRA  |  READ ONLY\n'
        'Read-only filesystem exploration.\n'
        '\n'
        'Filesystem inspection is not available '
        'for the current target.\n'
        '\n'
        'Available commands:\n'
        '  rudra about               '
        'Show application information\n'
        '  rudra --help              '
        'Show available commands\n'
        '\n'
        'Inspection never authorizes '
        'file modification or deletion.\n',
      );
    });

    test('preserves configured-target output exactly', () {
      final output = StringBuffer();

      BareWelcomeRenderer(output: output).render(
        _welcome(),
      );

      expect(
        output.toString(),
        '\n'
        'RUDRA  |  READ ONLY\n'
        'Read-only filesystem exploration.\n'
        '\n'
        'Target: fixture-target\n'
        'Starting directory: /fixture\n'
        '\n'
        'Available commands:\n'
        '  rudra ls                  '
        'Inspect the starting directory\n'
        '  rudra ls /absolute/path   '
        'Inspect another directory\n'
        '  rudra about               '
        'Show application information\n'
        '  rudra --help              '
        'Show available commands\n'
        '\n'
        'Inspection never authorizes '
        'file modification or deletion.\n',
      );
    });

    test('delegates detailed directory rendering', () {
      final output = StringBuffer();

      BareWelcomeRenderer(output: output).render(
        _welcome(
          listing: _directory_listing(
            rows: [_file_row()],
          ),
        ),
      );

      final result = output.toString();

      expect(result, contains('NAME'));
      expect(result, contains('PERMISSIONS'));
      expect(result, contains('MODIFIED (UTC)'));
      expect(result, contains('readme.txt'));
      expect(result, contains('1.0 KiB'));
      expect(result, contains('-rw-r--r--'));
      expect(
        result,
        contains('1 observed entries · immediate children only'),
      );

      // The nested filesystem table is rendered exactly once.
      expect(
        '1 observed entries'.allMatches(result),
        hasLength(1),
      );
    });

    test('renders empty directory observations', () {
      final output = StringBuffer();

      BareWelcomeRenderer(output: output).render(
        _welcome(
          listing: _directory_listing(),
        ),
      );

      expect(
        output.toString(),
        contains('0 observed entries · immediate children only'),
      );
      expect(output.toString(), isNot(contains('WARNING')));
    });

    test('retains the read-only safety statement', () {
      final output = StringBuffer();

      BareWelcomeRenderer(output: output).render(
        _welcome(),
      );

      expect(
        output.toString(),
        endsWith(
          'Inspection never authorizes '
          'file modification or deletion.\n',
        ),
      );
    });

    test('works through the generic Renderer contract', () {
      final output = StringBuffer();

      final Renderer<WelcomeViewModel> renderer =
          BareWelcomeRenderer(output: output);

      renderer.render(_welcome());

      expect(output.toString(), contains('RUDRA'));
      expect(output.toString(), contains('Target: fixture-target'));
    });

    test('renders deterministically without shared state', () {
      final model = _welcome(
        listing: _directory_listing(
          rows: [_file_row()],
        ),
      );

      final first = StringBuffer();
      final second = StringBuffer();

      BareWelcomeRenderer(output: first).render(model);
      BareWelcomeRenderer(output: second).render(model);

      expect(first.toString(), second.toString());
    });
  });

  group('BareWelcomeRenderer inspection diagnostics', () {
    test('preserves typed issues in the diagnostic sink', () {
      final output = StringBuffer();
      final errors = StringBuffer();

      BareWelcomeRenderer(
        output: output,
        error_output: errors,
      ).render(
        _welcome(
          listing: _directory_listing(
            is_complete: false,
            rows: [_file_row()],
            issues: [_issue()],
          ),
        ),
      );

      expect(output.toString(), contains('readme.txt'));

      expect(
        output.toString(),
        contains('WARNING: This directory listing is incomplete.'),
      );

      expect(
        errors.toString(),
        'inspect: permissionDenied: '
        '/fixture/blocked: Permission denied.\n',
      );
    });

    test('reports incomplete inspections without typed issues', () {
      final output = StringBuffer();
      final errors = StringBuffer();

      BareWelcomeRenderer(
        output: output,
        error_output: errors,
      ).render(
        _welcome(
          listing: _directory_listing(
            is_complete: false,
          ),
        ),
      );

      expect(output.toString(), contains('WARNING'));

      expect(
        errors.toString(),
        'Filesystem inspection did not complete.\n',
      );
    });

    test('does not fabricate errors for complete observations', () {
      final errors = StringBuffer();

      BareWelcomeRenderer(
        output: StringBuffer(),
        error_output: errors,
      ).render(
        _welcome(
          listing: _directory_listing(
            rows: [_file_row()],
          ),
        ),
      );

      expect(errors.toString(), isEmpty);
    });

    test('does not require an error output sink', () {
      final output = StringBuffer();

      BareWelcomeRenderer(output: output).render(
        _welcome(
          listing: _directory_listing(
            is_complete: false,
            issues: [_issue()],
          ),
        ),
      );

      expect(output.toString(), contains('WARNING'));
      expect(output.toString(), isNot(contains('permissionDenied')));
    });
  });

  group('BareWelcomeRenderer styling and safety', () {
    test('applies semantic styling when ANSI is enabled', () {
      final output = StringBuffer();

      BareWelcomeRenderer(
        output: output,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: true),
      ).render(
        _welcome(
          listing: _directory_listing(
            rows: [_directory_row()],
          ),
        ),
      );

      final result = output.toString();

      // Title and section headings use bold cyan.
      expect(result, contains('\x1B[1;36m'));

      // Directory entries use bold blue.
      expect(result, contains('\x1B[1;34m'));

      // Every styled segment is reset.
      expect(result, contains('\x1B[0m'));
    });

    test('keeps the plain theme free from ANSI sequences', () {
      final output = StringBuffer();

      BareWelcomeRenderer(
        output: output,
        theme: TerminalTheme.plain,
        ansi_text: const AnsiText(enabled: true),
      ).render(_welcome());

      expect(output.toString(), isNot(contains('\x1B')));
    });

    test('honors a disabled ANSI encoder', () {
      final output = StringBuffer();

      BareWelcomeRenderer(
        output: output,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: false),
      ).render(
        _welcome(
          listing: _directory_listing(
            rows: [_directory_row()],
          ),
        ),
      );

      expect(output.toString(), isNot(contains('\x1B')));
    });

    test('styles incomplete inspection warnings and errors', () {
      final output = StringBuffer();
      final errors = StringBuffer();

      BareWelcomeRenderer(
        output: output,
        error_output: errors,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: true),
      ).render(
        _welcome(
          listing: _directory_listing(
            is_complete: false,
            issues: [_issue()],
          ),
        ),
      );

      expect(output.toString(), contains('\x1B[1;33m'));
      expect(errors.toString(), contains('\x1B[1;31m'));
    });

    test('sanitizes untrusted target and path labels', () {
      final output = StringBuffer();

      BareWelcomeRenderer(output: output).render(
        _welcome(
          target_id: 'fixture\x1B[2Jtarget',
          starting_directory: '/fixture\nunsafe',
        ),
      );

      final result = output.toString();

      expect(result, contains('Target: fixture?[2Jtarget'));
      expect(
        result,
        contains('Starting directory: /fixture?unsafe'),
      );

      expect(result, isNot(contains('\x1B')));
    });

    test('sanitizes nested filesystem filenames', () {
      final output = StringBuffer();

      BareWelcomeRenderer(output: output).render(
        _welcome(
          listing: _directory_listing(
            rows: [
              _file_row(name: 'bad\x1B[2Jfile.txt'),
            ],
          ),
        ),
      );

      expect(output.toString(), contains('bad?[2Jfile.txt'));
      expect(output.toString(), isNot(contains('\x1B')));
    });
  });
}

/// Creates a composed Welcome presentation without SDK operations.
///
/// All visual components receive their independent view models.
///
/// Target availability determines filesystem command visibility.
WelcomeViewModel _welcome({
  FilesystemViewModel? listing,
  String? target_id = 'fixture-target',
  String? starting_directory = '/fixture',
}) {
  final target = WelcomeTargetViewModel(
    target_id: target_id,
    starting_directory: starting_directory,
  );

  return WelcomeViewModel(
    header: WelcomeHeaderViewModel(
      product_title: 'RUDRA',
    ),
    target: target,
    commands: WelcomeCommandsViewModel(
      show_filesystem_commands: target.can_inspect,
    ),
    footer: WelcomeFooterViewModel(
      safety_statement:
          'Inspection never authorizes file modification or deletion.',
    ),
    filesystem: listing,
  );
}

/// Creates a detailed filesystem presentation for Welcome.
///
/// Both component models are supplied without SDK operations.
FilesystemViewModel _directory_listing({
  bool is_complete = true,
  List<DirectoryEntryViewModel> rows = const [],
  List<DirectoryInspectionIssueViewModel> issues = const [],
}) {
  return FilesystemViewModel(
    listing: DirectoryListingViewModel(
      layout: DirectoryListingLayout.detailed,
      directory_path: '/fixture',
      target_id: 'fixture-target',
      is_complete: is_complete,
      rows: rows,
    ),
    inspection_issues: DirectoryInspectionIssuesViewModel(
      is_complete: is_complete,
      issues: issues,
    ),
  );
}

/// Creates a file row with known metadata.
///
/// The name can be overridden to verify safe rendering
/// of untrusted filesystem names.
DirectoryEntryViewModel _file_row({
  String name = 'readme.txt',
}) {
  return DirectoryEntryViewModel(
    path: '/fixture/readme.txt',
    name: name,
    compact_type: 'regularFile',
    type_label: 'File',
    logical_bytes: '1024',
    size_label: '1.0 KiB',
    permissions: '-rw-r--r--',
    modified_utc: '2026-11-10 12:30',
    role: TerminalRole.regular_file,
  );
}

/// Creates a directory row for semantic styling tests.
///
/// Directory sizes are unknown without recursive accounting.
DirectoryEntryViewModel _directory_row() {
  return DirectoryEntryViewModel(
    path: '/fixture/docs',
    name: 'docs/',
    compact_type: 'directory',
    type_label: 'Directory',
    logical_bytes: '?',
    size_label: '—',
    permissions: 'd?????????',
    modified_utc: '?',
    role: TerminalRole.directory,
  );
}

/// Creates one prepared, typed inspection diagnostic.
///
/// Diagnostic paths and messages remain presentation data,
/// not authoritative filesystem state.
DirectoryInspectionIssueViewModel _issue() {
  return const DirectoryInspectionIssueViewModel(
    operation: 'inspect',
    code: 'permissionDenied',
    path: '/fixture/blocked',
    message: 'Permission denied.',
  );
}
