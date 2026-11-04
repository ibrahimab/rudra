import 'dart:io';

import 'package:rudra_cli/rudra_cli.dart';
import 'package:rudra_cli/src/composition/product_sdk_composition.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies production SDK and CLI application composition.
///
/// Unit tests inject a deterministic TargetInspector through
/// the public Rudra SDK.
///
/// The macOS integration test exercises the real native adapter
/// using an isolated temporary filesystem fixture.
///
/// Rudra itself performs only read-only inspection operations.
void main() {
  group('ProductSdkComposition', () {
    test('selects only a supported local target adapter', () {
      final composition = ProductSdkComposition.for_current_host();

      if (Platform.isMacOS) {
        expect(composition, isNotNull);

        expect(
          composition!.sdk.target_id,
          'local-macos',
        );

        expect(
          composition.working_directory.value,
          Directory.current.absolute.path,
        );
      } else {
        expect(composition, isNull);
      }
    });

    test('registers SDK-backed commands with injected composition', () {
      final inspector = _RecordingInspector();

      final composition = ProductSdkComposition(
        sdk: RudraSdk(
          target_id: 'test-target',
          inspector: inspector,
        ),
        working_directory: TargetPath('/fixture'),
      );

      final cli = RudraCli.product(
        target_composition: composition,
      );

      expect(
        cli.command_names,
        containsAll(['about', 'ls']),
      );

      expect(
        cli.module_ids,
        containsAll([
          'rudra.product.about',
          'rudra.product.filesystem',
        ]),
      );

      // Application composition must not inspect anything.
      expect(inspector.listed_directories, isEmpty);
      expect(inspector.inspected_paths, isEmpty);
    });

    test('executes ls through the injected SDK', () async {
      final directory = TargetPath('/fixture');

      final file = FilesystemEntry(
        path: TargetPath('/fixture/example.txt'),
        kind: FilesystemEntryKind.regularFile,
        metadata: FilesystemMetadata(
          logical_size_bytes: 2048,
        ),
      );

      final inspector = _RecordingInspector(
        children: [file.path],
        entries: {
          file.path.value: file,
        },
      );

      final composition = ProductSdkComposition(
        sdk: RudraSdk(
          target_id: 'test-target',
          inspector: inspector,
        ),
        working_directory: directory,
      );

      final output = StringBuffer();
      final errors = StringBuffer();

      final cli = RudraCli.product(
        target_composition: composition,
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
        [same(file.path)],
      );

      expect(
        output.toString(),
        contains(RegExp(r'regularFile +2048 +/fixture/example\.txt')),
      );

      expect(errors.toString(), isEmpty);
    });

    test('preserves existing product command registration', () {
      final composition = ProductSdkComposition(
        sdk: RudraSdk(
          target_id: 'test-target',
          inspector: _RecordingInspector(),
        ),
        working_directory: TargetPath('/fixture'),
      );

      final cli = RudraCli.product(
        target_composition: composition,
      );

      expect(cli.command_names, contains('about'));
      expect(cli.command_names, contains('ls'));

      // Development commands must remain excluded.
      for (final name in [
        'check',
        'test',
        'format',
        'analyze',
        'build',
      ]) {
        expect(
          cli.command_names,
          isNot(contains(name)),
        );
      }
    });
  });

  group('Native production composition', () {
    test(
      'lists a real macOS directory through the SDK',
      () async {
        final fixture = await Directory.systemTemp.createTemp(
          'rudra-product-test-',
        );

        try {
          final file = File('${fixture.path}/example.txt');

          await file.writeAsString('rudra');

          final output = StringBuffer();
          final errors = StringBuffer();

          // No fake adapter is injected here.
          //
          // This uses the exact production composition that
          // the CLI executable uses on macOS.
          final cli = RudraCli.product(
            output: output,
            error_output: errors,
          );

          final status = await cli.run([
            'ls',
            fixture.path,
          ]);

          expect(status, RudraExitCode.success.value);

          expect(
            output.toString(),
            contains(RegExp('regularFile +5 +${RegExp.escape(file.path)}')),
          );

          expect(errors.toString(), isEmpty);
        } finally {
          // Test infrastructure removes its own fixture.
          // Rudra does not perform this deletion.
          await fixture.delete(recursive: true);
        }
      },
      skip: !Platform.isMacOS
          ? 'Native production adapter currently requires macOS.'
          : false,
    );
  });
}

/// Records filesystem inspection operations for composition tests.
///
/// All observations are supplied in memory.
///
/// This fake implements the established TargetInspector contract.
/// It does not perform native filesystem I/O.
final class _RecordingInspector implements TargetInspector {
  /// Creates a deterministic inspection fixture.
  ///
  /// [children] supplies paths discovered during enumeration.
  ///
  /// [entries] supplies inspected filesystem entries.
  _RecordingInspector({
    List<TargetPath> children = const [],
    Map<String, FilesystemEntry> entries = const {},
  })  : _children = List<TargetPath>.unmodifiable(children),
        _entries = Map<String, FilesystemEntry>.unmodifiable(entries);

  /// Immediate children exposed by directory enumeration.
  final List<TargetPath> _children;

  /// Configured observations indexed by target-native path.
  final Map<String, FilesystemEntry> _entries;

  /// Records requested directory paths.
  final List<TargetPath> listed_directories = [];

  /// Records individual entry inspection requests.
  final List<TargetPath> inspected_paths = [];

  /// Enumerates configured immediate children.
  ///
  /// Enumeration is lazy and performs no real filesystem I/O.
  @override
  Stream<TargetPath> list_directory(TargetPath path) async* {
    listed_directories.add(path);

    for (final child in _children) {
      yield child;
    }
  }

  /// Inspects a configured filesystem entry.
  ///
  /// Unexpected paths produce a failure rather than fabricated
  /// metadata or a misleading successful observation.
  @override
  Future<FilesystemEntry> inspect(TargetPath path) async {
    inspected_paths.add(path);

    final entry = _entries[path.value];

    if (entry == null) {
      throw StateError(
        'No test entry configured for ${path.value}',
      );
    }

    return entry;
  }

  /// Rejects unexpected capability discovery.
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
    throw StateError(
      'Unexpected read_symbolic_link call: ${path.value}',
    );
  }
}
