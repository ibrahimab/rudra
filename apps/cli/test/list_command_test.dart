import 'package:rudra_cli/rudra_cli.dart';
import 'package:rudra_cli/src/commands/filesystem_cli_module.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies filesystem command integration with Rudra's CLI.
///
/// These tests exercise real command registration and dispatch
/// using a fake, read-only TargetInspector.
///
/// No native filesystem access or cleanup is performed.
void main() {
  group('FilesystemCliModule', () {
    test('registers ls without inspecting the filesystem', () {
      final inspector = _FakeTargetInspector();

      final sdk = RudraSdk(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final cli = RudraCli();

      cli.register_module(
        FilesystemCliModule(
          sdk: sdk,
          working_directory: TargetPath('/tmp'),
        ),
      );

      expect(cli.command_names, contains('ls'));

      expect(
        cli.module_ids,
        contains('rudra.product.filesystem'),
      );

      expect(inspector.listed_directories, isEmpty);
      expect(inspector.inspected_paths, isEmpty);
    });
  });

  group('ListCommand', () {
    test('defaults to the injected working directory', () async {
      final directory = TargetPath('/tmp/work');

      final entry = _create_entry(
        '/tmp/work/example.txt',
        FilesystemEntryKind.regularFile,
        logical_size_bytes: 1024,
      );

      final inspector = _FakeTargetInspector(
        children: [entry.path],
        entries: {
          entry.path.value: entry,
        },
      );

      final output = StringBuffer();
      final errors = StringBuffer();

      final cli = _create_cli(
        inspector: inspector,
        working_directory: directory,
        output: output,
        error_output: errors,
      );

      final status = await cli.run(['ls']);

      expect(status, RudraExitCode.success.value);

      expect(
        inspector.listed_directories,
        [same(directory)],
      );

      expect(
        inspector.inspected_paths,
        [same(entry.path)],
      );

      expect(
        output.toString(),
        contains('regularFile\t1024\t/tmp/work/example.txt'),
      );

      expect(errors.toString(), isEmpty);
    });

    test('accepts an explicit absolute directory', () async {
      final directory = TargetPath('/tmp/default');
      final requested_directory = '/tmp/other';

      final inspector = _FakeTargetInspector();

      final cli = _create_cli(
        inspector: inspector,
        working_directory: directory,
        output: StringBuffer(),
        error_output: StringBuffer(),
      );

      final status = await cli.run([
        'ls',
        requested_directory,
      ]);

      expect(status, RudraExitCode.success.value);

      expect(
        inspector.listed_directories.single.value,
        requested_directory,
      );
    });

    test('renders unknown logical sizes explicitly', () async {
      final entry = _create_entry(
        '/tmp/link',
        FilesystemEntryKind.symbolicLink,
      );

      final inspector = _FakeTargetInspector(
        children: [entry.path],
        entries: {
          entry.path.value: entry,
        },
      );

      final output = StringBuffer();

      final cli = _create_cli(
        inspector: inspector,
        working_directory: TargetPath('/tmp'),
        output: output,
        error_output: StringBuffer(),
      );

      final status = await cli.run(['ls']);

      expect(status, RudraExitCode.success.value);

      expect(
        output.toString(),
        contains('symbolicLink\t?\t/tmp/link'),
      );

      expect(inspector.symbolic_link_calls, 0);
    });

    test('preserves partial results and reports typed issues', () async {
      final successful_entry = _create_entry(
        '/tmp/accessible.txt',
        FilesystemEntryKind.regularFile,
        logical_size_bytes: 512,
      );

      final failed_path = TargetPath('/tmp/restricted.txt');

      final failure = TargetInspectionException(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.inspect,
        path: failed_path,
        message: 'Permission denied.',
      );

      final inspector = _FakeTargetInspector(
        children: [
          successful_entry.path,
          failed_path,
        ],
        entries: {
          successful_entry.path.value: successful_entry,
        },
        inspection_failures: {
          failed_path.value: failure,
        },
      );

      final output = StringBuffer();
      final errors = StringBuffer();

      final cli = _create_cli(
        inspector: inspector,
        working_directory: TargetPath('/tmp'),
        output: output,
        error_output: errors,
      );

      final status = await cli.run(['ls']);

      expect(
        status,
        RudraExitCode.inspection_incomplete.value,
      );

      expect(
        output.toString(),
        contains('regularFile\t512\t/tmp/accessible.txt'),
      );

      expect(errors.toString(), contains('permissionDenied'));
      expect(errors.toString(), contains('/tmp/restricted.txt'));
      expect(errors.toString(), contains('Permission denied.'));

      expect(inspector.inspected_paths, hasLength(2));
    });

    test('reports directory enumeration failures', () async {
      final directory = TargetPath('/tmp/restricted');

      final failure = TargetInspectionException(
        code: TargetInspectionErrorCode.permissionDenied,
        operation: TargetInspectionOperation.listDirectory,
        path: directory,
        message: 'Cannot enumerate directory.',
      );

      final inspector = _FakeTargetInspector(
        enumeration_failure: failure,
      );

      final errors = StringBuffer();

      final cli = _create_cli(
        inspector: inspector,
        working_directory: directory,
        output: StringBuffer(),
        error_output: errors,
      );

      final status = await cli.run(['ls']);

      expect(
        status,
        RudraExitCode.inspection_incomplete.value,
      );

      expect(errors.toString(), contains('listDirectory'));
      expect(errors.toString(), contains('permissionDenied'));
      expect(inspector.inspected_paths, isEmpty);
    });

    test('rejects multiple directory arguments', () async {
      final inspector = _FakeTargetInspector();
      final diagnostics = StringBuffer();

      final sdk = RudraSdk(
        target_id: 'local-macos',
        inspector: inspector,
      );

      final cli = RudraCli(
        error_output: diagnostics,
      );

      cli.register_module(
        FilesystemCliModule(
          sdk: sdk,
          working_directory: TargetPath('/tmp'),
          output: StringBuffer(),
          error_output: StringBuffer(),
        ),
      );

      final status = await cli.run([
        'ls',
        '/tmp/first',
        '/tmp/second',
      ]);

      expect(status, RudraExitCode.invalid_usage.value);
      expect(diagnostics.isNotEmpty, isTrue);

      // Argument validation must happen before SDK invocation.
      expect(inspector.listed_directories, isEmpty);
      expect(inspector.inspected_paths, isEmpty);
    });

    test('preserves Windows-native directory paths', () async {
      final directory = TargetPath(
        r'C:\Users\example',
      );

      final entry = _create_entry(
        r'C:\Users\example\file.txt',
        FilesystemEntryKind.regularFile,
      );

      final inspector = _FakeTargetInspector(
        children: [entry.path],
        entries: {
          entry.path.value: entry,
        },
      );

      final output = StringBuffer();

      final cli = _create_cli(
        inspector: inspector,
        working_directory: directory,
        output: output,
        error_output: StringBuffer(),
        target_id: 'local-windows',
      );

      final status = await cli.run(['ls']);

      expect(status, RudraExitCode.success.value);

      expect(
        inspector.listed_directories.single.value,
        r'C:\Users\example',
      );

      expect(
        output.toString(),
        contains(r'C:\Users\example\file.txt'),
      );
    });

    test('propagates unexpected SDK failures', () async {
      final inspector = _FakeTargetInspector(
        unexpected_failure: StateError(
          'Unexpected inspection failure',
        ),
      );

      final cli = _create_cli(
        inspector: inspector,
        working_directory: TargetPath('/tmp'),
        output: StringBuffer(),
        error_output: StringBuffer(),
      );

      await expectLater(
        cli.run(['ls']),
        throwsA(isA<StateError>()),
      );
    });
  });
}

/// Creates an isolated CLI with an injected filesystem module.
///
/// This helper avoids platform-specific application composition.
///
/// The resulting CLI uses the same command registry as production.
RudraCli _create_cli({
  required TargetInspector inspector,
  required TargetPath working_directory,
  required StringBuffer output,
  required StringBuffer error_output,
  String target_id = 'local-macos',
}) {
  final sdk = RudraSdk(
    target_id: target_id,
    inspector: inspector,
  );

  final cli = RudraCli();

  cli.register_module(
    FilesystemCliModule(
      sdk: sdk,
      working_directory: working_directory,
      output: output,
      error_output: error_output,
    ),
  );

  return cli;
}

/// Creates an immutable filesystem entry for tests.
///
/// No filesystem access occurs.
FilesystemEntry _create_entry(
  String path,
  FilesystemEntryKind kind, {
  int? logical_size_bytes,
}) {
  return FilesystemEntry(
    path: TargetPath(path),
    kind: kind,
    metadata: FilesystemMetadata(
      logical_size_bytes: logical_size_bytes,
    ),
  );
}

/// Provides deterministic filesystem observations for CLI tests.
///
/// The fake implements Rudra's existing TargetInspector contract.
///
/// It records inspection calls and allows controlled failures.
/// No real filesystem operations are performed.
final class _FakeTargetInspector implements TargetInspector {
  /// Creates a configurable in-memory target inspector.
  ///
  /// [children] identifies paths produced by enumeration.
  ///
  /// [entries] contains corresponding filesystem observations.
  ///
  /// [inspection_failures] defines expected typed entry failures.
  ///
  /// [enumeration_failure] is emitted after configured children.
  ///
  /// [unexpected_failure] simulates an unclassified SDK failure.
  _FakeTargetInspector({
    List<TargetPath> children = const [],
    Map<String, FilesystemEntry> entries = const {},
    Map<String, TargetInspectionException> inspection_failures = const {},
    this.enumeration_failure,
    this.unexpected_failure,
  })  : _children = List<TargetPath>.unmodifiable(children),
        _entries = Map<String, FilesystemEntry>.unmodifiable(entries),
        _inspection_failures =
            Map<String, TargetInspectionException>.unmodifiable(
          inspection_failures,
        );

  /// Paths supplied by directory enumeration.
  final List<TargetPath> _children;

  /// Configured filesystem observations.
  final Map<String, FilesystemEntry> _entries;

  /// Configured typed inspection failures.
  final Map<String, TargetInspectionException> _inspection_failures;

  /// Optional directory enumeration failure.
  final TargetInspectionException? enumeration_failure;

  /// Optional unexpected failure.
  final Object? unexpected_failure;

  /// Recorded directory enumeration requests.
  final List<TargetPath> listed_directories = [];

  /// Recorded individual inspection requests.
  final List<TargetPath> inspected_paths = [];

  /// Number of symbolic-link destination reads.
  int symbolic_link_calls = 0;

  /// Enumerates immediate children without filesystem access.
  ///
  /// Injected errors are emitted through the stream.
  @override
  Stream<TargetPath> list_directory(TargetPath path) async* {
    listed_directories.add(path);

    if (unexpected_failure != null) {
      throw unexpected_failure!;
    }

    for (final child in _children) {
      yield child;
    }

    if (enumeration_failure != null) {
      throw enumeration_failure!;
    }
  }

  /// Inspects configured entries without native I/O.
  ///
  /// Unknown fixture paths produce an explicit StateError.
  @override
  Future<FilesystemEntry> inspect(TargetPath path) async {
    inspected_paths.add(path);

    final failure = _inspection_failures[path.value];

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

  /// Rejects unexpected capability requests.
  @override
  Future<TargetCapabilities> capabilities_for(
    TargetPath path,
  ) async {
    throw StateError(
      'Unexpected capabilities_for call: ${path.value}',
    );
  }

  /// Rejects unexpected symbolic-link destination requests.
  @override
  Future<TargetPath> read_symbolic_link(
    TargetPath path,
  ) async {
    symbolic_link_calls++;

    throw StateError(
      'Unexpected read_symbolic_link call: ${path.value}',
    );
  }
}
