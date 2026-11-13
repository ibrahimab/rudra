import 'dart:async';

import 'explorer_terminal_device.dart';
import 'explorer_terminal_host.dart';

/// Indicates that a catchable process interruption occurred.
///
/// The terminal host forwards this exception through its
/// input stream. The consuming interaction can then unwind
/// normally, allowing terminal restoration to complete.
///
/// This exception does not authorize or perform process exit.
final class ExplorerTerminalInterrupted implements Exception {
  /// Creates an interruption with its originating signal.
  const ExplorerTerminalInterrupted(this.signal);

  /// Signal that interrupted the interaction.
  final ExplorerTerminalSignal signal;

  /// Provides a readable interruption diagnostic.
  @override
  String toString() => 'Explorer terminal interrupted: ${signal.name}';
}

/// Identifies one failed terminal restoration operation.
///
/// The original error and stack trace are retained so
/// diagnostics do not hide the operating-system failure.
///
/// This type reports a failure; it does not suppress it.
final class ExplorerTerminalRestorationFailure implements Exception {
  /// Creates a failure associated with a restoration operation.
  const ExplorerTerminalRestorationFailure({
    required this.operation,
    required this.cause,
    required this.stack_trace,
  });

  /// Name of the restoration operation that failed.
  final String operation;

  /// Original exception or error from the terminal device.
  final Object cause;

  /// Original stack trace of the failure.
  final StackTrace stack_trace;

  /// Produces an actionable restoration diagnostic.
  @override
  String toString() => '$operation: $cause';
}

/// Reports one or more failures during terminal restoration.
///
/// [interaction_error] retains the original interaction or
/// setup failure, when one occurred.
///
/// [restoration_errors] contains all observed restoration
/// failures in attempted restoration order.
///
/// This exception is thrown only when restoration itself
/// encountered at least one failure.
///
/// Neither the original failure nor restoration failures
/// are silently converted into successful completion.
final class ExplorerTerminalLifecycleException implements Exception {
  /// Creates a combined terminal lifecycle failure.
  ///
  /// [restoration_errors] must contain at least one error.
  ///
  /// The supplied error collection is defensively copied.
  ExplorerTerminalLifecycleException({
    required this.interaction_error,
    required List<Object> restoration_errors,
  }) : restoration_errors = List<Object>.unmodifiable(
          restoration_errors,
        ) {
    if (restoration_errors.isEmpty) {
      throw ArgumentError(
        'At least one restoration error is required.',
      );
    }
  }

  /// Original setup or interaction error, when present.
  final Object? interaction_error;

  /// Errors encountered while restoring terminal state.
  final List<Object> restoration_errors;

  /// Produces a complete lifecycle failure diagnostic.
  ///
  /// Each restoration failure includes the operation name
  /// and its original error message.
  @override
  String toString() {
    final details =
        restoration_errors.map((error) => error.toString()).join('; ');

    return 'Explorer terminal lifecycle failure: '
        '${restoration_errors.length} restoration error(s); '
        'interaction error: $interaction_error; '
        'restoration details: $details';
  }
}

/// Hosts one Explorer interaction using an injectable terminal device.
///
/// The host owns the complete terminal lifecycle:
/// - Interactive capability validation.
/// - Original terminal setting capture.
/// - Input echo and line-mode changes.
/// - Alternate-screen activation.
/// - Cursor visibility changes.
/// - Raw input forwarding.
/// - Process interruption forwarding.
/// - Resource cancellation and terminal restoration.
///
/// The host does not interpret keyboard navigation commands.
/// It does not invoke the SDK or inspect filesystem entries.
///
/// Each host instance supports one interaction. A new instance
/// must be created for another independent CLI invocation.
///
/// All restoration steps are attempted independently.
/// One failed restoration step does not prevent the others.
///
/// On a restoration failure, an
/// [ExplorerTerminalLifecycleException] preserves the errors.
///
/// On successful restoration, an original interaction exception
/// propagates with its original stack trace.
///
/// Example:
/// ```dart
/// final host = DartExplorerTerminalHost();
///
/// final result = await host.run_interactive(() async {
///   // Consume host.input_bytes through TerminalInput.
///   return 0;
/// });
///
/// print(result);
/// ```
final class DartExplorerTerminalHost implements ExplorerTerminalHost {
  /// Creates a host for the supplied terminal device.
  ///
  /// When [device] is omitted, the production dart:io device
  /// is used.
  ///
  /// Construction performs no terminal-mode changes.
  DartExplorerTerminalHost({
    ExplorerTerminalDevice? device,
  }) : _device = device ?? const DartExplorerTerminalDevice();

  /// Device providing low-level terminal operations.
  final ExplorerTerminalDevice _device;

