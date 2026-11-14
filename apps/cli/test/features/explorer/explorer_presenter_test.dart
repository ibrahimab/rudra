import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';
import 'package:rudra_cli/src/features/explorer/presentation/explorer_presenter.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies Explorer presentation and viewport behavior.
///
/// All filesystem observations are constructed in memory.
///
/// No native filesystem access, terminal configuration,
/// persistent sessions, or cleanup operations are performed.
void main() {
  group('ExplorerPresenter', () {
    const presenter = ExplorerPresenter();

    test('preserves Explorer ordering and selection', () {
      final model = _model([
        _entry(
          '/fixture/zeta.txt',
          FilesystemEntryKind.regularFile,
          logical_bytes: 2048,
        ),
        _entry('/fixture/apps', FilesystemEntryKind.directory),
        _entry('/fixture/alpha.txt', FilesystemEntryKind.regularFile),
        _entry('/fixture/link', FilesystemEntryKind.symbolicLink),
      ]);

      final view_model = presenter.present(model, visible_row_limit: 10);

      expect(
        view_model.directory.visible_rows.map((row) => row.name),
        orderedEquals(['apps/', 'alpha.txt', 'link', 'zeta.txt']),
      );

      expect(view_model.directory.selected_index, 0);
      expect(view_model.directory.selected_visible_index, 0);
      expect(view_model.directory.visible_rows.first.type_label, 'Directory');

      expect(view_model.directory.visible_rows.last.size_label, '2.0 KiB');

      expect(view_model.directory.total_entries, 4);
      expect(view_model.directory.has_hidden_above, isFalse);
      expect(view_model.directory.has_hidden_below, isFalse);
      expect(view_model.directory.is_complete, isTrue);
    });

    test('scrolls forward to retain the selected row', () {
      final model = _model(_six_entries()).with_selection(5);

      final view_model = presenter.present(model, visible_row_limit: 2);

      expect(view_model.directory.first_visible_index, 4);
      expect(view_model.directory.selected_index, 5);
      expect(view_model.directory.selected_visible_index, 1);

      expect(
        view_model.directory.visible_rows.map((row) => row.name),
        orderedEquals(['e.txt', 'f.txt']),
      );

      expect(view_model.directory.has_hidden_above, isTrue);
      expect(view_model.directory.has_hidden_below, isFalse);
    });

    test('retains the viewport when selection remains visible', () {
      final model = _model(_six_entries()).with_selection(4);

      final view_model = presenter.present(
        model,
        visible_row_limit: 2,
        first_visible_index: 4,
      );

      expect(view_model.directory.first_visible_index, 4);
      expect(view_model.directory.selected_visible_index, 0);

      expect(
        view_model.directory.visible_rows.map((row) => row.name),
        orderedEquals(['e.txt', 'f.txt']),
      );
    });

    test('scrolls backward to retain the selected row', () {
      final model = _model(_six_entries()).with_selection(1);

      final view_model = presenter.present(
        model,
        visible_row_limit: 2,
        first_visible_index: 4,
      );

      expect(view_model.directory.first_visible_index, 1);
      expect(view_model.directory.selected_visible_index, 0);

      expect(
        view_model.directory.visible_rows.map((row) => row.name),
        orderedEquals(['b.txt', 'c.txt']),
      );

      expect(view_model.directory.has_hidden_above, isTrue);
      expect(view_model.directory.has_hidden_below, isTrue);
    });

    test('clamps an out-of-range viewport start', () {
      final model = _model(_six_entries()).with_selection(5);

      final view_model = presenter.present(
        model,
        visible_row_limit: 2,
        first_visible_index: 1000,
      );

      expect(view_model.directory.first_visible_index, 4);
      expect(view_model.directory.selected_visible_index, 1);
    });

    test('supports a zero-height entry viewport', () {
      final model = _model(_six_entries());

      final view_model = presenter.present(model, visible_row_limit: 0);

      expect(view_model.directory.visible_rows, isEmpty);
      expect(view_model.directory.selected_index, 0);
      expect(view_model.directory.selected_visible_index, isNull);
      expect(view_model.directory.observed_count, 6);
      expect(view_model.directory.has_hidden_below, isTrue);
    });

    test('rejects a negative viewport height', () {
      final model = _model([]);

      expect(
        () => presenter.present(model, visible_row_limit: -1),
        throwsRangeError,
      );
    });

    test('distinguishes empty and incomplete directories', () {
      final empty = presenter.present(_model([]), visible_row_limit: 10);

      expect(empty.directory.is_empty, isTrue);
      expect(empty.directory.selected_index, isNull);
      expect(empty.directory.visible_rows, isEmpty);

      final issue = InspectionIssue(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.listDirectory,
        path: TargetPath('/fixture'),
        message: 'Permission denied.',
      );

      final incomplete = presenter.present(
        _model([], is_complete: false, issues: [issue]),
        visible_row_limit: 10,
      );

      expect(incomplete.directory.is_empty, isFalse);
      expect(incomplete.directory.is_incomplete, isTrue);
      expect(incomplete.directory.observed_count, 0);

      expect(incomplete.footer.is_warning, isTrue);
      expect(
        incomplete.footer.inspection_status,
        contains('1 inspection issue(s)'),
      );
      expect(incomplete.footer.inspection_status, contains('permissionDenied'));
      expect(incomplete.footer.inspection_status, contains('listDirectory'));
    });

    test('retains partial observations and diagnostics', () {
      final issue = InspectionIssue(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/fixture/private'),
        message: 'Cannot inspect entry.',
      );

      final model = _model(
        [_entry('/fixture/visible.txt', FilesystemEntryKind.regularFile)],
        is_complete: false,
        issues: [issue],
      );

      final view_model = presenter.present(model, visible_row_limit: 5);

      expect(view_model.directory.visible_rows.single.name, 'visible.txt');
      expect(view_model.directory.is_complete, isFalse);

      expect(
        view_model.footer.inspection_status,
        contains('1 inspection issue(s)'),
      );
      expect(view_model.footer.inspection_status, contains('/fixture/private'));
    });

    test('preserves target-native paths without interpretation', () {
      const root = r'C:\workspace';
      const child_path = r'C:\workspace\src';

      final model = _model([
        _entry(child_path, FilesystemEntryKind.directory),
      ], root: root);

      final view_model = presenter.present(model, visible_row_limit: 5);

      expect(model.root_directory.value, root);
      expect(view_model.header.current_directory, root);
      expect(view_model.directory.visible_rows.single.path, child_path);
      expect(view_model.directory.visible_rows.single.name, 'src/');
    });

    test('retains row identity when entry paths are duplicated', () {
      final model = _model([
        _entry('/fixture/same', FilesystemEntryKind.regularFile),
        _entry('/fixture/same', FilesystemEntryKind.directory),
      ]).with_selection(1);

      final view_model = presenter.present(model, visible_row_limit: 2);

      expect(
        view_model.directory.visible_rows.map((row) => row.type_label),
        orderedEquals(['Directory', 'File']),
      );

      expect(view_model.directory.selected_index, 1);
      expect(view_model.directory.selected_visible_index, 1);
    });

    test('does not sanitize display text prematurely', () {
      const unsafe_path = '/fixture/unsafe\x1B[31m';

      final model = _model([
        _entry(unsafe_path, FilesystemEntryKind.regularFile),
      ]);

      final view_model = presenter.present(model, visible_row_limit: 1);

      // Renderer sanitization occurs before ANSI encoding.
      // Presentation does not change the observed path.
      expect(view_model.directory.visible_rows.single.path, unsafe_path);
      expect(view_model.directory.visible_rows.single.name, 'unsafe\x1B[31m');
    });

    test('produces immutable presentation collections', () {
      final view_model = presenter.present(
        _model(_six_entries()),
        visible_row_limit: 2,
      );

      expect(
        () => view_model.directory.visible_rows.clear(),
        throwsUnsupportedError,
      );
    });

    test('preserves the closed navigation state', () {
      final model = _model([]).close();

      final view_model = presenter.present(model, visible_row_limit: 5);

      expect(view_model.footer.navigation_hints, 'Explorer closed.');
      expect(model.can_go_back, isFalse);
    });
  });
}

