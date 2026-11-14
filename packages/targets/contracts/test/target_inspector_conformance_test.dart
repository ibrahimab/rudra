import 'dart:async';

import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

import 'support/target_inspector_conformance.dart';

void main() {
  final fixture = TargetInspectorConformanceFixture(
    root_directory: TargetPath('/fixture'),
    regular_file: TargetPath('/fixture/file.bin'),
    child_directory: TargetPath('/fixture/empty'),
    directory_symbolic_link: TargetPath('/fixture/link'),
    dangling_symbolic_link: TargetPath('/fixture/broken'),
    directory_link_target: TargetPath('empty'),
    dangling_link_target: TargetPath('missing-target'),
    missing_path: TargetPath('/fixture/missing'),
    relative_path: TargetPath('relative-entry'),
  );

  run_target_inspector_conformance_tests(
    create_inspector: _ConformanceInspector.new,
    fixture: fixture,
  );

  group('Conformance fixture stream behavior', () {
    test('enumeration is lazy', () async {
      final inspector = _ConformanceInspector();

      final stream = inspector.list_directory(TargetPath('/fixture'));

      expect(inspector.enumeration_starts, 0);

      await stream.toList();

      expect(inspector.enumeration_starts, 1);
    });

    test('retains partial output before terminal errors', () async {
      final inspector = _ConformanceInspector();

      await expectLater(
        inspector.list_directory(TargetPath('/fixture/partial')),
        emitsInOrder([
          isA<TargetPath>().having(
            (path) => path.value,
            'path',
            '/fixture/file.bin',
          ),
          emitsError(
            isA<TargetInspectionException>()
                .having(
                  (error) => error.code,
                  'code',
                  TargetInspectionErrorCode.ioFailure,
                )
                .having(
                  (error) => error.operation,
                  'operation',
                  TargetInspectionOperation.listDirectory,
                ),
          ),
          emitsDone,
        ]),
      );
    });

    test('cancellation finalizes active enumeration', () async {
      final inspector = _ConformanceInspector();

      final iterator = StreamIterator<TargetPath>(
        inspector.list_directory(TargetPath('/fixture')),
      );

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.value, '/fixture/file.bin');

      await iterator.cancel();

      expect(inspector.enumeration_finalizations, 1);
      expect(inspector.enumerated_children, 1);
    });
  });
}

/// Provides a deterministic, read-only filesystem for contract tests.
///
/// The fixture models:
/// - One root directory.
/// - One regular file.
/// - One empty child directory.
/// - One symbolic link to the child directory.
/// - One dangling symbolic link.
/// - One synthetic partial-enumeration failure.
///
/// No real filesystem APIs are used.
///
/// Enumeration instrumentation is provided solely to verify
/// lazy execution and cancellation behavior.
final class _ConformanceInspector implements TargetInspector {
  /// Number of directory streams that began execution.
  int enumeration_starts = 0;

  /// Number of root-directory enumerations that finalized.
  int enumeration_finalizations = 0;

  /// Number of root-directory paths produced by the generator.
  int enumerated_children = 0;

  /// All existing filesystem paths in this fixture.
  static const Set<String> _known_paths = {
    '/fixture',
    '/fixture/file.bin',
    '/fixture/empty',
    '/fixture/link',
    '/fixture/broken',
  };

  /// Reports capabilities for existing fixture paths.
  ///
  /// Missing and relative paths produce typed inspection failures.
  @override
  Future<TargetCapabilities> capabilities_for(TargetPath path) async {
    _require_absolute(path, TargetInspectionOperation.capabilitiesFor);

    if (!_known_paths.contains(path.value)) {
      throw _failure(
        TargetInspectionErrorCode.notFound,
        TargetInspectionOperation.capabilitiesFor,
        path,
      );
    }

    return TargetCapabilities(
      statuses: {
        TargetInspectionFeature.symbolicLinkTarget:
            TargetCapabilityStatus.supported,
      },
    );
  }

