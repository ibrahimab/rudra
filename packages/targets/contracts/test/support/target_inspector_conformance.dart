import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

/// Describes a known filesystem layout used by inspector tests.
///
/// The caller is responsible for providing an inspector capable of
/// observing the described entries.
///
/// All paths except symbolic-link destinations must be absolute
/// according to the target platform's path semantics.
///
/// The root directory must contain exactly the four named children.
/// The child directory must be empty.
///
/// [directory_symbolic_link] must point to [child_directory].
/// [dangling_symbolic_link] must point to a nonexistent destination.
///
/// The two stored symbolic-link destinations must be relative paths.
///
/// The fixture must remain unchanged while its tests execute.
///
/// Example:
/// ```dart
/// final fixture = TargetInspectorConformanceFixture(
///   root_directory: TargetPath('/fixture'),
///   regular_file: TargetPath('/fixture/file.bin'),
///   child_directory: TargetPath('/fixture/empty'),
///   directory_symbolic_link: TargetPath('/fixture/link'),
///   dangling_symbolic_link: TargetPath('/fixture/broken'),
///   directory_link_target: TargetPath('empty'),
///   dangling_link_target: TargetPath('missing-target'),
///   missing_path: TargetPath('/fixture/missing'),
///   relative_path: TargetPath('relative-entry'),
/// );
/// ```
final class TargetInspectorConformanceFixture {
  /// Creates a fixture specification without performing filesystem I/O.
  ///
  /// Callers must ensure that the supplied paths and symbolic-link
  /// relationships satisfy the documented fixture invariants.
  const TargetInspectorConformanceFixture({
    required this.root_directory,
    required this.regular_file,
    required this.child_directory,
    required this.directory_symbolic_link,
    required this.dangling_symbolic_link,
    required this.directory_link_target,
    required this.dangling_link_target,
    required this.missing_path,
    required this.relative_path,
  });

  /// Directory containing the known fixture entries.
  final TargetPath root_directory;

  /// Existing regular file in the root directory.
  final TargetPath regular_file;

  /// Existing empty directory in the root directory.
  final TargetPath child_directory;

  /// Symbolic link referring to the child directory.
  final TargetPath directory_symbolic_link;

  /// Symbolic link whose destination does not exist.
  final TargetPath dangling_symbolic_link;

  /// Raw stored destination of [directory_symbolic_link].
  final TargetPath directory_link_target;

  /// Raw stored destination of [dangling_symbolic_link].
  final TargetPath dangling_link_target;

  /// Absolute path that does not exist.
  final TargetPath missing_path;

  /// Relative path that inspector operations must reject.
  final TargetPath relative_path;
}

