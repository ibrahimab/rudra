import 'dart:async';

import 'package:rudra_cli/src/features/explorer/terminal/dart_explorer_terminal_host.dart';
import 'package:rudra_cli/src/features/explorer/terminal/explorer_terminal_device.dart';
import 'package:test/test.dart';

/// Verifies the Explorer terminal lifecycle.
///
/// Terminal operations are simulated through an injected device.
///
/// Tests never modify actual stdin settings, cursor visibility,
/// terminal screen buffers, or filesystem content.
void main() {
  group('DartExplorerTerminalHost', () {
    test('restores input modes after successful interaction', () async {
      final device = _FakeTerminalDevice();
      final host = DartExplorerTerminalHost(device: device);

      final result = await host.run_interactive(() async {
        expect(device.echo_mode, isFalse);
        expect(device.line_mode, isFalse);

        expect(
          device.written,
          contains('\x1B[?1049h\x1B[?25l'),
        );

        return 42;
      });

      expect(result, 42);
      expect(device.echo_mode, isTrue);
      expect(device.line_mode, isTrue);
      expect(device.input_canceled, isTrue);
      expect(device.signals_canceled, isTrue);

      expect(device.written, contains('\x1B[0m'));
      expect(device.written, contains('\x1B[?25h'));
      expect(device.written, contains('\x1B[?1049l'));
    });

    test('preserves initially disabled input settings', () async {
      final device = _FakeTerminalDevice(
        initial_echo_mode: false,
        initial_line_mode: false,
      );

      final host = DartExplorerTerminalHost(device: device);

      await host.run_interactive(() async => 0);

      expect(device.echo_mode, isFalse);
      expect(device.line_mode, isFalse);
    });

    test('forwards raw input bytes without interpretation', () async {
      final device = _FakeTerminalDevice();
      final host = DartExplorerTerminalHost(device: device);

      final received = host.run_interactive(() async {
        return host.input_bytes.first;
      });

      device.send_bytes([0x1B, 0x5B, 0x41]);

      expect(
        await received,
        orderedEquals([0x1B, 0x5B, 0x41]),
      );

      expect(device.input_canceled, isTrue);
    });

    test('restores terminal after an interaction exception', () async {
      final device = _FakeTerminalDevice();
      final host = DartExplorerTerminalHost(device: device);

      await expectLater(
        host.run_interactive<int>(() async {
          throw StateError('Injected interaction failure.');
        }),
        throwsStateError,
      );

      expect(device.echo_mode, isTrue);
      expect(device.line_mode, isTrue);
      expect(device.written, contains('\x1B[?25h'));
      expect(device.written, contains('\x1B[?1049l'));
    });

    test('restores state after partial terminal setup failure', () async {
      final device = _FakeTerminalDevice();
      device.fail_line_disable = true;

      final host = DartExplorerTerminalHost(device: device);

      var interaction_called = false;

      await expectLater(
        host.run_interactive(() async {
          interaction_called = true;
          return 0;
        }),
        throwsStateError,
      );

      expect(interaction_called, isFalse);
      expect(device.echo_mode, isTrue);
      expect(device.line_mode, isTrue);

      // No screen sequence was written yet.
      expect(device.written, isEmpty);
      expect(device.signals_canceled, isTrue);
    });

    test('restores screen after cursor-hide write fails', () async {
      final device = _FakeTerminalDevice();
      device.fail_cursor_hide = true;

      final host = DartExplorerTerminalHost(device: device);

      await expectLater(
        host.run_interactive(() async => 0),
        throwsStateError,
      );

      expect(device.written, contains('\x1B[?1049h'));
      expect(device.written, contains('\x1B[?25h'));
      expect(device.written, contains('\x1B[?1049l'));
      expect(device.echo_mode, isTrue);
      expect(device.line_mode, isTrue);
    });

    test('reports both interaction and restoration failures', () async {
      final device = _FakeTerminalDevice();
      device.fail_echo_restore = true;

      final host = DartExplorerTerminalHost(device: device);

      await expectLater(
        host.run_interactive<int>(() async {
          throw StateError('Interaction failure.');
        }),
        throwsA(
          isA<ExplorerTerminalLifecycleException>()
              .having(
                (error) => error.interaction_error,
                'interaction_error',
                isA<StateError>(),
              )
              .having(
                (error) => error.restoration_errors,
                'restoration_errors',
                isNotEmpty,
              ),
        ),
      );

      // Other restoration operations still run.
      expect(device.line_mode, isTrue);
      expect(device.written, contains('\x1B[?1049l'));
    });

    test('reports restoration failure after successful interaction', () async {
      final device = _FakeTerminalDevice();
      device.fail_echo_restore = true;

      final host = DartExplorerTerminalHost(device: device);

      await expectLater(
        host.run_interactive(() async => 0),
        throwsA(
          isA<ExplorerTerminalLifecycleException>().having(
            (error) => error.interaction_error,
            'interaction_error',
            isNull,
          ),
        ),
      );
    });

    test('forwards SIGINT as a typed input error', () async {
      final device = _FakeTerminalDevice();
      final host = DartExplorerTerminalHost(device: device);

      final result = host.run_interactive(() async {
        await host.input_bytes.first;
        return 0;
      });

      device.send_signal(ExplorerTerminalSignal.interrupt);

      await expectLater(
        result,
        throwsA(
          isA<ExplorerTerminalInterrupted>().having(
            (error) => error.signal,
            'signal',
            ExplorerTerminalSignal.interrupt,
          ),
        ),
      );

      expect(device.echo_mode, isTrue);
      expect(device.line_mode, isTrue);
      expect(device.written, contains('\x1B[?1049l'));
    });

    test('forwards SIGTERM as a typed input error', () async {
      final device = _FakeTerminalDevice();
      final host = DartExplorerTerminalHost(device: device);

      final result = host.run_interactive(() async {
        await host.input_bytes.first;
        return 0;
      });

      device.send_signal(ExplorerTerminalSignal.terminate);

      await expectLater(
        result,
        throwsA(
          isA<ExplorerTerminalInterrupted>().having(
            (error) => error.signal,
            'signal',
            ExplorerTerminalSignal.terminate,
          ),
        ),
      );

      expect(device.echo_mode, isTrue);
      expect(device.line_mode, isTrue);
    });

    test('propagates raw input errors and restores modes', () async {
      final device = _FakeTerminalDevice();
      final host = DartExplorerTerminalHost(device: device);

      final result = host.run_interactive(() async {
        await host.input_bytes.first;
        return 0;
      });

      device.fail_input(StateError('Input failure.'));

      await expectLater(result, throwsStateError);

      expect(device.echo_mode, isTrue);
      expect(device.line_mode, isTrue);
      expect(device.input_canceled, isTrue);
    });

    test('rejects noninteractive input without changing modes', () async {
      final device = _FakeTerminalDevice();
      device.has_input_terminal = false;

      final host = DartExplorerTerminalHost(device: device);

      expect(host.is_interactive, isFalse);

      await expectLater(
        host.run_interactive(() async => 0),
        throwsStateError,
      );

      expect(device.mode_changes, isEmpty);
      expect(device.written, isEmpty);
    });

    test('rejects redirected output and unsupported ANSI', () async {
      for (final disable_output in [true, false]) {
        final device = _FakeTerminalDevice();

        if (disable_output) {
          device.has_output_terminal = false;
        } else {
          device.supports_ansi = false;
        }

        final host = DartExplorerTerminalHost(device: device);

        expect(host.is_interactive, isFalse);

        await expectLater(
          host.run_interactive(() async => 0),
          throwsStateError,
        );

        expect(device.mode_changes, isEmpty);
      }
    });

    test('rejects unavailable terminal dimensions', () async {
      final device = _FakeTerminalDevice();
      device.rows = 0;

      final host = DartExplorerTerminalHost(device: device);

      expect(host.is_interactive, isFalse);

      await expectLater(
        host.run_interactive(() async => 0),
        throwsStateError,
      );
    });

    test('rejects nested and repeated interactions', () async {
      final device = _FakeTerminalDevice();
      final host = DartExplorerTerminalHost(device: device);

      await host.run_interactive(() async {
        await expectLater(
          host.run_interactive(() async => 0),
          throwsStateError,
        );

        return 0;
      });

      await expectLater(
        host.run_interactive(() async => 0),
        throwsStateError,
      );
    });

    test('rejects input access outside an interaction', () {
      final host = DartExplorerTerminalHost(
        device: _FakeTerminalDevice(),
      );

      expect(() => host.input_bytes, throwsStateError);
    });

    test('restores terminal modes before canceling stdin', () async {
      final device = _FakeTerminalDevice();

      // This simulation reproduces the descriptor-lifetime
      // condition suspected in the real macOS failure.
      device.require_active_input_for_mode_restore = true;

      final host = DartExplorerTerminalHost(device: device);

      final result = await host.run_interactive(() async {
        expect(device.echo_mode, isFalse);
        expect(device.line_mode, isFalse);
        expect(device.input_canceled, isFalse);

        return 0;
      });

      expect(result, 0);

      expect(device.line_mode, isTrue);
      expect(device.echo_mode, isTrue);

      expect(device.input_canceled, isTrue);
      expect(device.signals_canceled, isTrue);

      expect(device.written, contains('\x1B[?25h'));
      expect(device.written, contains('\x1B[?1049l'));
    });

    test('reports the exact failed restoration operation', () async {
      final device = _FakeTerminalDevice();
      device.fail_echo_restore = true;

      final host = DartExplorerTerminalHost(device: device);

      try {
        await host.run_interactive(() async => 0);

        fail('Expected terminal restoration to fail.');
      } on ExplorerTerminalLifecycleException catch (error) {
        expect(error.interaction_error, isNull);
        expect(error.restoration_errors, hasLength(1));

        final failure = error.restoration_errors.single;

        expect(
          failure,
          isA<ExplorerTerminalRestorationFailure>(),
        );

        final restoration_failure =
            failure as ExplorerTerminalRestorationFailure;

        expect(
          restoration_failure.operation,
          'restore terminal echo mode',
        );

        expect(restoration_failure.cause, isA<StateError>());

        expect(
          error.toString(),
          contains('restore terminal echo mode'),
        );

        expect(
          error.toString(),
          contains('Injected echo restoration failure.'),
        );
      }

      // A failed echo restoration must not prevent other
      // terminal cleanup operations.
      expect(device.line_mode, isTrue);
      expect(device.input_canceled, isTrue);
      expect(device.signals_canceled, isTrue);
      expect(device.written, contains('\x1B[?1049l'));
    });
  });
}

