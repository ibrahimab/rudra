import 'dart:async';
import 'dart:convert';

import 'package:rudra_cli/rudra_cli.dart';
import 'package:rudra_cli/src/core/rendering/renderer.dart';
import 'package:rudra_cli/src/features/explorer/dart_explorer_terminal_host.dart';
import 'package:rudra_cli/src/features/explorer/explorer_controller.dart';
import 'package:rudra_cli/src/features/explorer/explorer_runner.dart';
import 'package:rudra_cli/src/features/explorer/explorer_terminal_device.dart';
import 'package:rudra_cli/src/features/explorer/explorer_terminal_host.dart';
import 'package:rudra_cli/src/features/explorer/explorer_view_model.dart';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies interactive Explorer orchestration.
///
/// Tests use the real SDK and ExplorerController with an
/// in-memory TargetInspector implementation.
///
/// Terminal input, rendering, and lifecycle are injected.
///
/// No native filesystem content or terminal settings are changed.
void main() {
  group('ExplorerRunner', () {
    test('starts, renders, quits, and closes navigation', () async {
      final scenario = _Scenario(
        children: {
          '/root': ['/root/docs'],
        },
        entries: [
          _entry('/root/docs', FilesystemEntryKind.directory),
        ],
        keys: 'q',
      );

      final status = await scenario.runner.run();

      expect(status, RudraExitCode.success.value);
      expect(scenario.inspector.listed, ['/root']);
      expect(scenario.renderer.frames, hasLength(1));

      expect(
        scenario.renderer.frames.single.current_directory,
        '/root',
      );

      expect(
        scenario.renderer.frames.single.visible_rows.single.name,
        'docs/',
      );

      expect(scenario.controller.model?.is_closed, isTrue);
      expect(scenario.terminal.restored, isTrue);
    });

    test('moves selection without additional SDK requests', () async {
      final scenario = _Scenario(
        children: {
          '/root': ['/root/a.txt', '/root/b.txt'],
        },
        entries: [
          _entry('/root/a.txt', FilesystemEntryKind.regularFile),
          _entry('/root/b.txt', FilesystemEntryKind.regularFile),
        ],
        keys: '\x1B[B\x1B[Aq',
      );

      final status = await scenario.runner.run();

      expect(status, RudraExitCode.success.value);
      expect(scenario.inspector.listed, ['/root']);

      expect(
        scenario.renderer.frames.map(
          (frame) => frame.selected_index,
        ),
        orderedEquals([0, 1, 0]),
      );

      expect(
        scenario.inspector.inspected,
        hasLength(2),
      );
    });

    test('enters directories and navigates back', () async {
      final scenario = _Scenario(
        children: {
          '/root': ['/root/docs'],
          '/root/docs': ['/root/docs/readme.md'],
        },
        entries: [
          _entry('/root/docs', FilesystemEntryKind.directory),
          _entry(
            '/root/docs/readme.md',
            FilesystemEntryKind.regularFile,
          ),
        ],
        keys: '\r\x1B[Dq',
      );

      final status = await scenario.runner.run();

      expect(status, RudraExitCode.success.value);

      expect(
        scenario.inspector.listed,
        orderedEquals([
          '/root',
          '/root/docs',
          '/root',
        ]),
      );

      expect(
        scenario.renderer.frames.map(
          (frame) => frame.current_directory,
        ),
        orderedEquals([
          '/root',
          '/root/docs',
          '/root',
        ]),
      );

      expect(
        scenario.renderer.frames.map(
          (frame) => frame.can_go_back,
        ),
        orderedEquals([false, true, false]),
      );
    });

    test('does not navigate into files or symbolic links', () async {
      final scenario = _Scenario(
        children: {
          '/root': ['/root/a.txt', '/root/link'],
        },
        entries: [
          _entry('/root/a.txt', FilesystemEntryKind.regularFile),
          _entry('/root/link', FilesystemEntryKind.symbolicLink),
        ],
        keys: '\r\x1B[B\rq',
      );

      final status = await scenario.runner.run();

      expect(status, RudraExitCode.success.value);
      expect(scenario.inspector.listed, ['/root']);
      expect(scenario.inspector.link_reads, 0);
      expect(scenario.inspector.capability_reads, 0);

      expect(
        scenario.renderer.frames.map(
          (frame) => frame.current_directory,
        ),
        everyElement('/root'),
      );

      // Only moving the selection requires a redraw.
      expect(scenario.renderer.frames, hasLength(2));
    });

    test('tracks incomplete inspection across navigation', () async {
      final blocked_path = TargetPath('/root/blocked');

      final scenario = _Scenario(
        children: {
          '/root': ['/root/docs', blocked_path.value],
          '/root/docs': [],
        },
        entries: [
          _entry('/root/docs', FilesystemEntryKind.directory),
        ],
        failures: {
          blocked_path.value: TargetInspectionException(
            code: TargetInspectionErrorCode.permissionDenied,
            operation: TargetInspectionOperation.inspect,
            path: blocked_path,
            message: 'Permission denied.',
          ),
        },
        keys: '\rq',
      );

      final status = await scenario.runner.run();

      expect(
        status,
        RudraExitCode.inspection_incomplete.value,
      );

      expect(scenario.renderer.frames.first.is_incomplete, isTrue);
      expect(scenario.renderer.frames.first.issues, hasLength(1));

      // The child inspection succeeds, but the earlier
      // incomplete observation remains relevant to the exit.
      expect(scenario.renderer.frames.last.is_complete, isTrue);
      expect(scenario.inspector.listed, ['/root', '/root/docs']);
    });

    test('tracks incomplete inspection discovered in a child', () async {
      final blocked_path = TargetPath('/root/docs/blocked');

      final scenario = _Scenario(
        children: {
          '/root': ['/root/docs'],
          '/root/docs': [blocked_path.value],
        },
        entries: [
          _entry('/root/docs', FilesystemEntryKind.directory),
        ],
        failures: {
          blocked_path.value: TargetInspectionException(
            code: TargetInspectionErrorCode.permissionDenied,
            operation: TargetInspectionOperation.inspect,
            path: blocked_path,
            message: 'Permission denied.',
          ),
        },
        keys: '\r\x1B[Dq',
      );

      final status = await scenario.runner.run();

      expect(status, RudraExitCode.inspection_incomplete.value);

      expect(
        scenario.renderer.frames.map(
          (frame) => frame.is_incomplete,
        ),
        orderedEquals([false, true, false]),
      );
    });

    test('handles empty directories and input EOF', () async {
      final scenario = _Scenario(
        children: {'/root': []},
        entries: [],
        source: const Stream<List<int>>.empty(),
      );

      final status = await scenario.runner.run();

      expect(status, RudraExitCode.success.value);
      expect(scenario.renderer.frames.single.is_empty, isTrue);
      expect(
        scenario.renderer.frames.single.selected_index,
        isNull,
      );

      expect(scenario.controller.model?.is_closed, isTrue);
      expect(scenario.terminal.restored, isTrue);
    });

    test('scrolls the viewport as selection moves', () async {
      final paths = [
        for (final name in ['a', 'b', 'c', 'd', 'e']) '/root/$name.txt',
      ];

      final scenario = _Scenario(
        children: {'/root': paths},
        entries: [
          for (final path in paths)
            _entry(path, FilesystemEntryKind.regularFile),
        ],
        keys: '\x1B[B\x1B[B\x1B[Bq',
        rows: 9,
      );

      await scenario.runner.run();

      final first = scenario.renderer.frames.first;
      final last = scenario.renderer.frames.last;

      expect(first.visible_row_limit, 2);
      expect(first.first_visible_index, 0);
      expect(first.selected_visible_index, 0);

      expect(last.selected_index, 3);
      expect(last.first_visible_index, 2);
      expect(last.selected_visible_index, 1);

      expect(
        last.visible_rows.map((row) => row.name),
        orderedEquals(['c.txt', 'd.txt']),
      );

      expect(last.has_hidden_above, isTrue);
      expect(last.has_hidden_below, isTrue);
    });

    test('adapts viewport dimensions on the next render', () async {
      final scenario = _Scenario(
        children: {
          '/root': ['/root/a.txt', '/root/b.txt'],
        },
        entries: [
          _entry('/root/a.txt', FilesystemEntryKind.regularFile),
          _entry('/root/b.txt', FilesystemEntryKind.regularFile),
        ],
        keys: '\x1B[Bq',
        rows: 9,
      );

      scenario.renderer.on_render = (_) {
        if (scenario.renderer.frames.length == 1) {
          scenario.terminal.rows = 11;
        }
      };

      await scenario.runner.run();

      expect(
        scenario.renderer.frames.map(
          (frame) => frame.visible_row_limit,
        ),
        orderedEquals([2, 4]),
      );
    });

    test('permits a zero-height entry viewport', () async {
      final scenario = _Scenario(
        children: {
          '/root': ['/root/a.txt'],
        },
        entries: [
          _entry('/root/a.txt', FilesystemEntryKind.regularFile),
        ],
        keys: 'q',
        rows: 7,
      );

      expect(
        await scenario.runner.run(),
        RudraExitCode.success.value,
      );

      final frame = scenario.renderer.frames.single;

      expect(frame.visible_row_limit, 0);
      expect(frame.visible_rows, isEmpty);
      expect(frame.observed_count, 1);
    });

    test('rejects unsupported terminals without inspection', () async {
      final scenario = _Scenario(
        children: {'/root': []},
        entries: [],
      );

      scenario.terminal.interactive = false;

      final status = await scenario.runner.run();

      expect(status, RudraExitCode.configuration_error.value);
      expect(scenario.inspector.listed, isEmpty);
      expect(scenario.terminal.invocations, 0);
      expect(scenario.errors.toString(), contains('terminal'));
    });

    test('rejects initially undersized terminals', () async {
      final scenario = _Scenario(
        children: {'/root': []},
        entries: [],
        rows: 6,
      );

      final status = await scenario.runner.run();

      expect(status, RudraExitCode.configuration_error.value);
      expect(scenario.inspector.listed, isEmpty);
      expect(scenario.terminal.invocations, 0);
    });

    test('does not enter terminal mode when startup fails', () async {
      final scenario = _Scenario(
        children: {'/root': []},
        entries: [],
      );

      scenario.inspector.unexpected_directory = '/root';

      await expectLater(
        scenario.runner.run(),
        throwsStateError,
      );

      expect(scenario.terminal.invocations, 0);
      expect(scenario.controller.model, isNull);
    });

    test('restores terminal after navigation failure', () async {
      final scenario = _Scenario(
        children: {
          '/root': ['/root/docs'],
          '/root/docs': [],
        },
        entries: [
          _entry('/root/docs', FilesystemEntryKind.directory),
        ],
        keys: '\r',
      );

      scenario.inspector.unexpected_directory = '/root/docs';

      await expectLater(
        scenario.runner.run(),
        throwsStateError,
      );

      expect(scenario.terminal.restored, isTrue);
      expect(scenario.controller.model?.current_directory.value, '/root');
      expect(scenario.controller.model?.is_closed, isTrue);
    });

    test('restores terminal after rendering failure', () async {
      final scenario = _Scenario(
        children: {'/root': []},
        entries: [],
      );

      scenario.renderer.fail_render = true;

      await expectLater(
        scenario.runner.run(),
        throwsStateError,
      );

      expect(scenario.terminal.restored, isTrue);
      expect(scenario.controller.model?.is_closed, isTrue);
    });

    test('propagates input errors after restoration', () async {
      final scenario = _Scenario(
        children: {'/root': []},
        entries: [],
        source: Stream<List<int>>.error(
          StateError('Injected input failure.'),
        ),
      );

      await expectLater(
        scenario.runner.run(),
        throwsStateError,
      );

      expect(scenario.terminal.restored, isTrue);
      expect(scenario.controller.model?.is_closed, isTrue);
    });

    test('does not convert signal interruption into success', () async {
      final scenario = _Scenario(
        children: {'/root': []},
        entries: [],
        source: Stream<List<int>>.error(
          const ExplorerTerminalInterrupted(
            ExplorerTerminalSignal.terminate,
          ),
        ),
      );

      await expectLater(
        scenario.runner.run(),
        throwsA(isA<ExplorerTerminalInterrupted>()),
      );

      expect(scenario.terminal.restored, isTrue);
      expect(scenario.controller.model?.is_closed, isTrue);
    });

    test('restores terminal if it becomes too small', () async {
      final scenario = _Scenario(
        children: {
          '/root': ['/root/a.txt'],
        },
        entries: [
          _entry('/root/a.txt', FilesystemEntryKind.regularFile),
        ],
        keys: '\x1B[B',
      );

      scenario.renderer.on_render = (_) {
        scenario.terminal.rows = 5;
      };

      await expectLater(
        scenario.runner.run(),
        throwsStateError,
      );

      expect(scenario.terminal.restored, isTrue);
    });

    test('rejects repeated invocations', () async {
      final scenario = _Scenario(
        children: {'/root': []},
        entries: [],
        keys: 'q',
      );

      expect(
        await scenario.runner.run(),
        RudraExitCode.success.value,
      );

      await expectLater(
        scenario.runner.run(),
        throwsStateError,
      );

      expect(scenario.inspector.listed, ['/root']);
      expect(scenario.terminal.invocations, 1);
    });
  });
}