/// Creates one immutable filesystem observation.
///
/// No operating-system filesystem access is performed.
FilesystemEntry _entry(
  String path,
  FilesystemEntryKind kind, {
  int? logical_bytes,
}) {
  return FilesystemEntry(
    path: TargetPath(path),
    kind: kind,
    metadata: FilesystemMetadata(logical_size_bytes: logical_bytes),
  );
}

/// Creates a root ExplorerModel from injected observations.
///
/// The resulting navigation model has no dependency on a
/// native TargetInspector or filesystem service.
ExplorerModel _model(
  List<FilesystemEntry> entries, {
  String root = '/fixture',
  bool is_complete = true,
  List<InspectionIssue> issues = const [],
}) {
  final directory = TargetPath(root);

  return ExplorerModel(
    root_directory: directory,
    listing: DirectoryListing(
      target_id: 'fixture-target',
      directory: directory,
      entries: entries,
      is_complete: is_complete,
      issues: issues,
    ),
  );
}

/// Creates six deliberately ordered fixture entries.
///
/// Their names allow viewport position and selection
/// assertions to remain explicit and deterministic.
List<FilesystemEntry> _six_entries() {
  return [
    for (final name in ['a', 'b', 'c', 'd', 'e', 'f'])
      _entry('/fixture/$name.txt', FilesystemEntryKind.regularFile),
  ];
}