/// Test device that simulates terminal state and process signals.
///
/// All changes occur in memory.
final class _FakeTerminalDevice implements ExplorerTerminalDevice {
  /// Creates a fake terminal with configurable initial modes.
  _FakeTerminalDevice({
    bool initial_echo_mode = true,
    bool initial_line_mode = true,
  })  : _echo_mode = initial_echo_mode,
        _line_mode = initial_line_mode {
    _input = StreamController<List<int>>.broadcast(
      onCancel: () => input_canceled = true,
      sync: true,
    );

    _signals = StreamController<ExplorerTerminalSignal>.broadcast(
      onCancel: () => signals_canceled = true,
      sync: true,
    );
  }

  @override
  bool has_input_terminal = true;

  @override
  bool has_output_terminal = true;

  @override
  bool supports_ansi = true;

  @override
  int columns = 80;

  @override
  int rows = 24;

  bool _echo_mode;
  bool _line_mode;

  /// Simulates a device that rejects mode changes after
  /// its native input subscription has been canceled.
  bool require_active_input_for_mode_restore = false;

  bool fail_line_disable = false;
  bool fail_echo_restore = false;
  bool fail_cursor_hide = false;

  bool input_canceled = false;
  bool signals_canceled = false;

  final List<String> mode_changes = [];