/// Composes one isolated Explorer interaction fixture.
///
/// Uses the real public SDK and navigation controller.
/// Only external filesystem and terminal operations are faked.
final class _Scenario {
  /// Creates a scenario using the configured input and observations.
  _Scenario({
    required Map<String, List<String>> children,
    required List<FilesystemEntry> entries,
    Map<String, TargetInspectionException> failures = const {},
    String keys = 'q',
    Stream<List<int>>? source,
    int rows = 24,
  }) {
    inspector = _Inspector(
      children: children,
      entries: {
        for (final entry in entries) entry.path.value: entry,
      },
      failures: failures,
    );

    terminal = _FakeTerminalHost(
      source: source ??
          Stream<List<int>>.fromIterable([
            ascii.encode(keys),
          ]),
      rows: rows,
    );

    renderer = _RecordingRenderer();
    errors = StringBuffer();

    controller = ExplorerController(
      sdk: RudraSdk(
        target_id: 'fixture-target',
        inspector: inspector,
      ),
      starting_directory: TargetPath('/root'),
    );

    runner = ExplorerRunner(
      controller: controller,
      terminal: terminal,
      renderer: renderer,
      error_output: errors,
    );
  }

  /// Configured SDK inspection fixture.
  late final _Inspector inspector;

  /// Injected terminal lifecycle.
  late final _FakeTerminalHost terminal;

