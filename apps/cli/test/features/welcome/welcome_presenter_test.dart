import 'package:rudra_cli/src/features/filesystem/directory_listing_view_model.dart';
import 'package:rudra_cli/src/features/welcome/welcome_model.dart';
import 'package:rudra_cli/src/features/welcome/welcome_presenter.dart';
import 'package:rudra_cli/src/features/welcome/welcome_view_model.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies the welcome presentation pipeline.
///
/// Tests use constructed SDK observations rather than live
/// filesystem services or native target adapters.
///
/// The presenter must preserve the existing welcome model's
/// target identity, paths, and inspection completeness.
///
/// No terminal output or filesystem mutations occur.
void main() {
  const presenter = WelcomePresenter();

  group('WelcomePresenter', () {
    test('prepares the application title', () {
      final model = WelcomeModel(
        product_name: 'Rudra',
      );

      final result = presenter.present(model);

      expect(result.product_title, 'RUDRA');
      expect(result.can_inspect, isFalse);
      expect(result.listing, isNull);

      // Presentation must not modify source state.
      expect(model.product_name, 'Rudra');
    });

    test('preserves configured target information', () {
      final model = WelcomeModel(
        product_name: 'Rudra',
        target_id: 'local-macos',
        starting_directory: TargetPath('/workspace'),
      );

      final result = presenter.present(model);

      expect(result.product_title, 'RUDRA');
      expect(result.target_id, 'local-macos');
      expect(result.starting_directory, '/workspace');
      expect(result.can_inspect, isTrue);
      expect(result.listing, isNull);
    });

    test('preserves target-native Windows paths', () {
      final result = presenter.present(
        WelcomeModel(
          product_name: 'Rudra',
          target_id: 'local-windows',
          starting_directory: TargetPath(
            r'C:\Users\example',
          ),
        ),
      );

      expect(
        result.starting_directory,
        r'C:\Users\example',
      );
    });

    test('creates a detailed filesystem view model', () {
      final listing = _listing([
        _entry(
          '/fixture/readme.txt',
          FilesystemEntryKind.regularFile,
          bytes: 1024,
        ),
        _entry(
          '/fixture/docs',
          FilesystemEntryKind.directory,
        ),
      ]);

      final result = presenter.present(
        _welcome_model(listing: listing),
      );

      final directory = result.listing!;

      expect(
        directory.layout,
        DirectoryListingLayout.detailed,
      );

      expect(directory.target_id, 'fixture-target');
      expect(directory.directory_path, '/fixture');
      expect(directory.observed_count, 2);

      // Detailed presentation sorts directories first.
      expect(
        directory.rows.map((row) => row.name),
        orderedEquals([
          'docs/',
          'readme.txt',
        ]),
      );

      expect(directory.rows.last.size_label, '1.0 KiB');

      // The original SDK observation remains unchanged.
      expect(
        listing.entries.first.path.value,
        '/fixture/readme.txt',
      );
    });

    test('preserves incomplete inspection results', () {
      final issue = InspectionIssue(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/fixture/blocked'),
        message: 'Permission denied.',
      );

      final listing = _listing(
        [
          _entry(
            '/fixture/visible.txt',
            FilesystemEntryKind.regularFile,
          ),
        ],
        is_complete: false,
        issues: [issue],
      );

      final result = presenter.present(
        _welcome_model(listing: listing),
      );

      expect(result.has_incomplete_listing, isTrue);

      final directory = result.listing!;

      expect(directory.is_complete, isFalse);
      expect(directory.observed_count, 1);
      expect(directory.issues, hasLength(1));
      expect(
        directory.issues.single.code,
        'permissionDenied',
      );
      expect(
        directory.issues.single.path,
        '/fixture/blocked',
      );
    });

    test('preserves incomplete results without issues', () {
      final result = presenter.present(
        _welcome_model(
          listing: _listing(
            [],
            is_complete: false,
          ),
        ),
      );

      expect(result.has_incomplete_listing, isTrue);
      expect(result.listing!.issues, isEmpty);
      expect(result.listing!.observed_count, 0);
    });

    test('does not report absent listings as complete', () {
      final result = presenter.present(
        _welcome_model(),
      );

      expect(result.listing, isNull);
      expect(result.has_incomplete_listing, isFalse);
    });

    test('produces deterministic presentation data', () {
      final model = _welcome_model(
        listing: _listing([
          _entry(
            '/fixture/example.txt',
            FilesystemEntryKind.regularFile,
          ),
        ]),
      );

      final first = presenter.present(model);
      final second = presenter.present(model);

      expect(first.product_title, second.product_title);
      expect(first.target_id, second.target_id);

      expect(
        first.listing!.rows.map((row) => row.path),
        orderedEquals(
          second.listing!.rows.map((row) => row.path),
        ),
      );
    });
  });

  group('WelcomeViewModel invariants', () {
    test('rejects blank product titles', () {
      for (final title in ['', ' ', '\t', '\n']) {
        expect(
          () => WelcomeViewModel(
            product_title: title,
          ),
          throwsArgumentError,
        );
      }
    });

    test('requires target and directory together', () {
      expect(
        () => WelcomeViewModel(
          product_title: 'RUDRA',
          target_id: 'fixture-target',
        ),
        throwsArgumentError,
      );

      expect(
        () => WelcomeViewModel(
          product_title: 'RUDRA',
          starting_directory: '/fixture',
        ),
        throwsArgumentError,
      );
    });

    test('rejects blank target and directory values', () {
      expect(
        () => WelcomeViewModel(
          product_title: 'RUDRA',
          target_id: ' ',
          starting_directory: '/fixture',
        ),
        throwsArgumentError,
      );

      expect(
        () => WelcomeViewModel(
          product_title: 'RUDRA',
          target_id: 'fixture-target',
          starting_directory: ' ',
        ),
        throwsArgumentError,
      );
    });

    test('rejects a listing for another target', () {
      expect(
        () => WelcomeViewModel(
          product_title: 'RUDRA',
          target_id: 'another-target',
          starting_directory: '/fixture',
          listing: _directory_view_model(),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a listing for another directory', () {
      expect(
        () => WelcomeViewModel(
          product_title: 'RUDRA',
          target_id: 'fixture-target',
          starting_directory: '/other',
          listing: _directory_view_model(),
        ),
        throwsArgumentError,
      );
    });

    test('rejects compact listings on the welcome screen', () {
      expect(
        () => WelcomeViewModel(
          product_title: 'RUDRA',
          target_id: 'fixture-target',
          starting_directory: '/fixture',
          listing: _directory_view_model(
            layout: DirectoryListingLayout.compact,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('accepts a matching detailed listing', () {
      final model = WelcomeViewModel(
        product_title: 'RUDRA',
        target_id: 'fixture-target',
        starting_directory: '/fixture',
        listing: _directory_view_model(),
      );

      expect(model.can_inspect, isTrue);
      expect(model.listing, isNotNull);
      expect(model.has_incomplete_listing, isFalse);
    });
  });
}

/// Creates a configured welcome presentation source.
///
/// The directory and target identifiers match the SDK
/// observation fixtures used by this test suite.
WelcomeModel _welcome_model({
  DirectoryListing? listing,
}) {
  return WelcomeModel(
    product_name: 'Rudra',
    target_id: 'fixture-target',
    starting_directory: TargetPath('/fixture'),
    listing: listing,
  );
}

/// Creates a deterministic SDK directory observation.
///
/// Observations are constructed in memory without calling
/// a TargetInspector or SDK application service.
DirectoryListing _listing(
  List<FilesystemEntry> entries, {
  bool is_complete = true,
  List<InspectionIssue> issues = const [],
}) {
  return DirectoryListing(
    target_id: 'fixture-target',
    directory: TargetPath('/fixture'),
    entries: entries,
    is_complete: is_complete,
    issues: issues,
  );
}

/// Constructs one filesystem entry with optional logical size.
///
/// Missing metadata is represented explicitly as unknown.
FilesystemEntry _entry(
  String path,
  FilesystemEntryKind kind, {
  int? bytes,
}) {
  return FilesystemEntry(
    path: TargetPath(path),
    kind: kind,
    metadata: FilesystemMetadata(
      logical_size_bytes: bytes,
    ),
  );
}

/// Creates a directory view model for invariant testing.
///
/// Defaults to a complete detailed observation with no entries.
DirectoryListingViewModel _directory_view_model({
  DirectoryListingLayout layout = DirectoryListingLayout.detailed,
}) {
  return DirectoryListingViewModel(
    layout: layout,
    directory_path: '/fixture',
    target_id: 'fixture-target',
    is_complete: true,
    rows: [],
    issues: [],
  );
}
