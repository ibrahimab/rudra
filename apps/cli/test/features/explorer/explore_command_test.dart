import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:rudra_cli/rudra_cli.dart';
import 'package:rudra_cli/rudra_product_cli.dart';
import 'package:rudra_cli/src/features/explorer/cli/explorer_cli_composition.dart';
import 'package:rudra_cli/src/features/explorer/terminal/explorer_terminal_host.dart';
import 'package:rudra_cli/src/features/workflow/explorer/workflow_explorer_operation_exception.dart';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../../support/cli_host_fixture.dart';

/// Verifies Explorer command registration and production dispatch.
///
/// The tests exercise compose_product_cli() and the actual public SDK.
///
/// All filesystem and terminal operations are simulated.
/// No real filesystem content or terminal modes are modified.
void main() {
  test(
    'Explorer feature waits for verified state and borrows the SDK',
    () async {
      final fixture = _Fixture();
      final host = fixture.application_host;
      final sdk = host.composition();
      addTearDown(sdk.sdk.close);

      final state_read = host.hold_next_response();
      final cli = RudraCli()
        ..register_module(
          compose_explorer_cli(
            connect: sdk.connect,
            working_directory: sdk.working_directory,
            error_output: fixture.errors,
            create_terminal_host: () {
              fixture.host_creations++;
              return fixture.terminal;
            },
          ),
        );

      final invocation = cli.run(['explore']);
      try {
        await state_read.entered.timeout(const Duration(seconds: 5));
        expect(host.connect_count, 1);
        expect(fixture.host_creations, 0);
        expect(fixture.terminal.entered, isFalse);
      } finally {
        state_read.release();
      }

      expect(await invocation, RudraExitCode.success.value);
      expect(fixture.terminal.restored, isTrue);
      expect(sdk.sdk.is_connected, isTrue);
      expect(host.connect_count, 1);
    },
  );

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
        throwsA(
          isA<MessageSessionException>().having(
            (error) => error.code,
            'code',
            MessageSessionErrorCode.handler_failed,
          ),
        ),
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

    test('restores the same workflow after Q and a new invocation', () async {
      final directory = await Directory.systemTemp.createTemp(
        'rudra-explorer-workflow-test-',
      );

      addTearDown(() => directory.delete(recursive: true));

      final database = File('${directory.path}/rudra.sqlite');

      // Establish the workflow through the actual CLI action.
      final starter = _Fixture(
        children: {'/fixture': []},
        database_file: database,
      );
      final host = starter.application_host;

      expect(
        await starter.create_cli().run(['workflow', 'start']),
        RudraExitCode.success.value,
      );

      final original = await host.current();

      expect(original, isNotNull);

      // First Explorer invocation receives a fresh persisted read.
      final first = _Fixture(children: {'/fixture': []}, host: host);

      expect(
        await first.create_cli().run(['explore']),
        RudraExitCode.success.value,
      );

      final first_screen = first.terminal.output_buffer.toString();

      expect(first_screen, contains('Workflow: ACTIVE'));
      expect(first_screen, contains('ID: ${original!.identity.workflow_id}'));
      expect(first_screen, contains('Version: 1'));
      expect(first.terminal.restored, isTrue);
      expect(first.sdk!.resources_released, isTrue);

      // The fake terminal sends Q during each invocation.
      // A completely new CLI now restores the same database.
      final second = _Fixture(children: {'/fixture': []}, host: host);

      expect(
        await second.create_cli().run(['explore']),
        RudraExitCode.success.value,
      );

      final second_screen = second.terminal.output_buffer.toString();

      expect(second_screen, contains('Workflow: ACTIVE'));
      expect(second_screen, contains('ID: ${original.identity.workflow_id}'));
      expect(second_screen, contains('Version: 1'));
      expect(second.terminal.restored, isTrue);
      expect(second.sdk!.resources_released, isTrue);

      final restored = await host.current();

      expect(restored, isNotNull);
      expect(restored!.identity.workflow_id, original.identity.workflow_id);
      expect(restored.version, original.version);
      expect(restored.identity.root.value, original.identity.root.value);
    });

    test('opening Explorer without a workflow creates no database', () async {
      final directory = await Directory.systemTemp.createTemp(
        'rudra-explorer-read-only-test-',
      );

      addTearDown(() => directory.delete(recursive: true));

      final database_file = File('${directory.path}/rudra.sqlite');

      final fixture = _Fixture(
        children: {'/fixture': []},
        database_file: database_file,
      );

      expect(
        await fixture.create_cli().run(['explore']),
        RudraExitCode.success.value,
      );

      expect(database_file.existsSync(), isFalse);

      expect(
        fixture.terminal.output_buffer.toString(),
        contains('Workflow: NONE'),
      );

      expect(fixture.terminal.restored, isTrue);
    });

    test(
      'Start commits once and rejects a conflicting second request',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'rudra-explorer-start-key-',
        );

        addTearDown(() => directory.delete(recursive: true));

        final database_file = File('${directory.path}/rudra.sqlite');

        final database = database_file;

        // This is a fresh database, with no existing workflow.
        final first = _Fixture(
          children: {'/fixture': []},
          keys: 'sq',
          database_file: database,
        );
        final host = first.application_host;

        expect(database_file.existsSync(), isFalse);

        expect(
          await first.create_cli().run(['explore']),
          RudraExitCode.success.value,
        );

        // Pressing S must commit, not merely accept a submission.
        final committed = await host.current();

        expect(database_file.existsSync(), isTrue);
        expect(committed, isNotNull);
        expect(committed!.version, 1);
        expect(committed.identity.target_id, 'fixture-target');
        expect(committed.identity.root.value, '/fixture');

        final first_screen = first.terminal.output_buffer.toString();

        expect(first_screen, contains('Workflow: NONE'));
        expect(first_screen, contains('Workflow: ACTIVE'));
        expect(first_screen, contains('ID: ${committed.identity.workflow_id}'));
        expect(first.terminal.restored, isTrue);
        expect(first.sdk!.resources_released, isTrue);

        // Start an entirely new CLI invocation with the same
        // persistence location. S must not create a second workflow.
        final second = _Fixture(
          children: {'/fixture': []},
          keys: 'sq',
          host: host,
        );

        // The second explicit Start conflicts with the
        // workflow established by the first invocation.
        await expectLater(
          second.create_cli().run(['explore']),
          throwsA(
            isA<WorkflowExplorerOperationException>().having(
              (error) => error.outcome,
              'outcome',
              isA<WorkflowOperationResolved>().having(
                (outcome) => outcome.resolution.rejection_code,
                'rejection_code',
                WorkflowRejectionCode.ownership_conflict,
              ),
            ),
          ),
        );

        final second_screen = second.terminal.output_buffer.toString();

        expect(second_screen, contains('Workflow: ACTIVE'));
        expect(
          second_screen,
          contains('ID: ${committed.identity.workflow_id}'),
        );
        expect(second.terminal.restored, isTrue);
        expect(second.sdk!.resources_released, isTrue);

        final restored = await host.current();

        expect(restored, isNotNull);
        expect(restored!.identity.workflow_id, committed.identity.workflow_id);
        expect(restored.version, committed.version);
        expect(restored.identity.root.value, committed.identity.root.value);
      },
    );

    test('S starts the workflow at the currently opened directory', () async {
      final directory = await Directory.systemTemp.createTemp(
        'rudra-explorer-current-root-',
      );

      addTearDown(() => directory.delete(recursive: true));

      final database = File('${directory.path}/rudra.sqlite');

      final fixture = _Fixture(
        children: {
          '/fixture': ['/fixture/docs'],
          '/fixture/docs': [],
        },
        entries: {
          '/fixture/docs': _entry(
            '/fixture/docs',
            FilesystemEntryKind.directory,
          ),
        },
        // Enter directory, start workflow, then quit.
        keys: '\rsq',
        database_file: database,
      );
      final host = fixture.application_host;

      expect(
        await fixture.create_cli().run(['explore']),
        RudraExitCode.success.value,
      );

      final active = await host.current();

      expect(active, isNotNull);
      expect(active!.identity.root.value, '/fixture/docs');
      expect(
        fixture.terminal.output_buffer.toString(),
        contains('Directory: /fixture/docs'),
      );
      expect(fixture.terminal.restored, isTrue);
    });

    test('X durably stops the active workflow from Explorer', () async {
      final directory = await Directory.systemTemp.createTemp(
        'rudra-explorer-stop-key-',
      );

      addTearDown(() => directory.delete(recursive: true));

      final database_file = File('${directory.path}/rudra.sqlite');

      final database = database_file;

      // Establish the workflow through the normal CLI action.
      final starter = _Fixture(
        children: {'/fixture': []},
        database_file: database,
      );
      final host = starter.application_host;

      expect(
        await starter.create_cli().run(['workflow', 'start']),
        RudraExitCode.success.value,
      );

      final original = await host.current();

      expect(original, isNotNull);

      // Explorer restores the workflow and processes explicit X.
      final explorer = _Fixture(
        children: {'/fixture': []},
        keys: 'xq',
        host: host,
      );

      expect(
        await explorer.create_cli().run(['explore']),
        RudraExitCode.success.value,
      );

      final screen = explorer.terminal.output_buffer.toString();

      expect(screen, contains('Workflow: ACTIVE'));
      expect(screen, contains('ID: ${original!.identity.workflow_id}'));
      expect(screen, contains('X Stop Workflow'));
      expect(screen, contains('Workflow: NONE'));
      expect(screen, contains('S Start Workflow'));

      // The Stop is committed, not merely submitted.
      expect(await host.current(), isNull);
      expect(database_file.existsSync(), isTrue);
      expect(explorer.terminal.restored, isTrue);

      // A new Explorer invocation must remain read-only.
      final reopened = _Fixture(children: {'/fixture': []}, host: host);

      expect(
        await reopened.create_cli().run(['explore']),
        RudraExitCode.success.value,
      );

      expect(
        reopened.terminal.output_buffer.toString(),
        contains('Workflow: NONE'),
      );

      expect(await host.current(), isNull);
      expect(reopened.terminal.restored, isTrue);
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
    String keys = 'q',
    CliHostFixture? host,
    File? database_file,
  }) {
    inspector = _TestInspector(
      children: children,
      entries: entries,
      failures: failures,
      unexpected_directory: unexpected_directory,
    );

    terminal = _TestTerminalHost(interactive: interactive, keys: keys);
    application_host =
        host ??
        CliHostFixture(inspector: inspector, database_file: database_file);
  }

  /// In-memory target inspector.
  late final _TestInspector inspector;

  /// In-memory terminal host.
  late final _TestTerminalHost terminal;

  /// Existing noninteractive command output.
  final StringBuffer normal_output = StringBuffer();

  /// CLI diagnostics.
  final StringBuffer errors = StringBuffer();

  /// Authoritative host shared by the test frontends.
  late final CliHostFixture application_host;

  RudraSdk? sdk;

  /// Number of Explorer terminal host factory invocations.
  int host_creations = 0;

  /// Creates production CLI composition with injected dependencies.
  ///
  /// Construction does not inspect the filesystem or enter
  /// terminal mode.
  RudraCli create_cli() {
    final composition = application_host.composition();
    sdk = composition.sdk;
    return compose_product_cli(
      sdk_composition: composition,
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

  /// Fixture entries keyed by their target-native paths.
  final Map<String, FilesystemEntry> _entries;

  /// Injected inspection failures keyed by target path.
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
  _TestTerminalHost({required this.interactive, this.keys = 'q'});

  /// Whether interactive operation is supported.
  final bool interactive;

  /// Simulated explicit user keypresses.
  final String keys;

  /// Whether terminal interaction was entered.
  bool entered = false;

  /// Whether the interaction's cleanup path completed.
  bool restored = false;

  /// Captures Explorer terminal presentation.
  final StringBuffer output_buffer = StringBuffer();

  /// Tracks whether the fake terminal host is active.
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

    return Stream<List<int>>.fromIterable([ascii.encode(keys)]);
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