  /// Captured presentation snapshots.
  late final _RecordingRenderer renderer;

  /// Configuration diagnostics.
  late final StringBuffer errors;

  /// Actual SDK-backed navigation controller.
  late final ExplorerController controller;

  /// Workflow under test.
  late final ExplorerRunner runner;
}

/// Provides read-only in-memory filesystem observations.
///
/// Only the TargetInspector inspection contract is implemented.
/// Unexpected link resolution and capability requests are rejected.
final class _Inspector implements TargetInspector {
  /// Creates an inspector from deterministic directory contents.
  _Inspector({
    required Map<String, List<String>> children,
    required Map<String, FilesystemEntry> entries,
    required Map<String, TargetInspectionException> failures,
  })  : _children = children,
        _entries = entries,
        _failures = failures;

  final Map<String, List<String>> _children;
  final Map<String, FilesystemEntry> _entries;
  final Map<String, TargetInspectionException> _failures;

  /// Paths requested through directory enumeration.
  final List<String> listed = [];

  /// Paths requested through entry inspection.
  final List<String> inspected = [];

  /// Counts symbolic-link destination requests.
  int link_reads = 0;

  /// Counts capability discovery requests.
  int capability_reads = 0;

  /// Directory that should produce an unexpected SDK failure.
  String? unexpected_directory;

