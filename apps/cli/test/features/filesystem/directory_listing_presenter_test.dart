import 'package:rudra_cli/src/features/filesystem/directory_listing_presenter.dart';
import 'package:rudra_cli/src/features/filesystem/directory_listing_view_model.dart';
import 'package:rudra_cli/src/core/rendering/theme.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies SDK-to-presentation conversion for directory listings.
///
/// All filesystem observations are constructed in memory.
///
/// Tests enforce the existing compact and detailed presentation
/// contracts without accessing the host filesystem or terminal.
///
/// No SDK operations, cleanup actions, or native adapters run.
void main() {
  const presenter = DirectoryListingPresenter();

  group('DirectoryListingPresenter ordering', () {
    test('compact layout preserves SDK observation order', () {
      final listing = _listing([
        _entry('/fixture/z.txt', FilesystemEntryKind.regularFile),
        _entry('/fixture/docs', FilesystemEntryKind.directory),
        _entry('/fixture/a.txt', FilesystemEntryKind.regularFile),
      ]);

      final model = presenter.present(
        listing,
        layout: DirectoryListingLayout.compact,
      );

      expect(model.layout, DirectoryListingLayout.compact);
      expect(
        model.rows.map((row) => row.path),
        orderedEquals([
          '/fixture/z.txt',
          '/fixture/docs',
          '/fixture/a.txt',
        ]),
      );
    });

    test('defaults to the detailed layout', () {
      final model = presenter.present(_listing([]));

      expect(model.layout, DirectoryListingLayout.detailed);
    });

    test('detailed layout sorts directories before files', () {
      final listing = _listing([
        _entry('/fixture/z.txt', FilesystemEntryKind.regularFile),
        _entry('/fixture/zeta', FilesystemEntryKind.directory),
        _entry('/fixture/Alpha', FilesystemEntryKind.directory),
        _entry('/fixture/a.txt', FilesystemEntryKind.regularFile),
      ]);

      final model = presenter.present(listing);

      expect(
        model.rows.map((row) => row.name),
        orderedEquals([
          'Alpha/',
          'zeta/',
          'a.txt',
          'z.txt',
        ]),
      );

      // The SDK observation must retain its original order.
      expect(listing.entries.first.path.value, '/fixture/z.txt');
    });

    test('uses original paths to break name-order ties', () {
      final listing = _listing([
        _entry('/fixture/a.txt', FilesystemEntryKind.regularFile),
        _entry('/fixture/A.txt', FilesystemEntryKind.regularFile),
      ]);

      final model = presenter.present(listing);

      expect(
        model.rows.map((row) => row.path),
        orderedEquals([
          '/fixture/A.txt',
          '/fixture/a.txt',
        ]),
      );
    });
  });

  group('DirectoryListingPresenter entry presentation', () {
    test('preserves relative names and full paths', () {
      final listing = _listing([
        _entry('/fixture/apps', FilesystemEntryKind.directory),
        _entry('/fixture/readme.txt', FilesystemEntryKind.regularFile),
      ]);

      final model = presenter.present(listing);

      expect(model.directory_path, '/fixture');
      expect(model.target_id, 'fixture-target');
      expect(model.observed_count, 2);

      expect(model.rows[0].name, 'apps/');
      expect(model.rows[0].path, '/fixture/apps');

      expect(model.rows[1].name, 'readme.txt');
      expect(model.rows[1].path, '/fixture/readme.txt');
    });

    test('preserves Windows-native path spelling', () {
      final listing = _listing(
        [
          _entry(
            r'C:\workspace\src',
            FilesystemEntryKind.directory,
          ),
        ],
        directory: r'C:\workspace',
      );

      final model = presenter.present(listing);

      expect(model.directory_path, r'C:\workspace');
      expect(model.rows.single.path, r'C:\workspace\src');
      expect(model.rows.single.name, 'src/');
    });

    test('preserves unexpected paths instead of rewriting them', () {
      final listing = _listing([
        _entry(
          '/fixture-extra/file.txt',
          FilesystemEntryKind.regularFile,
        ),
      ]);

      final model = presenter.present(listing);

      expect(
        model.rows.single.name,
        '/fixture-extra/file.txt',
      );

      expect(
        model.rows.single.path,
        '/fixture-extra/file.txt',
      );
    });

    test('maps entry kinds and semantic styles', () {
      final listing = _listing([
        _entry('/fixture/d', FilesystemEntryKind.directory),
        _entry('/fixture/f', FilesystemEntryKind.regularFile),
        _entry('/fixture/l', FilesystemEntryKind.symbolicLink),
        _entry('/fixture/o', FilesystemEntryKind.other),
      ]);

      final model = presenter.present(
        listing,
        layout: DirectoryListingLayout.compact,
      );

      expect(
        model.rows.map((row) => row.type_label),
        orderedEquals([
          'Directory',
          'File',
          'Link',
          'Other',
        ]),
      );

      expect(
        model.rows.map((row) => row.role),
        orderedEquals([
          TerminalRole.directory,
          TerminalRole.regular_file,
          TerminalRole.symbolic_link,
          TerminalRole.other_entry,
        ]),
      );

      expect(
        model.rows.map((row) => row.compact_type),
        orderedEquals([
          'directory',
          'regularFile',
          'symbolicLink',
          'other',
        ]),
      );
    });

    test('formats logical bytes without recursive accounting', () {
      final listing = _listing([
        _entry(
          '/fixture/d',
          FilesystemEntryKind.directory,
          bytes: 4096,
        ),
        _entry(
          '/fixture/empty.txt',
          FilesystemEntryKind.regularFile,
          bytes: 0,
        ),
        _entry(
          '/fixture/small.txt',
          FilesystemEntryKind.regularFile,
          bytes: 1023,
        ),
        _entry(
          '/fixture/kib.txt',
          FilesystemEntryKind.regularFile,
          bytes: 1024,
        ),
        _entry(
          '/fixture/mib.txt',
          FilesystemEntryKind.regularFile,
          bytes: 1048576,
        ),
      ]);

      final model = presenter.present(
        listing,
        layout: DirectoryListingLayout.compact,
      );

      expect(
        model.rows.map((row) => row.logical_bytes),
        orderedEquals([
          '4096',
          '0',
          '1023',
          '1024',
          '1048576',
        ]),
      );

      expect(
        model.rows.map((row) => row.size_label),
        orderedEquals([
          '—',
          '0 B',
          '1023 B',
          '1.0 KiB',
          '1.0 MiB',
        ]),
      );
    });

    test('formats ordinary and special POSIX permissions', () {
      final listing = _listing([
        _entry(
          '/fixture/file',
          FilesystemEntryKind.regularFile,
          mode: 0x1A4,
        ),
        _entry(
          '/fixture/executable',
          FilesystemEntryKind.regularFile,
          mode: 0x9ED,
        ),
        _entry(
          '/fixture/directory',
          FilesystemEntryKind.directory,
          mode: 0x3ED,
        ),
      ]);

      final model = presenter.present(
        listing,
        layout: DirectoryListingLayout.compact,
      );

      expect(
        model.rows.map((row) => row.permissions),
        orderedEquals([
          '-rw-r--r--',
          '-rwsr-xr-x',
          'drwxr-xr-t',
        ]),
      );
    });

    test('converts timestamps to the established UTC format', () {
      final listing = _listing([
        _entry(
          '/fixture/example.txt',
          FilesystemEntryKind.regularFile,
          modified: DateTime.parse('2026-11-10T23:15:00+02:00'),
        ),
      ]);

      final model = presenter.present(listing);

      expect(model.rows.single.modified_utc, '2026-11-10 21:15');
    });

    test('preserves explicitly unknown metadata', () {
      final listing = _listing([
        _entry(
          '/fixture/unknown',
          FilesystemEntryKind.other,
        ),
      ]);

      final row = presenter.present(listing).rows.single;

      expect(row.logical_bytes, '?');
      expect(row.size_label, '?');
      expect(row.modified_utc, '?');
      expect(row.permissions, '??????????');
    });
  });

  group('DirectoryListingPresenter inspection results', () {
    test('preserves incomplete observations and typed issues', () {
      final issue = InspectionIssue(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/fixture/blocked'),
        message: 'Permission denied.',
      );

      final listing = _listing(
        [
          _entry(
            '/fixture/good.txt',
            FilesystemEntryKind.regularFile,
          ),
        ],
        is_complete: false,
        issues: [issue],
      );

      final model = presenter.present(listing);

      expect(model.is_complete, isFalse);
      expect(model.is_incomplete, isTrue);
      expect(model.observed_count, 1);
      expect(model.issues, hasLength(1));

      final diagnostic = model.issues.single;

      expect(diagnostic.operation, 'inspect');
      expect(diagnostic.code, 'permissionDenied');
      expect(diagnostic.path, '/fixture/blocked');
      expect(diagnostic.message, 'Permission denied.');
    });

    test('preserves incomplete results without typed issues', () {
      final model = presenter.present(
        _listing([], is_complete: false),
      );

      expect(model.is_incomplete, isTrue);
      expect(model.issues, isEmpty);
      expect(model.rows, isEmpty);
    });

    test('defensively preserves immutable collections', () {
      final model = presenter.present(
        _listing([
          _entry(
            '/fixture/file.txt',
            FilesystemEntryKind.regularFile,
          ),
        ]),
      );

      expect(
        () => model.rows.clear(),
        throwsUnsupportedError,
      );

      expect(
        () => model.issues.clear(),
        throwsUnsupportedError,
      );
    });
  });
}

/// Creates a deterministic SDK directory observation.
///
/// No target adapter or filesystem service is invoked.
DirectoryListing _listing(
  List<FilesystemEntry> entries, {
  String directory = '/fixture',
  bool is_complete = true,
  List<InspectionIssue> issues = const [],
}) {
  return DirectoryListing(
    target_id: 'fixture-target',
    directory: TargetPath(directory),
    entries: entries,
    is_complete: is_complete,
    issues: issues,
  );
}

/// Creates an immutable filesystem observation for a test.
///
/// Unknown metadata is represented by null rather than
/// fabricated zero values.
FilesystemEntry _entry(
  String path,
  FilesystemEntryKind kind, {
  int? bytes,
  int? mode,
  DateTime? modified,
}) {
  return FilesystemEntry(
    path: TargetPath(path),
    kind: kind,
    metadata: FilesystemMetadata(
      logical_size_bytes: bytes,
      modified_at: modified,
      permissions:
          mode == null ? null : FilesystemPermissions(posix_mode: mode),
    ),
  );
}
