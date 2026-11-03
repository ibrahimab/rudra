import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('TargetInspector contract', () {
    final inspector = _FixtureTargetInspector();

    test('exposes target capabilities asynchronously', () async {
      final capabilities = await inspector.capabilities_for(
        TargetPath('/fixture'),
      );

      expect(
        capabilities.status_for(
          TargetInspectionFeature.symbolicLinkTarget,
        ),
        TargetCapabilityStatus.supported,
      );
    });

    test('returns a typed filesystem entry', () async {
      final entry = await inspector.inspect(
        TargetPath('/fixture/link'),
      );

      expect(entry.kind, FilesystemEntryKind.symbolicLink);
      expect(entry.path.value, '/fixture/link');
    });

    test('streams immediate child paths', () async {
      final paths =
          await inspector.list_directory(TargetPath('/fixture')).toList();

      expect(
        paths.map((path) => path.value).toList(),
        [
          '/fixture/file.bin',
          '/fixture/link',
        ],
      );
    });

    test('returns an unresolved relative link target', () async {
      final destination = await inspector.read_symbolic_link(
        TargetPath('/fixture/link'),
      );

      expect(destination.value, '../destination');
    });

    test('reports enumeration failures as stream errors', () async {
      final stream = inspector.list_directory(
        TargetPath('/fixture/file.bin'),
      );

      await expectLater(
        stream,
        emitsInOrder([
          emitsError(
            isA<TargetInspectionException>()
                .having(
                  (error) => error.code,
                  'code',
                  TargetInspectionErrorCode.notDirectory,
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

    test('reports missing entries as typed failures', () async {
      await expectLater(
        inspector.inspect(TargetPath('/fixture/missing')),
        throwsA(
          isA<TargetInspectionException>().having(
            (error) => error.code,
            'code',
            TargetInspectionErrorCode.notFound,
          ),
        ),
      );
    });
  });
}

/// Provides deterministic inspection results without filesystem I/O.
///
/// This fixture proves that the contract can be implemented using
/// ordinary Dart objects and asynchronous primitives.
///
/// It is intentionally limited to a small predefined filesystem.
/// It does not establish full adapter conformance.
final class _FixtureTargetInspector implements TargetInspector {
  /// Reports the capabilities available in the fixture.
  @override
  Future<TargetCapabilities> capabilities_for(
    TargetPath path,
  ) async {
    if (path.value != '/fixture') {
      throw TargetInspectionException(
        code: TargetInspectionErrorCode.notFound,
        operation: TargetInspectionOperation.capabilitiesFor,
        path: path,
        message: 'Fixture path not found.',
      );
    }

    return TargetCapabilities(
      statuses: {
        TargetInspectionFeature.symbolicLinkTarget:
            TargetCapabilityStatus.supported,
      },
    );
  }

  /// Returns predefined filesystem entry observations.
  @override
  Future<FilesystemEntry> inspect(TargetPath path) async {
    final kind = switch (path.value) {
      '/fixture' => FilesystemEntryKind.directory,
      '/fixture/file.bin' => FilesystemEntryKind.regularFile,
      '/fixture/link' => FilesystemEntryKind.symbolicLink,
      _ => null,
    };

    if (kind == null) {
      throw TargetInspectionException(
        code: TargetInspectionErrorCode.notFound,
        operation: TargetInspectionOperation.inspect,
        path: path,
        message: 'Fixture entry not found.',
      );
    }

    return FilesystemEntry(
      path: path,
      kind: kind,
      metadata: FilesystemMetadata(),
    );
  }

  /// Streams the predefined children of the fixture directory.
  @override
  Stream<TargetPath> list_directory(
    TargetPath path,
  ) async* {
    if (path.value != '/fixture') {
      throw TargetInspectionException(
        code: TargetInspectionErrorCode.notDirectory,
        operation: TargetInspectionOperation.listDirectory,
        path: path,
        message: 'Fixture path is not a directory.',
      );
    }

    yield TargetPath('/fixture/file.bin');
    yield TargetPath('/fixture/link');
  }

  /// Returns the fixture symbolic link's raw stored destination.
  @override
  Future<TargetPath> read_symbolic_link(
    TargetPath path,
  ) async {
    if (path.value != '/fixture/link') {
      throw TargetInspectionException(
        code: TargetInspectionErrorCode.notSymbolicLink,
        operation: TargetInspectionOperation.readSymbolicLink,
        path: path,
        message: 'Fixture path is not a symbolic link.',
      );
    }

    return TargetPath('../destination');
  }
}