  /// Enumerates only configured immediate children.
  @override
  Stream<TargetPath> list_directory(TargetPath path) async* {
    listed.add(path.value);

    if (unexpected_directory == path.value) {
      throw StateError('Injected enumeration failure.');
    }

    for (final child in _children[path.value] ?? const <String>[]) {
      yield TargetPath(child);
    }
  }

  /// Inspects configured entries or propagates configured failures.
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

  /// Rejects capability discovery, which Explorer does not require.
  @override
  Future<TargetCapabilities> capabilities_for(TargetPath path) async {
    capability_reads++;
    throw StateError('Unexpected capability request.');
  }

  /// Rejects symbolic-link resolution.
  @override
  Future<TargetPath> read_symbolic_link(TargetPath path) async {
    link_reads++;
    throw StateError('Unexpected symbolic-link resolution.');
  }
}

/// Simulates one guarded terminal interaction.
///
/// The fake deliberately models restoration in a finally block.
/// The actual Dart host has separate native lifecycle tests.
final class _FakeTerminalHost implements ExplorerTerminalHost {
  /// Creates a terminal with injected input and dimensions.
  _FakeTerminalHost({
    required Stream<List<int>> source,
    required this.rows,
  }) : _source = source;

  final Stream<List<int>> _source;

  /// Whether interactive operation is supported.
  bool interactive = true;

