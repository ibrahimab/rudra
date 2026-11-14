import 'dart:async';

import 'package:rudra_cli/rudra_cli.dart';
import 'package:rudra_cli/src/composition/product_sdk_composition.dart';
import 'package:rudra_cli/src/features/explorer/terminal/explorer_terminal_host.dart';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies Explorer command registration and production dispatch.
///
/// The tests exercise RudraCli.product() and the actual public SDK.
///
/// All filesystem and terminal operations are simulated.
/// No real filesystem content or terminal modes are modified.
void main() {
  group('ExploreCommand production integration', () {
    test('registers Explorer without constructing a terminal', () {
      final fixture = _Fixture();
      final cli = fixture.create_cli();

      expect(cli.command_names, containsAll(['about', 'ls', 'explore']));

      expect(
        cli.module_ids,
        containsAll([
          'rudra.product.about',
          'rudra.product.filesystem',
          'rudra.product.explorer',
        ]),
      );

      expect(fixture.host_creations, 0);
      expect(fixture.inspector.listed, isEmpty);
      expect(fixture.terminal.entered, isFalse);
    });

    test('explores the configured default directory', () async {
      final fixture = _Fixture(
        children: {
          '/fixture': ['/fixture/docs'],
        },
        entries: {
          '/fixture/docs': _entry(
            '/fixture/docs',
            FilesystemEntryKind.directory,
          ),
        },
      );

      final status = await fixture.create_cli().run(['explore']);

      expect(status, RudraExitCode.success.value);
      expect(fixture.host_creations, 1);
      expect(fixture.inspector.listed, ['/fixture']);
      expect(fixture.inspector.inspected, ['/fixture/docs']);

      expect(
        fixture.terminal.output_buffer.toString(),
        contains('Directory: /fixture'),
      );

      expect(fixture.terminal.output_buffer.toString(), contains('docs/'));

      expect(fixture.terminal.entered, isTrue);
      expect(fixture.terminal.restored, isTrue);
      expect(fixture.inspector.link_reads, 0);
    });

    test('accepts an explicit starting directory', () async {
      final fixture = _Fixture(children: {'/another/directory': []});

      final status = await fixture.create_cli().run([
        'explore',
        '/another/directory',
      ]);

      expect(status, RudraExitCode.success.value);

      expect(fixture.inspector.listed, ['/another/directory']);

      expect(
        fixture.terminal.output_buffer.toString(),
        contains('Directory: /another/directory'),
      );
    });

    test('rejects multiple directory arguments', () async {
      final fixture = _Fixture();

      final status = await fixture.create_cli().run([
        'explore',
        '/first',
        '/second',
      ]);

      expect(status, RudraExitCode.invalid_usage.value);

      expect(
        fixture.errors.toString(),
        contains('Expected at most one directory argument'),
      );

      expect(fixture.host_creations, 0);
      expect(fixture.inspector.listed, isEmpty);
    });

    test('rejects an empty explicit directory', () async {
      final fixture = _Fixture();

      final status = await fixture.create_cli().run(['explore', '']);

      expect(status, RudraExitCode.invalid_usage.value);
      expect(fixture.host_creations, 0);
      expect(fixture.inspector.listed, isEmpty);
    });

    test('rejects invalid target path construction', () async {
      final fixture = _Fixture();

      final status = await fixture.create_cli().run([
        'explore',
        '/invalid\u0000path',
      ]);

      expect(status, RudraExitCode.invalid_usage.value);
      expect(fixture.host_creations, 0);
      expect(fixture.inspector.listed, isEmpty);
    });

    test('rejects noninteractive terminals before inspection', () async {
      final fixture = _Fixture(interactive: false);

      final status = await fixture.create_cli().run(['explore']);

      expect(status, RudraExitCode.configuration_error.value);

      expect(fixture.inspector.listed, isEmpty);
      expect(fixture.terminal.entered, isFalse);

      expect(
        fixture.errors.toString(),
        contains('Interactive Explorer requires'),
      );
    });

    test('preserves incomplete inspection exit status', () async {
      final blocked = TargetPath('/fixture/blocked');

      final fixture = _Fixture(
        children: {
          '/fixture': [blocked.value],
        },
        failures: {
          blocked.value: TargetInspectionException(
            code: TargetInspectionErrorCode.permissionDenied,
            operation: TargetInspectionOperation.inspect,
            path: blocked,
            message: 'Permission denied.',
          ),
        },
      );

      final status = await fixture.create_cli().run(['explore']);

      expect(status, RudraExitCode.inspection_incomplete.value);

      expect(fixture.terminal.output_buffer.toString(), contains('WARNING'));

      expect(fixture.terminal.restored, isTrue);
    });

    test('propagates unexpected SDK errors before terminal entry', () async {
      final fixture = _Fixture(unexpected_directory: '/fixture');

      await expectLater(
        fixture.create_cli().run(['explore']),
        throwsStateError,
      );

      expect(fixture.inspector.listed, ['/fixture']);
      expect(fixture.terminal.entered, isFalse);
    });

    test('preserves the existing no-argument welcome workflow', () async {
      final fixture = _Fixture(children: {'/fixture': []});

      final status = await fixture.create_cli().run([]);

      expect(status, RudraExitCode.success.value);
      expect(fixture.inspector.listed, ['/fixture']);

      expect(fixture.normal_output.toString(), contains('RUDRA  |  READ ONLY'));

      expect(fixture.host_creations, 0);
    });

    test('preserves the existing compact ls output', () async {
      final fixture = _Fixture(
        children: {
          '/fixture': ['/fixture/readme.txt'],
        },
        entries: {
          '/fixture/readme.txt': _entry(
            '/fixture/readme.txt',
            FilesystemEntryKind.regularFile,
          ),
        },
      );

      final status = await fixture.create_cli().run(['ls']);

      expect(status, RudraExitCode.success.value);

      expect(fixture.normal_output.toString(), contains('TYPE'));

      expect(fixture.normal_output.toString(), contains('LOGICAL_BYTES'));

      expect(fixture.normal_output.toString(), contains('/fixture/readme.txt'));

      expect(fixture.host_creations, 0);
    });
  });
}

