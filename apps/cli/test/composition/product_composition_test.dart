import 'dart:io';

import 'package:rudra_cli/rudra_cli.dart';
import 'package:rudra_cli/src/composition/product_sdk_composition.dart';
import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_target_macos/rudra_target_macos.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../support/cli_host_fixture.dart';

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
    test('selects the local target and defers native connectivity', () {
      final composition = ProductSdkComposition.for_current_host();

      expect(composition.sdk.target_id, local_macos_target_id);
      expect(
        composition.working_directory.value,
        Directory.current.absolute.path,
      );
      expect(composition.connection_params.transport, isNull);
      expect(composition.sdk.is_connected, isFalse);
      expect(composition.sdk.resources_released, isTrue);
    });

    test('registers SDK-backed commands with injected composition', () {
      final inspector = _RecordingInspector();

      final composition = CliHostFixture(inspector: inspector)
          .composition(directory: TargetPath('/fixture'));

      final cli = RudraCli.product(target_composition: composition);

      expect(cli.command_names, containsAll(['about', 'ls']));

      expect(
        cli.module_ids,
        containsAll(['rudra.product.about', 'rudra.product.filesystem']),
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
        metadata: FilesystemMetadata(logical_size_bytes: 2048),
      );

      final inspector = _RecordingInspector(
        children: [file.path],
        entries: {file.path.value: file},
      );

      final composition = CliHostFixture(inspector: inspector)
          .composition(directory: directory);

      final output = StringBuffer();
      final errors = StringBuffer();

      final cli = RudraCli.product(
        target_composition: composition,
        output: output,
        error_output: errors,
      );

      final status = await cli.run(['ls']);

      expect(status, RudraExitCode.success.value);

      expect(inspector.listed_directories.map((path) => path.value), [
        directory.value,
      ]);

      expect(inspector.inspected_paths.map((path) => path.value), [
        file.path.value,
      ]);

      expect(
        output.toString(),
        contains(RegExp(r'regularFile +2048 +/fixture/example\.txt')),
      );

      expect(errors.toString(), isEmpty);
      expect(composition.sdk.resources_released, isTrue);
    });

    test('preserves existing product command registration', () {
      final composition = CliHostFixture(inspector: _RecordingInspector())
          .composition();

      final cli = RudraCli.product(target_composition: composition);

      expect(cli.command_names, contains('about'));
      expect(cli.command_names, contains('ls'));

      // Development commands must remain excluded.
      for (final name in ['check', 'test', 'format', 'analyze', 'build']) {
        expect(cli.command_names, isNot(contains(name)));
      }
    });
  });

  test(
    'host connection is deferred until an operational command validates',
    () async {
      final transport = _UnavailableTransport();

      for (final arguments in [
        ['--help'],
        ['about'],
        ['ls', '/first', '/second'],
        ['explore', ''],
        ['workflow', 'start', 'relative'],
        ['workflow', 'stop', 'unexpected'],
        ['host', 'start'],
      ]) {
        final composition = ProductSdkComposition(
          sdk: RudraSdk(),
          working_directory: TargetPath('/fixture'),
          connection_params: ConnectionParams(transport: transport),
        );
        await RudraCli.product(
          target_composition: composition,
          output: StringBuffer(),
          error_output: StringBuffer(),
        ).run(arguments);
        expect(composition.sdk.resources_released, isTrue);
      }
      expect(transport.attempts, 0);
    },
  );

  test('unavailable host is explicit for every operational command', () async {
    final transport = _UnavailableTransport();

    for (final arguments in <List<String>>[
      [],
      ['ls'],
      ['explore'],
      ['workflow', 'start'],
      ['workflow', 'stop'],
    ]) {
      final output = StringBuffer();
      final errors = StringBuffer();
      final composition = ProductSdkComposition(
        sdk: RudraSdk(),
        working_directory: TargetPath('/fixture'),
        connection_params: ConnectionParams(transport: transport),
      );

      final status = await RudraCli.product(
        target_composition: composition,
        output: output,
        error_output: errors,
        explorer_terminal_host_factory: () =>
            fail('Unavailable host must not open a terminal.'),
      ).run(arguments);

      expect(status, RudraExitCode.host_unavailable.value);
      expect(errors.toString(), contains('Rudra Host unavailable'));
      expect(output.toString(), isEmpty);
      expect(composition.sdk.resources_released, isTrue);
      await expectLater(composition.sdk.connect(), throwsStateError);
    }
    expect(transport.attempts, 5);
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

          final host = CliHostFixture(inspector: MacOsTargetInspector());
          final cli = RudraCli.product(
            target_composition: host.composition(),
            output: output,
            error_output: errors,
          );

          final status = await cli.run(['ls', fixture.path]);

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
  }) : _children = List<TargetPath>.unmodifiable(children),
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
      throw StateError('No test entry configured for ${path.value}');
    }

    return entry;
  }

  /// Rejects unexpected capability discovery.
  @override
  Future<TargetCapabilities> capabilities_for(TargetPath path) async {
    throw StateError('Unexpected capabilities_for call: ${path.value}');
  }

  /// Rejects unexpected symbolic-link destination requests.
  @override
  Future<TargetPath> read_symbolic_link(TargetPath path) async {
    throw StateError('Unexpected read_symbolic_link call: ${path.value}');
  }
}

final class _UnavailableTransport implements Transport {
  int attempts = 0;

  @override
  Future<TransportConnection> connect() async {
    attempts++;
    throw StateError('Fixture host is unavailable.');
  }

  @override
  Future<TransportListener> listen() async =>
      fail('Expected a client invocation.');
}
