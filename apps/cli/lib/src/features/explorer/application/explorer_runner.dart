import 'dart:async';

import '../../../core/cli/rudra_exit_code.dart';
import '../../../core/rendering/renderer.dart';

import '../presentation/explorer_view_model.dart';
import '../terminal/explorer_terminal_host.dart';
import '../terminal/terminal_input.dart';
import '../terminal/terminal_key.dart';

import 'explorer_controller.dart';

/// Hosts one Explorer interaction in a terminal.
///
/// The runner checks terminal capabilities, decodes input, and renders the
/// controller's view models inside the terminal host's restoration scope.
///
/// Example:
/// ```dart
/// final runner = ExplorerRunner(
///   controller: controller,
///   terminal: terminal,
///   renderer: renderer,
///   error_output: stderr,
/// );
/// final status = await runner.run();
/// ```
final class ExplorerRunner {
  /// Creates the runner without starting the interaction.
  ///
  /// [controller] owns navigation, application state and action dispatch.
  /// The runner disposes it after the terminal interaction ends or startup fails.
  /// [terminal] supplies input, dimensions and guarded terminal lifecycle.
  /// [renderer] renders complete snapshots and reports its fixed row count.
  /// [error_output] receives terminal configuration diagnostics.
  ExplorerRunner({
    required ExplorerController controller,
    required ExplorerTerminalHost terminal,
    required ViewportRenderer<ExplorerViewModel> renderer,
    required StringSink error_output,
  }) : _controller = controller,
       _terminal = terminal,
       _renderer = renderer,
       _error_output = error_output;

  /// Controller for the interaction hosted by this runner.
  final ExplorerController _controller;

  /// Interactive terminal lifecycle and input provider.
  final ExplorerTerminalHost _terminal;

  /// Renderer for complete Explorer presentation snapshots.
  final ViewportRenderer<ExplorerViewModel> _renderer;

  /// Output destination for terminal configuration diagnostics.
  final StringSink _error_output;

  /// Whether this runner has already been invoked.
  bool _has_started = false;

  /// Terminal rows reserved for fixed widgets and the final newline.
  ///
  /// Throws [StateError] if the renderer reports a negative fixed height.
  int get _reserved_terminal_rows {
    final fixed_rows = _renderer.fixed_rows;
    if (fixed_rows < 0) {
      throw StateError('Explorer renderer reported a negative fixed height.');
    }

    // Keep the final newline from scrolling the alternate screen.
    return fixed_rows + 1;
  }

  /// Runs one interaction through Quit, Ctrl+C, or input EOF.
  ///
  /// Returns [RudraExitCode.configuration_error] for an unsupported or
  /// initially undersized terminal before performing a directory inspection.
  /// Otherwise returns [RudraExitCode.inspection_incomplete] if any directory
  /// observation was incomplete, or [RudraExitCode.success].
  ///
  /// Throws [StateError] on repeated invocation or if the terminal becomes
  /// too small during interaction. Startup synchronization and inspection
  /// failures propagate before entering interactive mode. Once hosted, errors
  /// including OS interruptions propagate after terminal restoration is attempted.
  Future<int> run() async {
    if (_has_started) {
      throw StateError('ExplorerRunner supports only one invocation.');
    }
    _has_started = true;

    try {
      final required_rows = _reserved_terminal_rows;
      if (!_terminal.is_interactive ||
          _terminal.terminal_rows < required_rows) {
        _error_output.writeln(
          'Interactive Explorer requires a supported terminal '
          'with at least $required_rows rows.',
        );
        return RudraExitCode.configuration_error.value;
      }

      await _controller.start();
      await _terminal.run_interactive(_interact);

      return _controller.encountered_incomplete
          ? RudraExitCode.inspection_incomplete.value
          : RudraExitCode.success.value;
    } finally {
      await _controller.dispose();
    }
  }

  /// Consumes input and invalidations inside the terminal restoration scope.
  ///
  /// At most one asynchronous operation and one pending redraw are retained.
  /// Termination stops admission immediately and waits for the operation to
  /// settle before releasing input and presentation subscriptions.
  Future<void> _interact() async {
    final stopping = Completer<void>();
    (Object, StackTrace)? failure;
    Future<void>? operation;
    var needs_redraw = false;
    var redraw_scheduled = false;

    void stop([Object? error, StackTrace? stack]) {
      if (error != null) failure ??= (error, stack ?? StackTrace.current);
      if (!stopping.isCompleted) stopping.complete();
    }

    void redraw() {
      if (stopping.isCompleted || operation != null || !needs_redraw) return;

      needs_redraw = false;
      try {
        _render();
      } catch (error, stack) {
        stop(error, stack);
      }
    }

    Future<void> settle(Future<bool> result) async {
      try {
        if (await result) needs_redraw = true;
      } catch (error, stack) {
        stop(error, stack);
      } finally {
        operation = null;
        redraw();
      }
    }

    void on_key(TerminalKey key) {
      if (stopping.isCompleted) return;
      if (ExplorerController.is_exit_key(key)) {
        stop();
        return;
      }
      // The input subscription stays active while an operation is outstanding.
      if (operation != null) return;

      try {
        final result = _controller.handle_key(key);
        if (result is Future<bool>) {
          operation = settle(result);
        } else if (result == true) {
          needs_redraw = true;
          redraw();
        }
      } catch (error, stack) {
        stop(error, stack);
      }
    }

    final presentation = _controller.presentation_changes.listen((_) {
      if (stopping.isCompleted) return;

      needs_redraw = true;
      if (operation != null || redraw_scheduled) return;

      redraw_scheduled = true;
      scheduleMicrotask(() {
        redraw_scheduled = false;
        redraw();
      });
    });

    StreamSubscription<TerminalKey>? keys;
    try {
      _render();
      final input = TerminalInput(source: _terminal.input_bytes);
      keys = input.read_keys().listen(on_key, onError: stop, onDone: stop);
      await stopping.future;
      await operation;
      if (failure case (final error, final stack)) {
        Error.throwWithStackTrace(error, stack);
      }
    } finally {
      stop();
      await Future.wait<void>([
        Future<void>.sync(presentation.cancel),
        if (keys != null) Future<void>.sync(keys.cancel),
      ]);
    }
  }

  /// Renders using the current terminal height, including after a resize.
  ///
  /// Throws [StateError] if the fixed rows no longer fit.
  void _render() {
    final visible_row_limit = _terminal.terminal_rows - _reserved_terminal_rows;
    if (visible_row_limit < 0) {
      throw StateError('Terminal became too small for Explorer rendering.');
    }

    final view = _controller.view_model(visible_row_limit: visible_row_limit);
    _renderer.render(view);
    _controller.acknowledge_render(view);
  }
}
