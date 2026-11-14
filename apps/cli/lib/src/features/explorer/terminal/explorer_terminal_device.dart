import 'dart:async';
import 'dart:io';

/// Catchable process signals supported by the Explorer terminal host.
///
/// Signals represent process interruption, not filesystem operations.
enum ExplorerTerminalSignal {
  /// Interrupt requested, normally through Ctrl+C.
  interrupt,

  /// Process termination requested.
  terminate,
}

/// Provides low-level terminal facilities to an Explorer host.
///
/// The device exposes terminal operations without implementing
/// Explorer navigation, presentation, or SDK behavior.
///
/// Keeping these operations injectable allows lifecycle tests
/// to simulate partial failures and interruptions without
/// changing the developer's actual terminal configuration.
///
/// A device implementation must preserve the distinction
/// between interactive and redirected input/output.
///
/// Example:
/// ```dart
/// const device = DartExplorerTerminalDevice();
///
/// if (device.has_input_terminal && device.has_output_terminal) {
///   print(device.columns);
/// }
/// ```
abstract interface class ExplorerTerminalDevice {
  /// Whether standard input is attached to a terminal.
  bool get has_input_terminal;

  /// Whether standard output is attached to a terminal.
  bool get has_output_terminal;

  /// Whether ANSI terminal control sequences are supported.
  bool get supports_ansi;

  /// Current terminal width in display columns.
  int get columns;

  /// Current terminal height in display rows.
  int get rows;

  /// Whether terminal input echo is enabled.
  ///
  /// Setters may throw if the operating system rejects a change.
  bool get echo_mode;
  set echo_mode(bool value);

  /// Whether canonical line input processing is enabled.
  ///
  /// Disabling this permits individual key input.
  bool get line_mode;
  set line_mode(bool value);

  /// Raw terminal input bytes.
  ///
  /// The owning host establishes and cancels the subscription.
  Stream<List<int>> get input_bytes;

  /// Catchable process interruption notifications.
  ///
  /// The host establishes the subscription for one interaction.
  /// Canceling that subscription must release signal listeners.
  Stream<ExplorerTerminalSignal> get signals;

  /// Terminal output destination.
  ///
  /// Writes may throw and must be handled by the terminal host.
  StringSink get output;
}

/// Implements Explorer terminal operations through dart:io.
///
/// This adapter is intended for the current local terminal
/// application. It does not implement filesystem inspection.
///
/// Terminal modes are never changed by construction or by
/// terminal capability detection.
///
/// Signal listeners are installed lazily when the returned
/// signal stream receives a subscription.
///
/// Example:
/// ```dart
/// const device = DartExplorerTerminalDevice();
///
/// print(device.has_input_terminal);
/// ```
final class DartExplorerTerminalDevice implements ExplorerTerminalDevice {
  /// Creates a terminal device without changing process state.
  const DartExplorerTerminalDevice();

  /// Reports whether stdin is attached to a terminal.
  @override
  bool get has_input_terminal => stdin.hasTerminal;

  /// Reports whether stdout is attached to a terminal.
  @override
  bool get has_output_terminal => stdout.hasTerminal;

  /// Enables ANSI operations only for a configured terminal.
  ///
  /// An absent or explicitly dumb TERM setting is not assumed
  /// to support interactive ANSI screen control.
  @override
  bool get supports_ansi {
    final term = Platform.environment['TERM'];

    return term != null && term.isNotEmpty && term.toLowerCase() != 'dumb';
  }

  /// Returns the current stdout terminal width.
  @override
  int get columns => stdout.terminalColumns;

  /// Returns the current stdout terminal height.
  @override
  int get rows => stdout.terminalLines;

  /// Reads the existing stdin echo setting.
  @override
  bool get echo_mode => stdin.echoMode;

  /// Changes stdin echo behavior.
  @override
  set echo_mode(bool value) {
    stdin.echoMode = value;
  }

  /// Reads the existing stdin line-processing setting.
  @override
  bool get line_mode => stdin.lineMode;

  /// Changes stdin line-processing behavior.
  @override
  set line_mode(bool value) {
    stdin.lineMode = value;
  }

  /// Supplies raw stdin byte events.
  ///
  /// Subscription ownership remains with the terminal host.
  @override
  Stream<List<int>> get input_bytes => stdin;

  /// Supplies catchable interrupt and termination signals.
  ///
  /// SIGTERM is unavailable on Windows and is not registered
  /// there. The initial production Explorer targets macOS.
  ///
  /// Canceling the returned stream subscription cancels
  /// all native signal subscriptions created by that stream.
  @override
  Stream<ExplorerTerminalSignal> get signals {
    StreamSubscription<ProcessSignal>? interrupt_subscription;
    StreamSubscription<ProcessSignal>? terminate_subscription;

    late final StreamController<ExplorerTerminalSignal> controller;

    controller = StreamController<ExplorerTerminalSignal>(
      onListen: () {
        interrupt_subscription = ProcessSignal.sigint.watch().listen(
          (_) => controller.add(ExplorerTerminalSignal.interrupt),
        );

        if (!Platform.isWindows) {
          terminate_subscription = ProcessSignal.sigterm.watch().listen(
            (_) => controller.add(ExplorerTerminalSignal.terminate),
          );
        }
      },
      onCancel: () async {
        await interrupt_subscription?.cancel();
        await terminate_subscription?.cancel();
      },
    );

    return controller.stream;
  }

  /// Supplies stdout for interactive rendering.
  @override
  StringSink get output => stdout;
}
