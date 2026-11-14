@TestOn('mac-os')
import 'dart:io';

import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:rudra_target_macos/rudra_target_macos.dart';
import 'package:test/test.dart';

/// Number of children created for the cancellation test.
///
/// More than one entry ensures that taking a single observation
/// terminates enumeration before the directory is exhausted.
const int _cancellation_fixture_count = 12;

void main() {
  group('macOS TargetInspector conformance', () {
    late Directory fixture;
    late TargetInspector inspector;

    setUp(() async {
      fixture = await Directory.systemTemp.createTemp(
        'rudra_macos_conformance_test_',
      );

      // All tests use the shared interface, not the concrete
      // adapter type.
      inspector = MacOsTargetInspector();
    });

    tearDown(() async {
      // Remove only the disposable fixture owned by this test.
      await fixture.delete(recursive: true);
    });

    test('reports supported, unknown and unsupported features', () async {
      final capabilities = await inspector.capabilities_for(
        TargetPath(fixture.path),
      );

      expect(
        capabilities.status_for(TargetInspectionFeature.logicalFileSize),
        TargetCapabilityStatus.supported,
      );

      expect(
        capabilities.status_for(TargetInspectionFeature.creationTime),
        TargetCapabilityStatus.unknown,
      );

      expect(
        capabilities.status_for(TargetInspectionFeature.effectiveAccess),
        TargetCapabilityStatus.unsupported,
      );

      expect(
        capabilities.status_for(TargetInspectionFeature.symbolicLinkTarget),
        TargetCapabilityStatus.supported,
      );
    });

    test('inspects entries without following final links', () async {
      final file = File('${fixture.path}/original.txt');
      await file.writeAsString('Rudra');

      final link = Link('${fixture.path}/shortcut');
      await link.create('original.txt');

      final file_path = TargetPath(file.path);
      final link_path = TargetPath(link.path);

      final file_entry = await inspector.inspect(file_path);
      final link_entry = await inspector.inspect(link_path);

      expect(file_entry.path, same(file_path));
      expect(file_entry.kind, FilesystemEntryKind.regularFile);
      expect(file_entry.metadata.logical_size_bytes, 5);

      expect(link_entry.path, same(link_path));
      expect(link_entry.kind, FilesystemEntryKind.symbolicLink);
    });

    test('enumerates only immediate directory children', () async {
      final file = File('${fixture.path}/example.txt');
      await file.writeAsString('Data');

      final directory = Directory('${fixture.path}/child');
      await directory.create();

      final nested = File('${directory.path}/nested.txt');
      await nested.writeAsString('Nested');

      final dangling = Link('${fixture.path}/dangling');
      await dangling.create('missing-target');

      final paths = await inspector
          .list_directory(TargetPath(fixture.path))
          .map((child_path) => child_path.value)
          .toList();

      expect(
        paths,
        unorderedEquals([file.path, directory.path, dangling.path]),
      );

      expect(paths, isNot(contains(nested.path)));
    });

    test('enumeration is lazy and single-subscription', () async {
      final path = TargetPath(fixture.path);

      // Creating a stream must not open and enumerate the
      // directory before a listener subscribes.
      final stream = inspector.list_directory(path);

      final file = File('${fixture.path}/created-later.txt');
      await file.writeAsString('Created after stream construction');

      final observed = await stream.toList();

      expect(observed, hasLength(1));
      expect(observed.single.value, file.path);

      // An exhausted single-subscription stream cannot be
      // subscribed to again.
      expect(() => stream.listen((_) {}), throwsStateError);
    });

    test('refuses to enumerate a directory symbolic link', () async {
      final directory = Directory('${fixture.path}/actual');
      await directory.create();

      final link = Link('${fixture.path}/shortcut');
      await link.create('actual');

      final path = TargetPath(link.path);

      await expectLater(
        inspector.list_directory(path),
        emitsInOrder([
          emitsError(
            _contract_error(
              TargetInspectionErrorCode.notDirectory,
              TargetInspectionOperation.listDirectory,
              path,
            ),
          ),
          emitsDone,
        ]),
      );
    });

    test('directory enumeration errors terminate the stream', () async {
      final path = TargetPath('${fixture.path}/missing');

      await expectLater(
        inspector.list_directory(path),
        emitsInOrder([
          emitsError(
            _contract_error(
              TargetInspectionErrorCode.notFound,
              TargetInspectionOperation.listDirectory,
              path,
            ),
          ),
          emitsDone,
        ]),
      );
    });

    test('reads stored link destinations without resolving them', () async {
      const target = '../missing/../original.txt';

      final link = Link('${fixture.path}/shortcut');
      await link.create(target);

      final path = TargetPath(link.path);

      final destination = await inspector.read_symbolic_link(path);

      // Relative components must remain exactly as stored.
      // The destination need not exist.
      expect(destination.value, target);
    });

    test('rejects non-links with the correct error code', () async {
      final file = File('${fixture.path}/regular.txt');
      await file.writeAsString('Not a link');

      final path = TargetPath(file.path);

      await expectLater(
        inspector.read_symbolic_link(path),
        throwsA(
          _contract_error(
            TargetInspectionErrorCode.notSymbolicLink,
            TargetInspectionOperation.readSymbolicLink,
            path,
          ),
        ),
      );
    });

    test('reports missing entries through inspect', () async {
      final path = TargetPath('${fixture.path}/missing');

      await expectLater(
        inspector.inspect(path),
        throwsA(
          _contract_error(
            TargetInspectionErrorCode.notFound,
            TargetInspectionOperation.inspect,
            path,
          ),
        ),
      );
    });

    test('reports inaccessible locations through capabilities', () async {
      // A nonexistent path is deterministically unaddressable.
      // This does not attempt to simulate macOS permission
      // denials, which depend on the test process privileges.
      final path = TargetPath('${fixture.path}/missing');

      await expectLater(
        inspector.capabilities_for(path),
        throwsA(
          _contract_error(
            TargetInspectionErrorCode.notFound,
            TargetInspectionOperation.capabilitiesFor,
            path,
          ),
        ),
      );
    });

    test('rejects relative paths for all four operations', () async {
      final path = TargetPath('relative/location');

      await expectLater(
        inspector.capabilities_for(path),
        throwsA(
          _contract_error(
            TargetInspectionErrorCode.invalidPath,
            TargetInspectionOperation.capabilitiesFor,
            path,
          ),
        ),
      );

      await expectLater(
        inspector.inspect(path),
        throwsA(
          _contract_error(
            TargetInspectionErrorCode.invalidPath,
            TargetInspectionOperation.inspect,
            path,
          ),
        ),
      );

      await expectLater(
        inspector.list_directory(path),
        emitsInOrder([
          emitsError(
            _contract_error(
              TargetInspectionErrorCode.invalidPath,
              TargetInspectionOperation.listDirectory,
              path,
            ),
          ),
          emitsDone,
        ]),
      );

      await expectLater(
        inspector.read_symbolic_link(path),
        throwsA(
          _contract_error(
            TargetInspectionErrorCode.invalidPath,
            TargetInspectionOperation.readSymbolicLink,
            path,
          ),
        ),
      );
    });

    test('supports early cancellation and subsequent enumeration', () async {
      for (var index = 0; index < _cancellation_fixture_count; index++) {
        final file = File('${fixture.path}/entry_$index.txt');
        await file.writeAsString('$index');
      }

      final path = TargetPath(fixture.path);

      // take(1) cancels the upstream subscription when the
      // requested number of events has been received.
      final first = await inspector.list_directory(path).take(1).toList();

      expect(first, hasLength(1));

      // A subsequent independent stream must still enumerate
      // the entire directory.
      final all = await inspector.list_directory(path).toList();

      expect(all, hasLength(_cancellation_fixture_count));
    });
  });
}

/// Matches a failure emitted by any TargetInspector operation.
///
/// This helper checks the portable error contract without relying
/// on native errno values or diagnostic message text.
///
/// The exact TargetPath instance must be preserved by the adapter.
///
/// Example:
/// ```dart
/// final matcher = _contract_error(
///   TargetInspectionErrorCode.notFound,
///   TargetInspectionOperation.inspect,
///   TargetPath('/tmp/missing'),
/// );
/// ```
TypeMatcher<TargetInspectionException> _contract_error(
  TargetInspectionErrorCode code,
  TargetInspectionOperation operation,
  TargetPath path,
) {
  return isA<TargetInspectionException>()
      .having((error) => error.code, 'error code', code)
      .having((error) => error.operation, 'operation', operation)
      .having((error) => error.path, 'original path', same(path));
}