  late final StreamController<List<int>> _input;
  late final StreamController<ExplorerTerminalSignal> _signals;

  final _RecordedOutput _output = _RecordedOutput();

  /// Complete terminal output produced during the interaction.
  String get written => _output.buffer.toString();

  @override
  bool get echo_mode => _echo_mode;

  /// Changes simulated echo mode.
  ///
  /// Can reproduce a native terminal descriptor that becomes
  /// unavailable after its input subscription is canceled.
  @override
  set echo_mode(bool value) {
    mode_changes.add('echo:$value');

    if (require_active_input_for_mode_restore && input_canceled) {
      throw StateError(
        'Cannot restore echo mode after stdin cancellation.',
      );
    }

    _echo_mode = value;

    if (value && fail_echo_restore) {
      throw StateError('Injected echo restoration failure.');
    }
  }

  @override
  bool get line_mode => _line_mode;

  /// Changes simulated canonical input mode.
  ///
  /// Rejects changes after input cancellation when the
  /// descriptor-lifetime failure simulation is enabled.
  @override
  set line_mode(bool value) {
    mode_changes.add('line:$value');

    if (require_active_input_for_mode_restore && input_canceled) {
      throw StateError(
        'Cannot restore line mode after stdin cancellation.',
      );
    }

    _line_mode = value;

    if (!value && fail_line_disable) {
      throw StateError('Injected line-mode failure.');
    }
  }

  @override
  Stream<List<int>> get input_bytes => _input.stream;

  @override
  Stream<ExplorerTerminalSignal> get signals => _signals.stream;

  @override
  StringSink get output {
    _output.fail_cursor_hide = fail_cursor_hide;
    return _output;
  }

  /// Delivers simulated terminal input.
  void send_bytes(List<int> bytes) {
    _input.add(bytes);
  }

  /// Delivers a simulated catchable process signal.
  void send_signal(ExplorerTerminalSignal signal) {
    _signals.add(signal);
  }

  /// Delivers a simulated terminal input failure.
  void fail_input(Object error) {
    _input.addError(error);
  }
}

/// Captures trusted terminal output and simulates write failures.
final class _RecordedOutput implements StringSink {
  /// Captured output.
  final StringBuffer buffer = StringBuffer();

  /// Whether cursor hiding should fail after a partial write.
  bool fail_cursor_hide = false;

  @override
  void write(Object? object) {
    final value = object.toString();

    buffer.write(value);

    if (fail_cursor_hide && value == '\x1B[?25l') {
      throw StateError('Injected cursor-hide failure.');
    }
  }

  @override
  void writeln([Object? object = '']) {
    write(object);
    write('\n');
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    write(objects.join(separator));
  }

  @override
  void writeCharCode(int char_code) {
    write(String.fromCharCode(char_code));
  }
}
