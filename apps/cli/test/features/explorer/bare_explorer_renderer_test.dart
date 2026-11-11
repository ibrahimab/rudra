import 'package:rudra_cli/src/core/rendering/bare/ansi_text.dart';
import 'package:rudra_cli/src/core/rendering/terminal_text.dart';
import 'package:rudra_cli/src/core/rendering/theme.dart';

import 'package:rudra_cli/src/features/explorer/bare_explorer_renderer.dart';
import 'package:rudra_cli/src/features/explorer/explorer_model.dart';
import 'package:rudra_cli/src/features/explorer/explorer_presenter.dart';
import 'package:rudra_cli/src/features/explorer/explorer_view_model.dart';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies the bare Explorer rendering backend.
///
/// All filesystem observations and output destinations are
/// supplied through deterministic in-memory fixtures.
///
/// No actual terminal state is modified.
/// No native filesystem operations or cleanup are performed.
void main() {
  group('BareExplorerRenderer', () {
    test('renders directory context and observed entries', () {
      final view_model = _view_model(
        [
          _entry(
            '/fixture/readme.md',
            FilesystemEntryKind.regularFile,
            logical_bytes: 2048,
          ),
          _entry(
            '/fixture/docs',
            FilesystemEntryKind.directory,
          ),
        ],
        visible_row_limit: 3,
      );

      final output = _render(view_model, columns: 80);

      expect(output, contains('RUDRA / EXPLORER'));
      expect(output, contains('READ ONLY'));
      expect(output, contains('Directory: /fixture'));
      expect(output, contains('NAME'));
      expect(output, contains('TYPE'));
      expect(output, contains('SIZE'));
      expect(output, contains('docs/'));
      expect(output, contains('Directory'));
      expect(output, contains('readme.md'));
      expect(output, contains('2.0 KiB'));
      expect(output, contains('2 observed entries'));
      expect(output, contains('No filesystem changes.'));

      // The initially selected directory is identifiable
      // without requiring ANSI colors.
      expect(
        output.split('\n').any(
              (line) => line.startsWith('> docs/'),
            ),
        isTrue,
      );

      expect(output, isNot(contains('\x1B')));
    });

    test('highlights the selected row using ANSI styles', () {
      final view_model = _view_model(
        [
          _entry(
            '/fixture/a.txt',
            FilesystemEntryKind.regularFile,
          ),
          _entry(
            '/fixture/b.txt',
            FilesystemEntryKind.regularFile,
          ),
        ],
        selected_index: 1,
      );

      final output = _render(
        view_model,
        columns: 60,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: true),
      );

      expect(output, contains('\x1B[1;7m'));
      expect(output, contains('> b.txt'));
      expect(output, contains('\x1B[0m'));
    });

    test('renders only the requested Explorer viewport', () {
      final entries = [
        for (final name in ['a', 'b', 'c', 'd', 'e'])
          _entry(
            '/fixture/$name.txt',
            FilesystemEntryKind.regularFile,
          ),
      ];

      final view_model = _view_model(
        entries,
        selected_index: 4,
        visible_row_limit: 2,
      );

      expect(view_model.first_visible_index, 3);

      final output = _render(
        view_model,
        columns: 70,
      );

      expect(output, contains('d.txt'));
      expect(output, contains('> e.txt'));
      expect(output, isNot(contains('a.txt')));
      expect(output, isNot(contains('b.txt')));
      expect(output, isNot(contains('c.txt')));
      expect(output, contains('more above'));
    });

    test('keeps frame height stable with unused entry rows', () {
      final view_model = _view_model(
        [
          _entry(
            '/fixture/only.txt',
            FilesystemEntryKind.regularFile,
          ),
        ],
        visible_row_limit: 5,
      );

      final output = _render(view_model, columns: 70);

      final lines = output.split('\n');

      // Six fixed lines, five entry slots, and the final
      // trailing newline represented by an empty split item.
      expect(lines.length, 12);
      expect(lines[3], contains('only.txt'));

      expect(lines[4], isEmpty);
      expect(lines[5], isEmpty);
      expect(lines[6], isEmpty);
      expect(lines[7], isEmpty);
    });

    test('distinguishes empty and incomplete observations', () {
      final empty = _render(
        _view_model([], visible_row_limit: 2),
        columns: 90,
      );

      expect(empty, contains('(empty directory)'));
      expect(empty, isNot(contains('WARNING')));

      final incomplete = _render(
        _view_model(
          [],
          visible_row_limit: 2,
          is_complete: false,
        ),
        columns: 90,
      );

      expect(
        incomplete,
        contains('(no entries observed; inspection incomplete)'),
      );

      expect(incomplete, contains('WARNING'));
      expect(incomplete, isNot(contains('(empty directory)')));
    });

    test('preserves typed inspection diagnostics', () {
      final issue = InspectionIssue(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/fixture/blocked'),
        message: 'Permission denied.',
      );

      final view_model = _view_model(
        [
          _entry(
            '/fixture/visible.txt',
            FilesystemEntryKind.regularFile,
          ),
        ],
        is_complete: false,
        issues: [issue],
      );

      final output = _render(
        view_model,
        columns: 180,
      );

      expect(output, contains('WARNING'));
      expect(output, contains('permissionDenied'));
      expect(output, contains('inspect'));
      expect(output, contains('/fixture/blocked'));
      expect(output, contains('Permission denied.'));
      expect(output, contains('visible.txt'));
    });

    test('sanitizes malicious filesystem and diagnostic text', () {
      final issue = InspectionIssue(
        code: TargetInspectionErrorCode.ioFailure,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/fixture/blocked\x1B[H'),
        message: 'evil\x1B[2J',
      );

      final view_model = _view_model(
        [
          _entry(
            '/fixture/unsafe\x1B[2J',
            FilesystemEntryKind.regularFile,
          ),
        ],
        is_complete: false,
        issues: [issue],
      );

      final output = _render(
        view_model,
        columns: 180,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: true),
      );

      expect(output, contains('unsafe?[2J'));
      expect(output, contains('blocked?[H'));
      expect(output, contains('evil?[2J'));

      // No untrusted clear-screen or cursor-home sequences
      // may survive the terminal text sanitizer.
      expect(output, isNot(contains('\x1B[2J')));
      expect(output, isNot(contains('\x1B[H')));
    });

    test('emits controlled redraw sequences only when enabled', () {
      final view_model = _view_model([]);

      final output = _render(
        view_model,
        columns: 60,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: true),
        redraw_screen: true,
      );

      expect(output, startsWith('\x1B[H\x1B[2J'));

      expect(
        '\x1B[2J'.allMatches(output).length,
        1,
      );
    });

    test('rejects redrawing without ANSI support', () {
      expect(
        () => BareExplorerRenderer(
          output: StringBuffer(),
          terminal_columns: () => 80,
          redraw_screen: true,
        ),
        throwsArgumentError,
      );
    });

    test('truncates output to narrow terminal widths', () {
      final view_model = _view_model(
        [
          _entry(
            '/fixture/very-long-directory-name',
            FilesystemEntryKind.directory,
          ),
        ],
      );

      final output = _render(
        view_model,
        columns: 18,
      );

      for (final line in output.split('\n')) {
        expect(
          TerminalText.estimated_columns(line),
          lessThanOrEqualTo(18),
        );
      }

      expect(output, contains('> '));
      expect(output, isNot(contains('\x1B')));
    });

    test('reads current terminal width on every render', () {
      var columns = 18;
      final output = StringBuffer();

      final renderer = BareExplorerRenderer(
        output: output,
        terminal_columns: () => columns,
      );

      final view_model = _view_model([]);

      renderer.render(view_model);

      final first_frame = output.toString();

      expect(first_frame, isNot(contains('Directory: /fixture')));

      output.clear();
      columns = 80;

      renderer.render(view_model);

      final second_frame = output.toString();

      expect(second_frame, contains('Directory: /fixture'));
    });

    test('rejects negative terminal width', () {
      final renderer = BareExplorerRenderer(
        output: StringBuffer(),
        terminal_columns: () => -1,
      );

      expect(
        () => renderer.render(_view_model([])),
        throwsRangeError,
      );
    });

    test('propagates output sink failures', () {
      final renderer = BareExplorerRenderer(
        output: _FailingSink(),
        terminal_columns: () => 80,
      );

      expect(
        () => renderer.render(_view_model([])),
        throwsStateError,
      );
    });

    test('renders a closed Explorer without active key hints', () {
      final view_model = _view_model(
        [],
        is_closed: true,
      );

      final output = _render(
        view_model,
        columns: 80,
      );

      expect(output, contains('Explorer closed.'));
      expect(output, isNot(contains('Q Quit')));
    });
  });
}

