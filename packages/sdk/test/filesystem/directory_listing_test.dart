
import 'package:rudra_sdk/src/filesystem/directory_listing.dart';
import 'package:rudra_sdk/src/filesystem/inspection_issue.dart';
import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

/// Verifies the standardized directory-listing response contract.
///
/// Tests use in-memory domain objects and perform no filesystem I/O.
///
/// The tests establish invariants that must remain consistent
/// across SDK services, CLI consumers, Flutter applications,
/// and future serialization boundaries.
void main() {
  group('DirectoryListing', () {
    test('represents a complete empty directory', () {
      final directory = TargetPath('/tmp/empty');

      final listing = DirectoryListing(
        target_id: 'local-macos',
        directory: directory,
        entries: [],
        is_complete: true,
      );

      expect(listing.target_id, 'local-macos');
      expect(listing.directory, same(directory));
      expect(listing.entries, isEmpty);
      expect(listing.issues, isEmpty);
      expect(listing.is_complete, isTrue);
    });

    test('preserves filesystem entries and metadata', () {
      final metadata = FilesystemMetadata(
        logical_size_bytes: 1024,
        allocated_size_bytes: 4096,
      );

      final entry = FilesystemEntry(
        path: TargetPath('/tmp/example.txt'),
        kind: FilesystemEntryKind.regularFile,
        metadata: metadata,
      );

      final listing = DirectoryListing(
        target_id: 'local-macos',
        directory: TargetPath('/tmp'),
        entries: [entry],
        is_complete: true,
      );

      expect(listing.entries, hasLength(1));
      expect(listing.entries.single, same(entry));

      expect(
        listing.entries.single.metadata,
        same(metadata),
      );

      expect(
        listing.entries.single.metadata.logical_size_bytes,
        1024,
      );

      expect(
        listing.entries.single.metadata.allocated_size_bytes,
        4096,
      );
    });

    test('preserves different filesystem entry kinds', () {
      final entries = [
        FilesystemEntry(
          path: TargetPath('/tmp/file.txt'),
          kind: FilesystemEntryKind.regularFile,
          metadata: FilesystemMetadata(),
        ),
        FilesystemEntry(
          path: TargetPath('/tmp/directory'),
          kind: FilesystemEntryKind.directory,
          metadata: FilesystemMetadata(),
        ),
        FilesystemEntry(
          path: TargetPath('/tmp/link'),
          kind: FilesystemEntryKind.symbolicLink,
          metadata: FilesystemMetadata(),
        ),
      ];

      final listing = DirectoryListing(
        target_id: 'local-macos',
        directory: TargetPath('/tmp'),
        entries: entries,
        is_complete: true,
      );

      expect(
        listing.entries.map((entry) => entry.kind),
        [
          FilesystemEntryKind.regularFile,
          FilesystemEntryKind.directory,
          FilesystemEntryKind.symbolicLink,
        ],
      );
    });

    test('defensively copies filesystem entries', () {
      final entry = FilesystemEntry(
        path: TargetPath('/tmp/example.txt'),
        kind: FilesystemEntryKind.regularFile,
        metadata: FilesystemMetadata(),
      );

      final entries = <FilesystemEntry>[entry];

      final listing = DirectoryListing(
        target_id: 'local-macos',
        directory: TargetPath('/tmp'),
        entries: entries,
        is_complete: true,
      );

      entries.clear();

      expect(listing.entries, hasLength(1));
      expect(listing.entries.single, same(entry));

      expect(
        () => listing.entries.clear(),
        throwsUnsupportedError,
      );
    });

    test('preserves partial results with inspection issues', () {
      final entry = FilesystemEntry(
        path: TargetPath('/tmp/accessible.txt'),
        kind: FilesystemEntryKind.regularFile,
        metadata: FilesystemMetadata(),
      );

      final issue = InspectionIssue(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/tmp/restricted.txt'),
        message: 'Permission denied.',
      );

      final listing = DirectoryListing(
        target_id: 'local-macos',
        directory: TargetPath('/tmp'),
        entries: [entry],
        is_complete: false,
        issues: [issue],
      );

      expect(listing.is_complete, isFalse);
      expect(listing.entries, hasLength(1));
      expect(listing.entries.single, same(entry));

      expect(listing.issues, hasLength(1));
      expect(listing.issues.single, same(issue));

      expect(
        listing.issues.single.code,
        TargetInspectionErrorCode.permissionDenied,
      );

      expect(
        listing.issues.single.operation,
        TargetInspectionOperation.inspect,
      );
    });

    test('defensively copies inspection issues', () {
      final issue = InspectionIssue(
        code: TargetInspectionErrorCode.ioFailure,
        operation: TargetInspectionOperation.listDirectory,
        path: TargetPath('/tmp'),
        message: 'Directory enumeration failed.',
      );

      final issues = <InspectionIssue>[issue];

      final listing = DirectoryListing(
        target_id: 'local-macos',
        directory: TargetPath('/tmp'),
        entries: [],
        is_complete: false,
        issues: issues,
      );

      issues.clear();

      expect(listing.issues, hasLength(1));
      expect(listing.issues.single, same(issue));

      expect(
        () => listing.issues.clear(),
        throwsUnsupportedError,
      );
    });

    test('rejects blank target identifiers', () {
      for (final target_id in ['', ' ', '\t', '\n']) {
        expect(
          () => DirectoryListing(
            target_id: target_id,
            directory: TargetPath('/tmp'),
            entries: [],
            is_complete: true,
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects complete listings with issues', () {
      final issue = InspectionIssue(
        code: TargetInspectionErrorCode.notFound,
        operation: TargetInspectionOperation.inspect,
        path: TargetPath('/tmp/missing'),
        message: 'Entry not found.',
      );

      expect(
        () => DirectoryListing(
          target_id: 'local-macos',
          directory: TargetPath('/tmp'),
          entries: [],
          is_complete: true,
          issues: [issue],
        ),
        throwsArgumentError,
      );
    });

    test('allows incomplete listings without issues', () {
      final listing = DirectoryListing(
        target_id: 'local-macos',
        directory: TargetPath('/tmp'),
        entries: [],
        is_complete: false,
      );

      expect(listing.is_complete, isFalse);
      expect(listing.issues, isEmpty);
    });

    test('preserves Windows-native paths', () {
      final directory = TargetPath(
        r'C:\Users\example\Downloads',
      );

      final entry = FilesystemEntry(
        path: TargetPath(
          r'C:\Users\example\Downloads\file.txt',
        ),
        kind: FilesystemEntryKind.regularFile,
        metadata: FilesystemMetadata(),
      );

      final listing = DirectoryListing(
        target_id: 'local-windows',
        directory: directory,
        entries: [entry],
        is_complete: true,
      );

      expect(listing.target_id, 'local-windows');

      expect(
        listing.directory.value,
        r'C:\Users\example\Downloads',
      );

      expect(
        listing.entries.single.path.value,
        r'C:\Users\example\Downloads\file.txt',
      );
    });
  });
}