  /// Whether an interaction currently owns terminal state.
  bool _is_active = false;

  /// Whether this host has already begun an interaction.
  bool _has_started = false;

  /// Input stream controller for the current interaction.
  StreamController<List<int>>? _active_input;

  /// Trusted ANSI sequence entering the alternate screen.
  static const String _enter_alternate_screen = '\x1B[?1049h';

  /// Trusted ANSI sequence leaving the alternate screen.
  static const String _leave_alternate_screen = '\x1B[?1049l';

  /// Trusted ANSI sequence hiding the cursor.
  static const String _hide_cursor = '\x1B[?25l';

  /// Trusted ANSI sequence showing the cursor.
  static const String _show_cursor = '\x1B[?25h';

  /// Trusted ANSI sequence resetting text attributes.
  static const String _reset_attributes = '\x1B[0m';

  /// Whether the terminal supports the required interactive mode.
  ///
  /// Both input and output must be terminals, ANSI must be
  /// supported, and dimensions must be positive.
  ///
  /// No terminal settings are changed during detection.
  @override
  bool get is_interactive =>
      _device.has_input_terminal &&
      _device.has_output_terminal &&
      _device.supports_ansi &&
      _device.columns > 0 &&
      _device.rows > 0;

  /// Returns the current terminal width.
  @override
  int get terminal_columns => _device.columns;

  /// Returns the current terminal height.
  @override
  int get terminal_rows => _device.rows;

  /// Returns the active single-subscription input stream.
  ///
  /// Throws [StateError] outside an active interaction.
  ///
  /// Input errors, including process interruptions, propagate
  /// through this stream to the consuming Explorer workflow.
  @override
  Stream<List<int>> get input_bytes {
    final controller = _active_input;

    if (!_is_active || controller == null) {
      throw StateError(
        'Explorer input is available only during interaction.',
      );
    }

    return controller.stream;
  }

  /// Returns the configured terminal output sink.
  @override
  StringSink get output => _device.output;