  /// Inspects one predefined entry without resolving symbolic links.
  ///
  /// Missing and relative paths produce typed inspection failures.
  @override
  Future<FilesystemEntry> inspect(TargetPath path) async {
    _require_absolute(path, TargetInspectionOperation.inspect);

    final kind = switch (path.value) {
      '/fixture' => FilesystemEntryKind.directory,
      '/fixture/file.bin' => FilesystemEntryKind.regularFile,
      '/fixture/empty' => FilesystemEntryKind.directory,
      '/fixture/link' => FilesystemEntryKind.symbolicLink,
      '/fixture/broken' => FilesystemEntryKind.symbolicLink,
      _ => null,
    };

    if (kind == null) {
      throw _failure(
        TargetInspectionErrorCode.notFound,
        TargetInspectionOperation.inspect,
        path,
      );
    }

    return FilesystemEntry(
      path: path,
      kind: kind,
      metadata: FilesystemMetadata(),
    );
  }

  /// Enumerates fixture children without inspecting their metadata.
  ///
  /// The root directory's generator records when enumeration starts,
  /// how many paths are yielded, and when execution finalizes.
  ///
  /// The synthetic partial directory emits one path before failing.
  ///
  /// All other invalid requests produce typed stream errors.
  @override
  Stream<TargetPath> list_directory(TargetPath path) async* {
    enumeration_starts++;

    _require_absolute(path, TargetInspectionOperation.listDirectory);

    if (path.value == '/fixture') {
      try {
        const children = <String>[
          '/fixture/file.bin',
          '/fixture/empty',
          '/fixture/link',
          '/fixture/broken',
        ];

        for (final child in children) {
          enumerated_children++;
          yield TargetPath(child);
        }
      } finally {
        enumeration_finalizations++;
      }

      return;
    }

    if (path.value == '/fixture/empty') {
      return;
    }

    if (path.value == '/fixture/partial') {
      yield TargetPath('/fixture/file.bin');

      throw _failure(
        TargetInspectionErrorCode.ioFailure,
        TargetInspectionOperation.listDirectory,
        path,
      );
    }

    if (_known_paths.contains(path.value)) {
      throw _failure(
        TargetInspectionErrorCode.notDirectory,
        TargetInspectionOperation.listDirectory,
        path,
      );
    }

    throw _failure(
      TargetInspectionErrorCode.notFound,
      TargetInspectionOperation.listDirectory,
      path,
    );
  }

  /// Reads the stored target of one of the fixture's symbolic links.
  ///
  /// Neither symbolic link is followed or resolved.
  @override
  Future<TargetPath> read_symbolic_link(TargetPath path) async {
    _require_absolute(path, TargetInspectionOperation.readSymbolicLink);

    if (path.value == '/fixture/link') {
      return TargetPath('empty');
    }

    if (path.value == '/fixture/broken') {
      return TargetPath('missing-target');
    }

    if (_known_paths.contains(path.value)) {
      throw _failure(
        TargetInspectionErrorCode.notSymbolicLink,
        TargetInspectionOperation.readSymbolicLink,
        path,
      );
    }

    throw _failure(
      TargetInspectionErrorCode.notFound,
      TargetInspectionOperation.readSymbolicLink,
      path,
    );
  }

  /// Validates absolute paths for this Unix-style test fixture.
  ///
  /// This validation belongs only to the fixture. Real target
  /// adapters must implement their own native path semantics.
  ///
  /// Throws a typed invalid-path error for relative paths.
  void _require_absolute(TargetPath path, TargetInspectionOperation operation) {
    if (!path.value.startsWith('/')) {
      throw _failure(TargetInspectionErrorCode.invalidPath, operation, path);
    }
  }

  /// Creates a typed fixture inspection failure.
  ///
  /// The diagnostic message is intentionally generic because
  /// programmatic tests must rely on the typed error fields.
  TargetInspectionException _failure(
    TargetInspectionErrorCode code,
    TargetInspectionOperation operation,
    TargetPath path,
  ) {
    return TargetInspectionException(
      code: code,
      operation: operation,
      path: path,
      message: 'Fixture inspection failed: ${code.name}.',
    );
  }
}
