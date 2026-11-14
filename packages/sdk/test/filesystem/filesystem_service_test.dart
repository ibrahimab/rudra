import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies the platform-independent filesystem listing service.
///
/// These tests use a deterministic fake TargetInspector.
///
/// No real filesystem operations or cleanup actions are performed.
///
/// The tests establish that SDK orchestration remains independent
/// of native filesystem implementations and CLI presentation.
void main() {
  group('FilesystemService', () {
    test('lists and inspects immediate directory children', () async {
      final directory = TargetPath('/tmp');

      final file = _create_entry(
        '/tmp/example.txt',
        FilesystemEntryKind.regularFile,
        logical_size_bytes: 1024,
      );

      final folder = _create_entry(
        '/tmp/documents',
        FilesystemEntryKind.directory,
      );

      final inspector = _FakeTargetInspector(
        children: [file.path, folder.path],
        entries: {file.path.value: file, folder.path.value: folder},
      );

      final service = FilesystemService(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final listing = await service.list(directory: directory);

      expect(listing.target_id, 'local-macos');
      expect(listing.directory, same(directory));
      expect(listing.is_complete, isTrue);
      expect(listing.issues, isEmpty);
      expect(listing.entries, [same(file), same(folder)]);

      expect(inspector.listed_directories, [same(directory)]);
      expect(inspector.inspected_paths, [same(file.path), same(folder.path)]);

      expect(listing.entries.first.metadata.logical_size_bytes, 1024);
    });

    test('returns a complete result for an empty directory', () async {
      final inspector = _FakeTargetInspector();

      final service = FilesystemService(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final listing = await service.list(directory: TargetPath('/tmp/empty'));

      expect(listing.entries, isEmpty);
      expect(listing.issues, isEmpty);
      expect(listing.is_complete, isTrue);

      expect(inspector.listed_directories, hasLength(1));
      expect(inspector.inspected_paths, isEmpty);
    });

    test('preserves successful entries after child failure', () async {
      final failed_path = TargetPath('/tmp/restricted.txt');

      final successful_entry = _create_entry(
        '/tmp/accessible.txt',
        FilesystemEntryKind.regularFile,
      );

      final failure = TargetInspectionException(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.inspect,
        path: failed_path,
        message: 'Permission denied.',
        cause: StateError('Native diagnostic'),
      );

      final inspector = _FakeTargetInspector(
        children: [failed_path, successful_entry.path],
        entries: {successful_entry.path.value: successful_entry},
        inspection_failures: {failed_path.value: failure},
      );

      final service = FilesystemService(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final listing = await service.list(directory: TargetPath('/tmp'));

      expect(listing.is_complete, isFalse);
      expect(listing.entries, [same(successful_entry)]);
      expect(listing.issues, hasLength(1));

      final issue = listing.issues.single;

      expect(issue.code, TargetInspectionErrorCode.permissionDenied);

      expect(issue.operation, TargetInspectionOperation.inspect);

      expect(issue.path, same(failed_path));
      expect(issue.message, 'Permission denied.');

      // Both children must have been attempted.
      expect(inspector.inspected_paths, hasLength(2));
    });

    test('preserves entries after enumeration failure', () async {
      final directory = TargetPath('/tmp');

      final entry = _create_entry(
        '/tmp/first.txt',
        FilesystemEntryKind.regularFile,
      );

      final failure = TargetInspectionException(
        code: TargetInspectionErrorCode.ioFailure,
        operation: TargetInspectionOperation.listDirectory,
        path: directory,
        message: 'Enumeration interrupted.',
      );

      final inspector = _FakeTargetInspector(
        children: [entry.path],
        entries: {entry.path.value: entry},
        listing_failure: failure,
        fail_after_children: 1,
      );

      final service = FilesystemService(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final listing = await service.list(directory: directory);

      expect(listing.is_complete, isFalse);
      expect(listing.entries, [same(entry)]);
      expect(listing.issues, hasLength(1));

      expect(
        listing.issues.single.operation,
        TargetInspectionOperation.listDirectory,
      );

      expect(listing.issues.single.code, TargetInspectionErrorCode.ioFailure);
    });

    test('reports failure when enumeration cannot begin', () async {
      final directory = TargetPath('/tmp/restricted');

      final failure = TargetInspectionException(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.listDirectory,
        path: directory,
        message: 'Cannot enumerate directory.',
      );

      final inspector = _FakeTargetInspector(
        listing_failure: failure,
        fail_after_children: 0,
      );

      final service = FilesystemService(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final listing = await service.list(directory: directory);

      expect(listing.is_complete, isFalse);
      expect(listing.entries, isEmpty);
      expect(listing.issues, hasLength(1));

      expect(
        listing.issues.single.code,
        TargetInspectionErrorCode.permissionDenied,
      );

      expect(inspector.inspected_paths, isEmpty);
    });

    test('preserves target-native Windows paths', () async {
      final directory = TargetPath(r'C:\Users\example');

      final entry = _create_entry(
        r'C:\Users\example\file.txt',
        FilesystemEntryKind.regularFile,
      );

      final inspector = _FakeTargetInspector(
        children: [entry.path],
        entries: {entry.path.value: entry},
      );

      final service = FilesystemService(
        target_id: 'local-windows',
        inspector: inspector,
      );

      final listing = await service.list(directory: directory);

      expect(listing.target_id, 'local-windows');
      expect(listing.directory, same(directory));

      expect(listing.entries.single.path.value, r'C:\Users\example\file.txt');

      expect(listing.is_complete, isTrue);
    });

    test('rejects blank target identifiers', () {
      for (final target_id in ['', ' ', '\t', '\n']) {
        expect(
          () => FilesystemService(
            target_id: target_id,
            inspector: _FakeTargetInspector(),
          ),
          throwsArgumentError,
        );
      }
    });

    test('propagates unexpected inspection failures', () async {
      final path = TargetPath('/tmp/example.txt');

      final inspector = _FakeTargetInspector(
        children: [path],
        inspection_failures: {path.value: StateError('Unexpected failure')},
      );

      final service = FilesystemService(
        target_id: 'local-macos',
        inspector: inspector,
      );

      await expectLater(
        service.list(directory: TargetPath('/tmp')),
        throwsA(isA<StateError>()),
      );
    });

    test('propagates unexpected enumeration failures', () async {
      final inspector = _FakeTargetInspector(
        listing_failure: StateError('Unexpected enumeration failure'),
        fail_after_children: 0,
      );

      final service = FilesystemService(
        target_id: 'local-macos',
        inspector: inspector,
      );

      await expectLater(
        service.list(directory: TargetPath('/tmp')),
        throwsA(isA<StateError>()),
      );
    });

    test('uses only read-only inspection operations', () async {
      final entry = _create_entry(
        '/tmp/example.txt',
        FilesystemEntryKind.regularFile,
      );

      final inspector = _FakeTargetInspector(
        children: [entry.path],
        entries: {entry.path.value: entry},
      );

      final service = FilesystemService(
        target_id: 'local-macos',
        inspector: inspector,
      );

      await service.list(directory: TargetPath('/tmp'));

      expect(inspector.listed_directories, hasLength(1));
      expect(inspector.inspected_paths, hasLength(1));

      // The service has no reason to discover capabilities or
      // resolve symbolic-link destinations during basic listing.
      expect(inspector.capability_calls, 0);
      expect(inspector.symbolic_link_calls, 0);
    });
  });
}

/// Creates an immutable filesystem entry for a test fixture.
///
/// The function performs no filesystem operations.
FilesystemEntry _create_entry(
  String path,
  FilesystemEntryKind kind, {
  int? logical_size_bytes,
}) {
  return FilesystemEntry(
    path: TargetPath(path),
    kind: kind,
    metadata: FilesystemMetadata(logical_size_bytes: logical_size_bytes),
  );
}

/// A deterministic, in-memory TargetInspector implementation.
///
/// This fake supplies controlled observations and failures.
///
/// It tracks which read-only operations were invoked and
/// allows tests to simulate partial directory enumeration.
///
/// No native filesystem APIs are used.
final class _FakeTargetInspector implements TargetInspector {
  /// Creates a configurable filesystem inspection fixture.
  ///
  /// [children] supplies directory enumeration results.
  ///
  /// [entries] maps target-native paths to filesystem observations.
  ///
  /// [inspection_failures] maps paths to exceptions thrown when
  /// those entries are inspected.
  ///
  /// [listing_failure] is thrown during enumeration after
  /// [fail_after_children] paths have been emitted.
  ///
  /// If no failure position is specified, the failure is thrown
  /// after all configured children have been emitted.
  _FakeTargetInspector({
    List<TargetPath> children = const [],
    Map<String, FilesystemEntry> entries = const {},
    Map<String, Object> inspection_failures = const {},
    this.listing_failure,
    this.fail_after_children,
  }) : children = List<TargetPath>.unmodifiable(children),
       entries = Map<String, FilesystemEntry>.unmodifiable(entries),
       inspection_failures = Map<String, Object>.unmodifiable(
         inspection_failures,
       );

  /// Configured directory children.
  final List<TargetPath> children;

  /// Configured filesystem observations.
  final Map<String, FilesystemEntry> entries;

  /// Configured per-entry failures.
  final Map<String, Object> inspection_failures;

  /// Optional enumeration failure.
  final Object? listing_failure;

  /// Number of emitted children before enumeration fails.
  final int? fail_after_children;

  /// Directories requested through list_directory.
  final List<TargetPath> listed_directories = [];

  /// Paths requested through inspect.
  final List<TargetPath> inspected_paths = [];

  /// Number of capability discovery operations.
  int capability_calls = 0;

  /// Number of symbolic-link destination requests.
  int symbolic_link_calls = 0;

  /// Enumerates configured paths and optionally fails.
  ///
  /// The stream is lazy and single-subscription.
  @override
  Stream<TargetPath> list_directory(TargetPath path) async* {
    listed_directories.add(path);

    for (var index = 0; index < children.length; index++) {
      if (listing_failure != null && fail_after_children == index) {
        throw listing_failure!;
      }

      yield children[index];
    }

    if (listing_failure != null) {
      throw listing_failure!;
    }
  }

  /// Returns a configured observation or throws a configured error.
  ///
  /// Unexpected paths are rejected to expose fixture mistakes.
  @override
  Future<FilesystemEntry> inspect(TargetPath path) async {
    inspected_paths.add(path);

    final failure = inspection_failures[path.value];

    if (failure != null) {
      throw failure;
    }

    final entry = entries[path.value];

    if (entry == null) {
      throw StateError('No fake filesystem entry configured for ${path.value}');
    }

    return entry;
  }

  /// Records unexpected capability discovery.
  ///
  /// Basic directory listings must not require this operation.
  @override
  Future<TargetCapabilities> capabilities_for(TargetPath path) async {
    capability_calls++;

    throw StateError('Unexpected capabilities_for call: ${path.value}');
  }

  /// Records unexpected symbolic-link destination reads.
  ///
  /// Basic directory listings must not require this operation.
  @override
  Future<TargetPath> read_symbolic_link(TargetPath path) async {
    symbolic_link_calls++;

    throw StateError('Unexpected read_symbolic_link call: ${path.value}');
  }
}