  /// Current terminal width.
  int columns = 80;

  /// Current terminal height.
  int rows;

  /// Number of hosted interaction invocations.
  int invocations = 0;

  /// Whether the last interaction completed its cleanup.
  bool restored = false;

  bool _active = false;

  final StringBuffer _output = StringBuffer();

  @override
  bool get is_interactive => interactive;

  @override
  int get terminal_columns => columns;

  @override
  int get terminal_rows => rows;

  @override
  StringSink get output => _output;

  @override
  Stream<List<int>> get input_bytes {
    if (!_active) {
      throw StateError('No active terminal interaction.');
    }

    return _source;
  }

  /// Runs an interaction with deterministic restoration.
  @override
  Future<T> run_interactive<T>(
    Future<T> Function() interaction,
  ) async {
    if (!interactive || _active) {
      throw StateError('Terminal interaction unavailable.');
    }

    invocations++;
    _active = true;

    try {
      return await interaction();
    } finally {
      restored = true;
      _active = false;
    }
  }
}

/// Records immutable Explorer screen snapshots.
///
/// Rendering may be configured to fail to verify exception
/// propagation through the terminal lifecycle boundary.
final class _RecordingRenderer implements Renderer<ExplorerViewModel> {
  /// Screens successfully accepted by this renderer.
  final List<ExplorerViewModel> frames = [];

  /// Causes rendering to throw an unexpected error.
  bool fail_render = false;

  /// Optional callback invoked after a screen is recorded.
  void Function(ExplorerViewModel)? on_render;

  /// Records one presentation snapshot without terminal I/O.
  @override
  void render(ExplorerViewModel view_model) {
    if (fail_render) {
      throw StateError('Injected rendering failure.');
    }

    frames.add(view_model);
    on_render?.call(view_model);
  }
}

/// Creates one observed filesystem entry without native I/O.
FilesystemEntry _entry(
  String path,
  FilesystemEntryKind kind,
) {
  return FilesystemEntry(
    path: TargetPath(path),
    kind: kind,
    metadata: FilesystemMetadata(),
  );
}