/// Composes a deterministic production CLI test scenario.
///
/// ProductSdkComposition receives a real RudraSdk using an
/// in-memory implementation of the TargetInspector contract.
///
/// Explorer terminal hosting is injected separately.
final class _Fixture {
  /// Creates a fixture with configurable filesystem observations.
  _Fixture({
    Map<String, List<String>> children = const {},
    Map<String, FilesystemEntry> entries = const {},
    Map<String, TargetInspectionException> failures = const {},
    String? unexpected_directory,
    bool interactive = true,
  }) {
    inspector = _TestInspector(
      children: children,
      entries: entries,
      failures: failures,
      unexpected_directory: unexpected_directory,
    );

    terminal = _TestTerminalHost(interactive: interactive);
  }

  /// In-memory target inspector.
  late final _TestInspector inspector;

  /// In-memory terminal host.
  late final _TestTerminalHost terminal;

  /// Existing noninteractive command output.
  final StringBuffer normal_output = StringBuffer();

  /// CLI diagnostics.
  final StringBuffer errors = StringBuffer();

  /// Number of Explorer terminal host factory invocations.
  int host_creations = 0;

  /// Creates production CLI composition with injected dependencies.
  ///
  /// Construction does not inspect the filesystem or enter
  /// terminal mode.
  RudraCli create_cli() {
    return RudraCli.product(
      target_composition: ProductSdkComposition(
        sdk: RudraSdk(target_id: 'fixture-target', inspector: inspector),
        working_directory: TargetPath('/fixture'),
      ),
      output: normal_output,
      error_output: errors,
      explorer_terminal_host_factory: () {
        host_creations++;
        return terminal;
      },
    );
  }
}

