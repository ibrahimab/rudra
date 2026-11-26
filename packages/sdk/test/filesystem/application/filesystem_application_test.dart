import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies authoritative filesystem observation orchestration
/// using deterministic platform-independent inspection fixtures.
void main() {
  group('FilesystemApplication', () {
    test('observes immediate directory children lazily', () async {
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

      final application = FilesystemApplication(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final stream = application.observe_directory(directory: directory);

      expect(application.target_id, 'local-macos');
      expect(inspector.listed_directories, isEmpty);
      expect(inspector.inspected_paths, isEmpty);

      final observations = await stream.toList();

      expect(observations.map((item) => item.entry), [
        same(file),
        same(folder),
      ]);

      expect(observations.map((item) => item.issue), everyElement(isNull));

      expect(inspector.listed_directories, [same(directory)]);
      expect(inspector.inspected_paths, [same(file.path), same(folder.path)]);

      expect(observations.first.entry!.metadata.logical_size_bytes, 1024);
    });

    test('produces no observations for an empty directory', () async {
      final inspector = _FakeTargetInspector();

      final application = FilesystemApplication(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final observations = await application
          .observe_directory(directory: TargetPath('/tmp/empty'))
          .toList();

      expect(observations, isEmpty);
      expect(inspector.listed_directories, hasLength(1));
      expect(inspector.inspected_paths, isEmpty);
    });

    test('continues inspection after a typed child failure', () async {
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

      final application = FilesystemApplication(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final observations = await application
          .observe_directory(directory: TargetPath('/tmp'))
          .toList();

      expect(observations, hasLength(2));
      expect(observations.first.entry, isNull);

      final issue = observations.first.issue!;

      expect(issue.code, failure.code);
      expect(issue.operation, failure.operation);
      expect(issue.path, same(failed_path));
      expect(issue.message, failure.message);

      expect(observations.last.entry, same(successful_entry));
      expect(observations.last.issue, isNull);

      expect(inspector.inspected_paths, [
        same(failed_path),
        same(successful_entry.path),
      ]);
    });

    test('preserves observations before enumeration failure', () async {
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

      final application = FilesystemApplication(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final observations = await application
          .observe_directory(directory: directory)
          .toList();

      expect(observations, hasLength(2));
      expect(observations.first.entry, same(entry));
      expect(observations.last.entry, isNull);

      final issue = observations.last.issue!;

      expect(issue.code, failure.code);
      expect(issue.operation, failure.operation);
      expect(issue.path, same(directory));
      expect(issue.message, failure.message);
    });

    test('reports a typed failure when enumeration cannot begin', () async {
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

      final application = FilesystemApplication(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final observations = await application
          .observe_directory(directory: directory)
          .toList();

      expect(observations, hasLength(1));
      expect(observations.single.entry, isNull);
      expect(observations.single.issue!.code, failure.code);
      expect(observations.single.issue!.operation, failure.operation);
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

      final application = FilesystemApplication(
        target_id: 'local-windows',
        inspector: inspector,
      );

      final observations = await application
          .observe_directory(directory: directory)
          .toList();

      expect(application.target_id, 'local-windows');
      expect(inspector.listed_directories, [same(directory)]);
      expect(observations.single.entry, same(entry));

      expect(
        observations.single.entry!.path.value,
        r'C:\Users\example\file.txt',
      );
    });

    test('rejects blank target identifiers', () {
      for (final target_id in ['', ' ', '\t\n']) {
        expect(
          () => FilesystemApplication(
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
        inspection_failures: {
          path.value: StateError('Unexpected inspection failure.'),
        },
      );

      final application = FilesystemApplication(
        target_id: 'local-macos',
        inspector: inspector,
      );

      await expectLater(
        application.observe_directory(directory: TargetPath('/tmp')).toList(),
        throwsStateError,
      );
    });

    test('propagates unexpected enumeration failures', () async {
      final inspector = _FakeTargetInspector(
        listing_failure: StateError('Unexpected enumeration failure.'),
        fail_after_children: 0,
      );

      final application = FilesystemApplication(
        target_id: 'local-macos',
        inspector: inspector,
      );

      await expectLater(
        application.observe_directory(directory: TargetPath('/tmp')).toList(),
        throwsStateError,
      );
    });

    test('uses only the required read-only inspection operations', () async {
      final entry = _create_entry(
        '/tmp/example.txt',
        FilesystemEntryKind.regularFile,
      );

      final inspector = _FakeTargetInspector(
        children: [entry.path],
        entries: {entry.path.value: entry},
      );

      final application = FilesystemApplication(
        target_id: 'local-macos',
        inspector: inspector,
      );

      await application
          .observe_directory(directory: TargetPath('/tmp'))
          .toList();

      expect(inspector.listed_directories, hasLength(1));
      expect(inspector.inspected_paths, hasLength(1));

      expect(inspector.capability_calls, 0);
      expect(inspector.symbolic_link_calls, 0);
    });

    test('cancellation prevents inspection of remaining children', () async {
      final first = _create_entry(
        '/tmp/first.txt',
        FilesystemEntryKind.regularFile,
      );

      final second = _create_entry(
        '/tmp/second.txt',
        FilesystemEntryKind.regularFile,
      );

      final inspector = _FakeTargetInspector(
        children: [first.path, second.path],
        entries: {first.path.value: first, second.path.value: second},
      );

      final application = FilesystemApplication(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final observation = await application
          .observe_directory(directory: TargetPath('/tmp'))
          .first;

      expect(observation.entry, same(first));
      expect(inspector.inspected_paths, [same(first.path)]);
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
