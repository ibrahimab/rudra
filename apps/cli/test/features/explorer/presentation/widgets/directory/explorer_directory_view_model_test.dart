import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/directory/explorer_directory_view_model.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests directory viewport calculations and entry presentation.
///
/// Observations are supplied in memory. Selection and scrolling
/// are exercised without terminal or filesystem operations.
void main() {
  group('ExplorerDirectoryViewModel', () {
    test('preserves Explorer ordering and selection', () {
      final directory = ExplorerDirectoryViewModel(
        explorer: _model([
          _entry('/fixture/zeta.txt', FilesystemEntryKind.regularFile),
          _entry('/fixture/apps', FilesystemEntryKind.directory),
          _entry('/fixture/alpha.txt', FilesystemEntryKind.regularFile),
          _entry('/fixture/link', FilesystemEntryKind.symbolicLink),
        ]),
        visible_row_limit: 10,
      );

      expect(
        directory.visible_rows.map((row) => row.name),
        orderedEquals(['apps/', 'alpha.txt', 'link', 'zeta.txt']),
      );

      expect(directory.selected_index, 0);
      expect(directory.selected_visible_index, 0);
      expect(directory.total_entries, 4);
      expect(directory.visible_rows.first.type_label, 'Directory');
    });

    test('scrolls forward to keep the selected entry visible', () {
      final directory = ExplorerDirectoryViewModel(
        explorer: _model(_six_entries()).with_selection(5),
        visible_row_limit: 2,
      );

      expect(directory.first_visible_index, 4);
      expect(directory.selected_visible_index, 1);

      expect(
        directory.visible_rows.map((row) => row.name),
        orderedEquals(['e.txt', 'f.txt']),
      );

      expect(directory.has_hidden_above, isTrue);
      expect(directory.has_hidden_below, isFalse);
    });

    test('retains the scroll position while selection is visible', () {
      final directory = ExplorerDirectoryViewModel(
        explorer: _model(_six_entries()).with_selection(4),
        visible_row_limit: 2,
        first_visible_index: 4,
      );

      expect(directory.first_visible_index, 4);
      expect(directory.selected_visible_index, 0);
    });

    test('scrolls backward to keep the selected entry visible', () {
      final directory = ExplorerDirectoryViewModel(
        explorer: _model(_six_entries()).with_selection(1),
        visible_row_limit: 2,
        first_visible_index: 4,
      );

      expect(directory.first_visible_index, 1);
      expect(directory.selected_visible_index, 0);

      expect(
        directory.visible_rows.map((row) => row.name),
        orderedEquals(['b.txt', 'c.txt']),
      );
    });

    test('clamps an out-of-range scroll position', () {
      final directory = ExplorerDirectoryViewModel(
        explorer: _model(_six_entries()).with_selection(5),
        visible_row_limit: 2,
        first_visible_index: 1000,
      );

      expect(directory.first_visible_index, 4);
      expect(directory.visible_rows, hasLength(2));
    });

    test('supports a zero-height entry viewport', () {
      final directory = ExplorerDirectoryViewModel(
        explorer: _model(_six_entries()),
        visible_row_limit: 0,
      );

      expect(directory.visible_rows, isEmpty);
      expect(directory.selected_index, 0);
      expect(directory.selected_visible_index, isNull);
      expect(directory.observed_count, 6);
      expect(directory.has_hidden_below, isTrue);
    });

    test('rejects negative viewport dimensions', () {
      expect(
        () => ExplorerDirectoryViewModel(
          explorer: _model([]),
          visible_row_limit: -1,
        ),
        throwsRangeError,
      );
    });

    test('distinguishes empty and incomplete observations', () {
      final empty = ExplorerDirectoryViewModel(
        explorer: _model([]),
        visible_row_limit: 3,
      );

      final incomplete = ExplorerDirectoryViewModel(
        explorer: _model([], is_complete: false),
        visible_row_limit: 3,
      );

      expect(empty.is_empty, isTrue);
      expect(empty.is_complete, isTrue);

      expect(incomplete.is_empty, isFalse);
      expect(incomplete.is_incomplete, isTrue);
      expect(incomplete.observed_count, 0);
    });

    test('preserves partial entries and typed diagnostics', () {
      final issue = InspectionIssue(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/fixture/private'),
        message: 'Cannot inspect entry.',
      );

      final directory = ExplorerDirectoryViewModel(
        explorer: _model(
          [_entry('/fixture/visible.txt', FilesystemEntryKind.regularFile)],
          is_complete: false,
          issues: [issue],
        ),
        visible_row_limit: 5,
      );

      expect(directory.visible_rows.single.name, 'visible.txt');
      expect(directory.is_incomplete, isTrue);

      final diagnostic = directory.inspection_issues.issues.single;

      expect(diagnostic.code, 'permissionDenied');
      expect(diagnostic.path, '/fixture/private');
      expect(diagnostic.message, 'Cannot inspect entry.');
    });

    test('preserves target-native path spelling', () {
      const root = r'C:\workspace';
      const child = r'C:\workspace\src';

      final directory = ExplorerDirectoryViewModel(
        explorer: _model([
          _entry(child, FilesystemEntryKind.directory),
        ], root: root),
        visible_row_limit: 3,
      );

      expect(directory.explorer.current_directory.value, root);
      expect(directory.visible_rows.single.path, child);
      expect(directory.visible_rows.single.name, 'src/');
    });

    test('retains distinct entries sharing the same path', () {
      final directory = ExplorerDirectoryViewModel(
        explorer: _model([
          _entry('/fixture/same', FilesystemEntryKind.regularFile),
          _entry('/fixture/same', FilesystemEntryKind.directory),
        ]).with_selection(1),
        visible_row_limit: 2,
      );

      expect(
        directory.visible_rows.map((row) => row.type_label),
        orderedEquals(['Directory', 'File']),
      );
      expect(directory.selected_visible_index, 1);
    });

    test('retains unsanitized source text for the renderer', () {
      const unsafe_path = '/fixture/unsafe\x1B[31m';

      final directory = ExplorerDirectoryViewModel(
        explorer: _model([
          _entry(unsafe_path, FilesystemEntryKind.regularFile),
        ]),
        visible_row_limit: 2,
      );

      expect(directory.visible_rows.single.path, unsafe_path);
      expect(directory.visible_rows.single.name, 'unsafe\x1B[31m');
    });

    test('exposes immutable visible entry collections', () {
      final directory = ExplorerDirectoryViewModel(
        explorer: _model(_six_entries()),
        visible_row_limit: 2,
      );

      expect(() => directory.visible_rows.clear(), throwsUnsupportedError);
    });
  });
}

/// Creates an Explorer navigation snapshot from supplied observations.
///
/// [entries] contains the successfully observed filesystem entries.
///
/// [root] is the directory used for the navigation snapshot.
///
/// [is_complete] indicates whether the directory listing completed.
///
/// [issues] contains inspection diagnostics from that listing.
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

/// Creates an observed filesystem entry.
///
/// [path] is the target-native entry path.
///
/// [kind] identifies the observed filesystem entry type.
FilesystemEntry _entry(String path, FilesystemEntryKind kind) {
  return FilesystemEntry(
    path: TargetPath(path),
    kind: kind,
    metadata: FilesystemMetadata(),
  );
}

/// Creates six entries for deterministic viewport tests.
List<FilesystemEntry> _six_entries() {
  return [
    for (final name in ['a', 'b', 'c', 'd', 'e', 'f'])
      _entry('/fixture/$name.txt', FilesystemEntryKind.regularFile),
  ];
}