/// Provides read-only filesystem observations in memory.
///
/// Only the methods required by TargetInspector are implemented.
/// Unsupported operations throw rather than fabricate results.
final class _TestInspector implements TargetInspector {
  /// Creates a deterministic inspection fixture.
  _TestInspector({
    required Map<String, List<String>> children,
    required Map<String, FilesystemEntry> entries,
    required Map<String, TargetInspectionException> failures,
    required this.unexpected_directory,
  }) : _children = children,
       _entries = entries,
       _failures = failures;

  final Map<String, List<String>> _children;
  final Map<String, FilesystemEntry> _entries;
  final Map<String, TargetInspectionException> _failures;

  /// Directory for which enumeration should throw unexpectedly.
  final String? unexpected_directory;

  /// Recorded directory listing requests.
  final List<String> listed = [];

  /// Recorded entry inspection requests.
  final List<String> inspected = [];

  /// Number of symbolic-link resolution requests.
  int link_reads = 0;

  /// Enumerates configured immediate children.
  @override
  Stream<TargetPath> list_directory(TargetPath path) async* {
    listed.add(path.value);

    if (path.value == unexpected_directory) {
      throw StateError('Injected SDK enumeration failure.');
    }

    for (final child in _children[path.value] ?? const <String>[]) {
      yield TargetPath(child);
    }
  }

  /// Returns configured entries or propagates typed failures.
  @override
  Future<FilesystemEntry> inspect(TargetPath path) async {
    inspected.add(path.value);

    final failure = _failures[path.value];

    if (failure != null) {
      throw failure;
    }

    final entry = _entries[path.value];

    if (entry == null) {
      throw StateError('Unexpected inspection: ${path.value}');
    }

    return entry;
  }

  /// Rejects unnecessary capability discovery.
  @override
  Future<TargetCapabilities> capabilities_for(TargetPath path) async {
    throw StateError('Unexpected capability request.');
  }

  /// Rejects symbolic-link destination resolution.
  @override
  Future<TargetPath> read_symbolic_link(TargetPath path) async {
    link_reads++;
    throw StateError('Unexpected symbolic-link resolution.');
  }
}

/// Simulates one guarded interactive terminal lifecycle.
///
/// Its output buffer receives actual BareExplorerRenderer frames.
///
/// Input contains one Q key, allowing the real ExplorerRunner
/// to terminate through its normal navigation workflow.
final class _TestTerminalHost implements ExplorerTerminalHost {
  /// Creates a deterministic terminal host.
  _TestTerminalHost({required this.interactive});

  /// Whether interactive operation is supported.
  final bool interactive;

  /// Whether terminal interaction was entered.
  bool entered = false;

  /// Whether the interaction's cleanup path completed.
  bool restored = false;

  /// Captures Explorer terminal presentation.
  final StringBuffer output_buffer = StringBuffer();

  bool _active = false;

  @override
  bool get is_interactive => interactive;

  @override
  int get terminal_columns => 100;

  @override
  int get terminal_rows => 24;

  @override
  StringSink get output => output_buffer;

  /// Supplies a controlled quit event during an interaction.
  @override
  Stream<List<int>> get input_bytes {
    if (!_active) {
      throw StateError('No active terminal interaction.');
    }

    return Stream<List<int>>.fromIterable(const [
      [0x71],
    ]);
  }

  /// Runs the interaction and guarantees restoration signaling.
  @override
  Future<T> run_interactive<T>(Future<T> Function() interaction) async {
    if (!interactive || _active) {
      throw StateError('Terminal interaction unavailable.');
    }

    entered = true;
    _active = true;

    try {
      return await interaction();
    } finally {
      restored = true;
      _active = false;
    }
  }
}

/// Creates one immutable filesystem observation.
///
/// No native filesystem inspection is performed.
FilesystemEntry _entry(String path, FilesystemEntryKind kind) {
  return FilesystemEntry(
    path: TargetPath(path),
    kind: kind,
    metadata: FilesystemMetadata(),
  );
}
