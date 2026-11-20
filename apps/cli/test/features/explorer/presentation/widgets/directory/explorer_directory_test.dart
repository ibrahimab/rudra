import 'package:rudra_cli/src/core/rendering/widgets/terminal_widget.dart';
import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/directory/explorer_directory.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/directory/explorer_directory_view_model.dart';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests directory-row rendering using prepared viewport state.
void main() {
  final constraints = TerminalConstraints(columns: 80);

  group('ExplorerDirectory', () {
    test('renders an empty directory and preserves viewport height', () {
      final directory = ExplorerDirectory(
        ExplorerDirectoryViewModel(explorer: _explorer(), visible_row_limit: 3),
      );

      final lines = directory.build(constraints).toList();

      expect(directory.height, 4);
      expect(lines, hasLength(4));
      expect(lines[0].text, contains('NAME'));
      expect(lines[1].text, contains('(empty directory)'));
      expect(lines[2].text, isEmpty);
      expect(lines[3].text, isEmpty);
    });

    test('does not treat an incomplete listing as empty', () {
      final directory = ExplorerDirectory(
        ExplorerDirectoryViewModel(
          explorer: _explorer(is_complete: false),
          visible_row_limit: 2,
        ),
      );

      final lines = directory.build(constraints).toList();

      expect(
        lines[1].text,
        contains('no entries observed; inspection incomplete'),
      );
    });

    test('renders selected entries without changing their order', () {
      final explorer = _explorer(
        entries: [_entry('/workspace/z.txt'), _entry('/workspace/a.txt')],
      ).with_selection(1);

      final directory = ExplorerDirectory(
        ExplorerDirectoryViewModel(explorer: explorer, visible_row_limit: 2),
      );

      final lines = directory.build(constraints).toList();

      expect(lines[1].text, contains('a.txt'));
      expect(lines[2].text, contains('> z.txt'));
    });
  });
}

/// Creates an Explorer snapshot from a supplied listing.
///
/// [entries] contains the observed filesystem entries.
///
/// [is_complete] records whether inspection finished successfully.
ExplorerModel _explorer({
  List<FilesystemEntry> entries = const [],
  bool is_complete = true,
}) {
  final root = TargetPath('/workspace');

  return ExplorerModel(
    root_directory: root,
    listing: DirectoryListing(
      target_id: 'fixture-target',
      directory: root,
      entries: entries,
      is_complete: is_complete,
    ),
  );
}

/// Creates a regular-file observation at [path].
FilesystemEntry _entry(String path) {
  return FilesystemEntry(
    path: TargetPath(path),
    kind: FilesystemEntryKind.regularFile,
    metadata: FilesystemMetadata(),
  );
}