/// Registers reusable behavioral tests for a TargetInspector.
///
/// [create_inspector] must return an inspector capable of reading
/// the entries described by [fixture].
///
/// A fresh inspector is created for every test.
///
/// The suite performs no filesystem setup or mutation. Concrete
/// adapter test packages must create and clean up their own fixtures.
///
/// The tests validate observable contract behavior rather than
/// platform-specific implementation details.
///
/// Example:
/// ```dart
/// run_target_inspector_conformance_tests(
///   create_inspector: FakeTargetInspector.new,
///   fixture: fixture,
/// );
/// ```
///
/// The caller must construct [fixture] before registering the tests.
void run_target_inspector_conformance_tests({
  required TargetInspector Function() create_inspector,
  required TargetInspectorConformanceFixture fixture,
}) {
  group('TargetInspector conformance', () {
    late TargetInspector inspector;

    setUp(() {
      inspector = create_inspector();
    });

    test('reports symbolic-link target capability', () async {
      final capabilities = await inspector.capabilities_for(
        fixture.root_directory,
      );

      expect(
        capabilities.status_for(TargetInspectionFeature.symbolicLinkTarget),
        TargetCapabilityStatus.supported,
      );
    });

    test('identifies regular files', () async {
      final entry = await inspector.inspect(fixture.regular_file);

      expect(entry.kind, FilesystemEntryKind.regularFile);
      expect(entry.path.value, fixture.regular_file.value);
    });

    test('identifies directories', () async {
      final entry = await inspector.inspect(fixture.child_directory);

      expect(entry.kind, FilesystemEntryKind.directory);
      expect(entry.path.value, fixture.child_directory.value);
    });

    test('does not follow directory symbolic links', () async {
      final entry = await inspector.inspect(fixture.directory_symbolic_link);

      expect(entry.kind, FilesystemEntryKind.symbolicLink);
      expect(entry.path.value, fixture.directory_symbolic_link.value);
    });

    test('inspects dangling symbolic links', () async {
      final entry = await inspector.inspect(fixture.dangling_symbolic_link);

      expect(entry.kind, FilesystemEntryKind.symbolicLink);
    });

    test('enumerates immediate children exactly once', () async {
      final paths = await inspector
          .list_directory(fixture.root_directory)
          .map((path) => path.value)
          .toList();

      expect(
        paths,
        unorderedEquals([
          fixture.regular_file.value,
          fixture.child_directory.value,
          fixture.directory_symbolic_link.value,
          fixture.dangling_symbolic_link.value,
        ]),
      );
    });

    test('returns no children for an empty directory', () async {
      final paths = await inspector
          .list_directory(fixture.child_directory)
          .toList();

      expect(paths, isEmpty);
    });

    test('enumeration streams are single-subscription', () async {
      final stream = inspector.list_directory(fixture.root_directory);

      await stream.toList();

      expect(() => stream.listen((_) {}), throwsStateError);
    });

    test('preserves stored relative symbolic-link targets', () async {
      final destination = await inspector.read_symbolic_link(
        fixture.directory_symbolic_link,
      );

      expect(destination.value, fixture.directory_link_target.value);
    });

    test('reads dangling symbolic-link targets', () async {
      final destination = await inspector.read_symbolic_link(
        fixture.dangling_symbolic_link,
      );

      expect(destination.value, fixture.dangling_link_target.value);
    });

    test('reports missing entries during inspection', () async {
      await expectLater(
        inspector.inspect(fixture.missing_path),
        throwsA(
          _inspection_error(
            TargetInspectionErrorCode.notFound,
            TargetInspectionOperation.inspect,
            fixture.missing_path,
          ),
        ),
      );
    });

    test('reports missing capability locations', () async {
      await expectLater(
        inspector.capabilities_for(fixture.missing_path),
        throwsA(
          _inspection_error(
            TargetInspectionErrorCode.notFound,
            TargetInspectionOperation.capabilitiesFor,
            fixture.missing_path,
          ),
        ),
      );
    });

    test('reports missing directory enumeration', () async {
      await expectLater(
        inspector.list_directory(fixture.missing_path),
        emitsInOrder([
          emitsError(
            _inspection_error(
              TargetInspectionErrorCode.notFound,
              TargetInspectionOperation.listDirectory,
              fixture.missing_path,
            ),
          ),
          emitsDone,
        ]),
      );
    });

    test('rejects enumeration of a regular file', () async {
      await expectLater(
        inspector.list_directory(fixture.regular_file),
        emitsInOrder([
          emitsError(
            _inspection_error(
              TargetInspectionErrorCode.notDirectory,
              TargetInspectionOperation.listDirectory,
              fixture.regular_file,
            ),
          ),
          emitsDone,
        ]),
      );
    });

    test('rejects enumeration through symbolic links', () async {
      await expectLater(
        inspector.list_directory(fixture.directory_symbolic_link),
        emitsInOrder([
          emitsError(
            _inspection_error(
              TargetInspectionErrorCode.notDirectory,
              TargetInspectionOperation.listDirectory,
              fixture.directory_symbolic_link,
            ),
          ),
          emitsDone,
        ]),
      );
    });

    test('rejects reading a regular file as a link', () async {
      await expectLater(
        inspector.read_symbolic_link(fixture.regular_file),
        throwsA(
          _inspection_error(
            TargetInspectionErrorCode.notSymbolicLink,
            TargetInspectionOperation.readSymbolicLink,
            fixture.regular_file,
          ),
        ),
      );
    });

    test('reports missing symbolic links', () async {
      await expectLater(
        inspector.read_symbolic_link(fixture.missing_path),
        throwsA(
          _inspection_error(
            TargetInspectionErrorCode.notFound,
            TargetInspectionOperation.readSymbolicLink,
            fixture.missing_path,
          ),
        ),
      );
    });

    test('rejects relative inspection paths', () async {
      await expectLater(
        inspector.inspect(fixture.relative_path),
        throwsA(
          _inspection_error(
            TargetInspectionErrorCode.invalidPath,
            TargetInspectionOperation.inspect,
            fixture.relative_path,
          ),
        ),
      );

      await expectLater(
        inspector.capabilities_for(fixture.relative_path),
        throwsA(
          _inspection_error(
            TargetInspectionErrorCode.invalidPath,
            TargetInspectionOperation.capabilitiesFor,
            fixture.relative_path,
          ),
        ),
      );

      await expectLater(
        inspector.list_directory(fixture.relative_path),
        emitsInOrder([
          emitsError(
            _inspection_error(
              TargetInspectionErrorCode.invalidPath,
              TargetInspectionOperation.listDirectory,
              fixture.relative_path,
            ),
          ),
          emitsDone,
        ]),
      );

      await expectLater(
        inspector.read_symbolic_link(fixture.relative_path),
        throwsA(
          _inspection_error(
            TargetInspectionErrorCode.invalidPath,
            TargetInspectionOperation.readSymbolicLink,
            fixture.relative_path,
          ),
        ),
      );
    });
  });
}

/// Creates a matcher for a typed inspection failure.
///
/// The matcher verifies the error code, operation, and path without
/// depending on human-readable diagnostic messages.
///
/// Paths are compared by their original string values because
/// TargetPath does not currently implement value equality.
Matcher _inspection_error(
  TargetInspectionErrorCode code,
  TargetInspectionOperation operation,
  TargetPath path,
) {
  return isA<TargetInspectionException>()
      .having((error) => error.code, 'code', code)
      .having((error) => error.operation, 'operation', operation)
      .having((error) => error.path.value, 'path', path.value);
}
