import 'package:rudra_cli/src/features/filesystem/presentation/widgets/directory_listing/directory_listing_view_model.dart';
import 'package:rudra_cli/src/features/filesystem/presentation/filesystem_view_model.dart';
import 'package:rudra_cli/src/features/filesystem/presentation/widgets/directory_inspection_issues/directory_inspection_issues_view_model.dart';

import 'package:rudra_cli/src/features/welcome/presentation/widgets/commands/welcome_commands_view_model.dart';
import 'package:rudra_cli/src/features/welcome/presentation/widgets/footer/welcome_footer_view_model.dart';
import 'package:rudra_cli/src/features/welcome/presentation/widgets/header/welcome_header_view_model.dart';
import 'package:rudra_cli/src/features/welcome/presentation/widgets/target/welcome_target_view_model.dart';

import 'package:rudra_cli/src/features/welcome/presentation/widgets/commands/welcome_commands_view_model.dart';
import 'package:rudra_cli/src/features/welcome/presentation/widgets/footer/welcome_footer_view_model.dart';
import 'package:rudra_cli/src/features/welcome/presentation/widgets/header/welcome_header_view_model.dart';
import 'package:rudra_cli/src/features/welcome/presentation/widgets/target/welcome_target_view_model.dart';

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

      expect(result.header.product_title, 'RUDRA');
      expect(result.can_inspect, isFalse);
      expect(result.filesystem, isNull);

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

      expect(result.header.product_title, 'RUDRA');
      expect(result.target.target_id, 'local-macos');
      expect(result.target.starting_directory, '/workspace');
      expect(result.can_inspect, isTrue);
      expect(result.filesystem, isNull);
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
        result.target.starting_directory,
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

      final directory = result.filesystem!;

      expect(
        directory.listing.layout,
        DirectoryListingLayout.detailed,
      );

      expect(directory.listing.target_id, 'fixture-target');
      expect(directory.listing.directory_path, '/fixture');
      expect(directory.listing.observed_count, 2);

      // Detailed presentation sorts directories first.
      expect(
        directory.listing.rows.map((row) => row.name),
        orderedEquals([
          'docs/',
          'readme.txt',
        ]),
      );

      expect(directory.listing.rows.last.size_label, '1.0 KiB');

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

      final directory = result.filesystem!;

      expect(directory.listing.is_complete, isFalse);
      expect(directory.listing.observed_count, 1);
      expect(directory.inspection_issues.issues, hasLength(1));
      expect(
        directory.inspection_issues.issues.single.code,
        'permissionDenied',
      );
      expect(
        directory.inspection_issues.issues.single.path,
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
      expect(result.filesystem!.inspection_issues.issues, isEmpty);
      expect(result.filesystem!.listing.observed_count, 0);
    });

    test('does not report absent listings as complete', () {
      final result = presenter.present(
        _welcome_model(),
      );

      expect(result.filesystem, isNull);
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

      expect(first.header.product_title, second.header.product_title);
      expect(first.target.target_id, second.target.target_id);

      expect(
        first.filesystem!.listing.rows.map((row) => row.path),
        orderedEquals(
          second.filesystem!.listing.rows.map((row) => row.path),
        ),
      );
    });
  });

  group('Welcome component invariants', () {
    test('rejects blank product titles', () {
      for (final title in ['', ' ', '\t', '\n']) {
        expect(
          () => WelcomeHeaderViewModel(
            product_title: title,
          ),
          throwsArgumentError,
        );
      }
    });

    test('requires target and starting directory together', () {
      expect(
        () => WelcomeTargetViewModel(
          target_id: 'fixture-target',
        ),
        throwsArgumentError,
      );

      expect(
        () => WelcomeTargetViewModel(
          starting_directory: '/fixture',
        ),
        throwsArgumentError,
      );
    });

    test('rejects blank target information', () {
      expect(
        () => WelcomeTargetViewModel(
          target_id: ' ',
          starting_directory: '/fixture',
        ),
        throwsArgumentError,
      );

      expect(
        () => WelcomeTargetViewModel(
          target_id: 'fixture-target',
          starting_directory: ' ',
        ),
        throwsArgumentError,
      );
    });

    test('rejects blank safety statements', () {
      expect(
        () => WelcomeFooterViewModel(
          safety_statement: ' ',
        ),
        throwsArgumentError,
      );
    });

    test('rejects a listing from another target', () {
      expect(
        () => _welcome_view_model(
          target_id: 'another-target',
          filesystem: _directory_view_model(),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a listing from another directory', () {
      expect(
        () => _welcome_view_model(
          starting_directory: '/other',
          filesystem: _directory_view_model(),
        ),
        throwsArgumentError,
      );
    });

    test('rejects listings without a configured target', () {
      expect(
        () => _welcome_view_model(
          target_id: null,
          starting_directory: null,
          filesystem: _directory_view_model(),
        ),
        throwsArgumentError,
      );
    });

    test('rejects compact filesystem presentation', () {
      expect(
        () => _welcome_view_model(
          filesystem: _directory_view_model(
            layout: DirectoryListingLayout.compact,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('rejects command hints inconsistent with the target', () {
      expect(
        () => _welcome_view_model(
          show_filesystem_commands: false,
        ),
        throwsArgumentError,
      );
    });

    test('accepts matching detailed filesystem presentation', () {
      final model = _welcome_view_model(
        filesystem: _directory_view_model(),
      );

      expect(model.can_inspect, isTrue);
      expect(model.filesystem, isNotNull);
      expect(model.has_incomplete_listing, isFalse);
      expect(model.commands.show_filesystem_commands, isTrue);
    });

    test('accepts unsupported target presentation', () {
      final model = _welcome_view_model(
        target_id: null,
        starting_directory: null,
      );

      expect(model.can_inspect, isFalse);
      expect(model.filesystem, isNull);
      expect(model.commands.show_filesystem_commands, isFalse);
    });
  });
}

/// Creates a complete Welcome presentation for invariant tests.
///
/// Component models remain independent. The root model verifies
/// their cross-component consistency.
///
/// No filesystem inspection or terminal I/O occurs.
WelcomeViewModel _welcome_view_model({
  String? target_id = 'fixture-target',
  String? starting_directory = '/fixture',
  FilesystemViewModel? filesystem,
  bool? show_filesystem_commands,
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
      show_filesystem_commands: show_filesystem_commands ?? target.can_inspect,
    ),
    footer: WelcomeFooterViewModel(
      safety_statement:
          'Inspection never authorizes file modification or deletion.',
    ),
    filesystem: filesystem,
  );
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

/// Builds a filesystem presentation for Welcome invariants.
///
/// A complete, empty directory is used unless a different
/// listing layout is requested.
FilesystemViewModel _directory_view_model({
  DirectoryListingLayout layout = DirectoryListingLayout.detailed,
}) {
  return FilesystemViewModel(
    listing: DirectoryListingViewModel(
      layout: layout,
      directory_path: '/fixture',
      target_id: 'fixture-target',
      is_complete: true,
      rows: [],
    ),
    inspection_issues: DirectoryInspectionIssuesViewModel(
      is_complete: true,
      issues: [],
    ),
  );
}
