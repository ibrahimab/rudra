import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies RudraSdk application composition.
///
/// Tests use an in-memory TargetInspector implementation.
///
/// No native filesystem operations or cleanup actions are
/// performed.
///
/// The SDK facade must remain independent of concrete platform
/// adapters, CLI frameworks, Flutter, and persistence.
void main() {
  group('RudraSdk', () {
    test('constructs without performing filesystem operations', () {
      final inspector = _RecordingTargetInspector();

      final sdk = RudraSdk(
        target_id: 'local-macos',
        inspector: inspector,
      );

      expect(sdk.target_id, 'local-macos');
      expect(sdk.filesystem.target_id, 'local-macos');

      expect(inspector.enumeration_count, 0);
      expect(inspector.inspection_count, 0);
      expect(inspector.capability_count, 0);
      expect(inspector.symbolic_link_count, 0);
    });

    test('exposes a stable filesystem service instance', () {
      final sdk = RudraSdk(
        target_id: 'local-macos',
        inspector: _RecordingTargetInspector(),
      );

      final filesystem = sdk.filesystem;

      expect(sdk.filesystem, same(filesystem));
      expect(filesystem.target_id, sdk.target_id);
    });

    test('delegates filesystem listing to injected inspector', () async {
      final directory = TargetPath('/tmp');

      final file = FilesystemEntry(
        path: TargetPath('/tmp/example.txt'),
        kind: FilesystemEntryKind.regularFile,
        metadata: FilesystemMetadata(
          logical_size_bytes: 1024,
        ),
      );

      final inspector = _RecordingTargetInspector(
        children: [file.path],
        entries: {
          file.path.value: file,
        },
      );

      final sdk = RudraSdk(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final listing = await sdk.filesystem.list(
        directory: directory,
      );

      expect(listing.target_id, sdk.target_id);
      expect(listing.directory, same(directory));
      expect(listing.is_complete, isTrue);
      expect(listing.issues, isEmpty);

      expect(listing.entries, hasLength(1));
      expect(listing.entries.single, same(file));

      expect(
        listing.entries.single.metadata.logical_size_bytes,
        1024,
      );

      expect(inspector.enumeration_count, 1);
      expect(inspector.inspection_count, 1);

      expect(
        inspector.last_enumerated_path,
        same(directory),
      );

      expect(
        inspector.inspected_paths,
        [same(file.path)],
      );

      expect(inspector.capability_count, 0);
      expect(inspector.symbolic_link_count, 0);
    });

    test('preserves target-native Windows paths', () async {
      final directory = TargetPath(
        r'C:\Users\example\Downloads',
      );

      final file = FilesystemEntry(
        path: TargetPath(
          r'C:\Users\example\Downloads\example.txt',
        ),
        kind: FilesystemEntryKind.regularFile,
        metadata: FilesystemMetadata(),
      );

      final inspector = _RecordingTargetInspector(
        children: [file.path],
        entries: {
          file.path.value: file,
        },
      );

      final sdk = RudraSdk(
        target_id: 'local-windows',
        inspector: inspector,
      );

      final listing = await sdk.filesystem.list(
        directory: directory,
      );

      expect(sdk.target_id, 'local-windows');
      expect(listing.target_id, 'local-windows');

      expect(
        listing.directory.value,
        r'C:\Users\example\Downloads',
      );

      expect(
        listing.entries.single.path.value,
        r'C:\Users\example\Downloads\example.txt',
      );

      expect(listing.is_complete, isTrue);
    });

    test('preserves typed partial inspection results', () async {
      final directory = TargetPath('/tmp');

      final successful_entry = FilesystemEntry(
        path: TargetPath('/tmp/accessible.txt'),
        kind: FilesystemEntryKind.regularFile,
        metadata: FilesystemMetadata(),
      );

      final failed_path = TargetPath('/tmp/restricted.txt');

      final failure = TargetInspectionException(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.inspect,
        path: failed_path,
        message: 'Permission denied.',
        cause: StateError('Native diagnostic'),
      );

      final inspector = _RecordingTargetInspector(
        children: [
          successful_entry.path,
          failed_path,
        ],
        entries: {
          successful_entry.path.value: successful_entry,
        },
        failures: {
          failed_path.value: failure,
        },
      );

      final sdk = RudraSdk(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final listing = await sdk.filesystem.list(
        directory: directory,
      );

      expect(listing.is_complete, isFalse);
      expect(listing.entries, [same(successful_entry)]);
      expect(listing.issues, hasLength(1));

      final issue = listing.issues.single;

      expect(
        issue.code,
        TargetInspectionErrorCode.permissionDenied,
      );

      expect(
        issue.operation,
        TargetInspectionOperation.inspect,
      );

      expect(issue.path, same(failed_path));
      expect(issue.message, 'Permission denied.');

      expect(inspector.inspection_count, 2);
    });

    test('rejects invalid target identifiers', () {
      for (final target_id in ['', ' ', '\t', '\n']) {
        expect(
          () => RudraSdk(
            target_id: target_id,
            inspector: _RecordingTargetInspector(),
          ),
          throwsArgumentError,
        );
      }
    });

    test('keeps independently configured SDK instances isolated', () async {
      final first_inspector = _RecordingTargetInspector();
      final second_inspector = _RecordingTargetInspector();

      final first_sdk = RudraSdk(
        target_id: 'target-one',
        inspector: first_inspector,
      );

      final second_sdk = RudraSdk(
        target_id: 'target-two',
        inspector: second_inspector,
      );

      final listing = await first_sdk.filesystem.list(
        directory: TargetPath('/tmp'),
      );

      expect(listing.target_id, 'target-one');

      expect(first_inspector.enumeration_count, 1);
      expect(second_inspector.enumeration_count, 0);

      expect(first_sdk.filesystem, isNot(same(second_sdk.filesystem)));
    });
  });
}

/// A deterministic TargetInspector used for SDK composition tests.
///
/// This fake records read-only operations and provides configured
/// filesystem observations.
///
/// It does not access or modify any real filesystem.
///
/// Unexpected inspection requests fail explicitly rather than
/// returning fabricated observations.
final class _RecordingTargetInspector implements TargetInspector {
  /// Creates an in-memory inspector.
  ///
  /// [children] contains paths returned during enumeration.
  ///
  /// [entries] maps paths to filesystem observations.
  ///
  /// [failures] maps paths to typed inspection exceptions.
  ///
  /// Collections are defensively copied.
  _RecordingTargetInspector({
    List<TargetPath> children = const [],
    Map<String, FilesystemEntry> entries = const {},
    Map<String, TargetInspectionException> failures = const {},
  })  : _children = List<TargetPath>.unmodifiable(children),
        _entries = Map<String, FilesystemEntry>.unmodifiable(entries),
        _failures =
            Map<String, TargetInspectionException>.unmodifiable(failures);

  /// Paths yielded during directory enumeration.
  final List<TargetPath> _children;

  /// Configured filesystem observations.
  final Map<String, FilesystemEntry> _entries;

  /// Configured inspection failures.
  final Map<String, TargetInspectionException> _failures;

  /// Number of directory enumeration operations.
  int enumeration_count = 0;

  /// Number of entry inspection operations.
  int inspection_count = 0;

  /// Number of capability discovery operations.
  int capability_count = 0;

  /// Number of symbolic-link destination reads.
  int symbolic_link_count = 0;

  /// Most recently enumerated directory.
  TargetPath? last_enumerated_path;

  /// Paths submitted for individual inspection.
  final List<TargetPath> inspected_paths = [];

  /// Enumerates the configured immediate children.
  ///
  /// The stream is lazy and performs no filesystem I/O.
  @override
  Stream<TargetPath> list_directory(TargetPath path) async* {
    enumeration_count++;
    last_enumerated_path = path;

    for (final child in _children) {
      yield child;
    }
  }

  /// Returns the configured entry or throws a configured error.
  ///
  /// Unknown paths produce a StateError to reveal test mistakes.
  @override
  Future<FilesystemEntry> inspect(TargetPath path) async {
    inspection_count++;
    inspected_paths.add(path);

    final failure = _failures[path.value];

    if (failure != null) {
      throw failure;
    }

    final entry = _entries[path.value];

    if (entry == null) {
      throw StateError(
        'No fixture configured for ${path.value}',
      );
    }

    return entry;
  }

  /// Rejects unexpected capability discovery requests.
  @override
  Future<TargetCapabilities> capabilities_for(
    TargetPath path,
  ) async {
    capability_count++;

    throw StateError(
      'Unexpected capabilities_for: ${path.value}',
    );
  }

  /// Rejects unexpected symbolic-link reads.
  @override
  Future<TargetPath> read_symbolic_link(
    TargetPath path,
  ) async {
    symbolic_link_count++;

    throw StateError(
      'Unexpected read_symbolic_link: ${path.value}',
    );
  }
}