  /// Runs one interaction with guaranteed restoration attempts.
  ///
  /// The original echo and line modes are captured before
  /// either value is changed.
  ///
  /// The host then:
  /// 1. Installs signal forwarding.
  /// 2. Disables echo and canonical line input.
  /// 3. Enters the alternate screen.
  /// 4. Hides the cursor.
  /// 5. Subscribes to raw terminal input.
  /// 6. Executes [interaction].
  ///
  /// Every change is marked for restoration before attempting
  /// the corresponding operation. This accounts for setters
  /// and output writes that partially succeed before throwing.
  ///
  /// Cleanup cancels subscriptions, closes the input stream,
  /// restores screen and cursor state, and restores input modes.
  ///
  /// Setup and interaction failures propagate after cleanup.
  ///
  /// If restoration fails, an
  /// [ExplorerTerminalLifecycleException] is thrown containing
  /// the restoration failures and original error, if present.
  ///
  /// Throws [StateError] when:
  /// - The terminal is unsuitable for interactive operation.
  /// - This host is already active.
  /// - This host has previously been used.
  ///
  /// Signals are delivered through [input_bytes]. A workflow
  /// must actively consume that stream to respond to them.
  /// This host does not forcibly cancel outstanding SDK calls.
  ///
  /// Terminal restoration cannot be guaranteed following
  /// uncatchable signals, abrupt process death, or power loss.
  ///
  /// No filesystem inspection or mutation occurs here.
  @override
  Future<T> run_interactive<T>(
    Future<T> Function() interaction,
  ) async {
    if (_is_active || _has_started) {
      throw StateError(
        'This Explorer terminal host cannot be reused.',
      );
    }

    if (!is_interactive) {
      throw StateError(
        'An interactive terminal with ANSI support is required.',
      );
    }

    _is_active = true;
    _has_started = true;

    final restoration_errors = <Object>[];

    Object? interaction_error;
    StackTrace? interaction_stack;

    bool? original_echo_mode;
    bool? original_line_mode;

    var echo_change_attempted = false;
    var line_change_attempted = false;
    var alternate_screen_attempted = false;
    var cursor_hide_attempted = false;

    StreamController<List<int>>? input_controller;
    StreamSubscription<List<int>>? input_subscription;
    StreamSubscription<ExplorerTerminalSignal>? signal_subscription;

    late T result;

    try {
      original_echo_mode = _device.echo_mode;
      original_line_mode = _device.line_mode;

      final controller = StreamController<List<int>>();
      input_controller = controller;
      _active_input = controller;

      // Install signal handling before altering terminal modes.
      //
      // A single-subscription controller retains early events
      // until the Explorer interaction subscribes to input.
      signal_subscription = _device.signals.listen(
        (signal) {
          if (!controller.isClosed) {
            controller.addError(
              ExplorerTerminalInterrupted(signal),
            );
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!controller.isClosed) {
            controller.addError(error, stack);
          }
        },
      );

      // Mark changes before attempting them. A native setter
      // may alter state and then report an error.
      echo_change_attempted = true;
      _device.echo_mode = false;

      line_change_attempted = true;
      _device.line_mode = false;

      alternate_screen_attempted = true;
      _device.output.write(_enter_alternate_screen);

      cursor_hide_attempted = true;
      _device.output.write(_hide_cursor);

      // Raw input is forwarded without interpreting bytes.
      // Keyboard decoding belongs to TerminalInput.
      input_subscription = _device.input_bytes.listen(
        (bytes) {
          if (!controller.isClosed) {
            controller.add(bytes);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!controller.isClosed) {
            controller.addError(error, stack);
          }
        },
        onDone: () {
          if (!controller.isClosed) {
            controller.close();
          }
        },
      );

      result = await interaction();
    } catch (error, stack) {
      interaction_error = error;
      interaction_stack = stack;
    }

    // Stop forwarding process signals before restoration.
    //
    // The interaction has finished, so new interruptions
    // should not be delivered into its closing input stream.
    await _attempt_restoration(
      'cancel signal subscription',
      () async {
        await signal_subscription?.cancel();
      },
      restoration_errors,
    );

    // Stop delivering further keyboard events while restoring
    // terminal state, but keep the underlying stdin subscription
    // alive until the original terminal modes are restored.
    //
    // Canceling a native stdin subscription too early may make
    // its terminal descriptor unavailable to the mode setters.
    await _attempt_restoration(
      'pause terminal input',
      () {
        input_subscription?.pause();
      },
      restoration_errors,
    );

    // Restore visual terminal state independently.
    //
    // An output failure must not prevent input-mode restoration.
    if (cursor_hide_attempted) {
      await _attempt_restoration(
        'reset terminal text attributes',
        () => _device.output.write(_reset_attributes),
        restoration_errors,
      );

      await _attempt_restoration(
        'restore cursor visibility',
        () => _device.output.write(_show_cursor),
        restoration_errors,
      );
    }

    if (alternate_screen_attempted) {
      await _attempt_restoration(
        'leave alternate screen',
        () => _device.output.write(_leave_alternate_screen),
        restoration_errors,
      );
    }

    // Restore terminal modes BEFORE canceling the native
    // stdin subscription.
    //
    // Both setters retain their original configured values.
    // Each is attempted even if the other fails.
    //
    // Restore line mode before echo mode to respect terminal
    // implementations where echo depends on canonical input.
    if (line_change_attempted) {
      await _attempt_restoration(
        'restore terminal line mode',
        () => _device.line_mode = original_line_mode!,
        restoration_errors,
      );
    }

    if (echo_change_attempted) {
      await _attempt_restoration(
        'restore terminal echo mode',
        () => _device.echo_mode = original_echo_mode!,
        restoration_errors,
      );
    }

    // Native input can now be released without risking the
    // availability of the terminal-mode restoration operations.
    await _attempt_restoration(
      'cancel terminal input subscription',
      () async {
        await input_subscription?.cancel();
      },
      restoration_errors,
    );

    // Close the forwarded input stream after native input
    // has been released.
    //
    // Do not await StreamController.close() here: a setup
    // failure may occur before any consumer subscribes.
    await _attempt_restoration(
      'close forwarded input stream',
      () {
        final controller = input_controller;

        if (controller != null && !controller.isClosed) {
          controller.close();
        }
      },
      restoration_errors,
    );

    _active_input = null;

    // Release ownership only after all cleanup attempts.
    _is_active = false;

    if (restoration_errors.isNotEmpty) {
      throw ExplorerTerminalLifecycleException(
        interaction_error: interaction_error,
        restoration_errors: restoration_errors,
      );
    }

    if (interaction_error != null) {
      Error.throwWithStackTrace(
        interaction_error,
        interaction_stack!,
      );
    }

    return result;
  }

  /// Attempts one named restoration operation.
  ///
  /// All failures are captured with their original causes
  /// and stack traces.
  ///
  /// Recording a failure does not stop subsequent restoration
  /// operations from being attempted.
  ///
  /// The caller reports all collected errors after cleanup.
  static Future<void> _attempt_restoration(
    String operation_name,
    FutureOr<void> Function() operation,
    List<Object> errors,
  ) async {
    try {
      await operation();
    } catch (error, stack) {
      errors.add(
        ExplorerTerminalRestorationFailure(
          operation: operation_name,
          cause: error,
          stack_trace: stack,
        ),
      );
    }
  }
}