/// Creates a deterministic Explorer presentation snapshot.
///
/// All filesystem observations are supplied in memory.
ExplorerViewModel _view_model(
  List<FilesystemEntry> entries, {
  int selected_index = 0,
  int visible_row_limit = 5,
  bool is_complete = true,
  bool is_closed = false,
  List<InspectionIssue> issues = const [],
}) {
  final directory = TargetPath('/fixture');

  var model = ExplorerModel(
    root_directory: directory,
    listing: DirectoryListing(
      target_id: 'fixture-target',
      directory: directory,
      entries: entries,
      is_complete: is_complete,
      issues: issues,
    ),
  );

  if (entries.isNotEmpty) {
    model = model.with_selection(selected_index);
  }

  if (is_closed) {
    model = model.close();
  }

  return const ExplorerPresenter().present(
    model,
    visible_row_limit: visible_row_limit,
  );
}

/// Creates one filesystem entry without native inspection.
FilesystemEntry _entry(
  String path,
  FilesystemEntryKind kind, {
  int? logical_bytes,
}) {
  return FilesystemEntry(
    path: TargetPath(path),
    kind: kind,
    metadata: FilesystemMetadata(
      logical_size_bytes: logical_bytes,
    ),
  );
}

/// Renders a snapshot to a deterministic in-memory output sink.
///
/// Terminal styling and screen clearing are opt-in.
String _render(
  ExplorerViewModel view_model, {
  required int columns,
  TerminalTheme? theme,
  AnsiText ansi_text = const AnsiText(),
  bool redraw_screen = false,
}) {
  final output = StringBuffer();

  final renderer = BareExplorerRenderer(
    output: output,
    terminal_columns: () => columns,
    theme: theme,
    ansi_text: ansi_text,
    redraw_screen: redraw_screen,
  );

  renderer.render(view_model);

  return output.toString();
}

/// Output sink that deliberately fails during rendering.
///
/// Used to establish that rendering failures are not
/// converted into successful results.
final class _FailingSink implements StringSink {
  /// Fails every attempted string write.
  @override
  void write(Object? object) {
    throw StateError('Injected output failure.');
  }

  /// Fails every attempted line write.
  @override
  void writeln([Object? object = '']) {
    throw StateError('Injected output failure.');
  }

  /// Fails every attempted iterable write.
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    throw StateError('Injected output failure.');
  }

  /// Fails every attempted character write.
  @override
  void writeCharCode(int char_code) {
    throw StateError('Injected output failure.');
  }
}
