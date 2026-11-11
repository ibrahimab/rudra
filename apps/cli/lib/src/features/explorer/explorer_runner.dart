import '../../core/cli/rudra_exit_code.dart';
import '../../core/rendering/renderer.dart';

import 'explorer_controller.dart';
import 'explorer_model.dart';
import 'explorer_presenter.dart';
import 'explorer_terminal_host.dart';
import 'explorer_view_model.dart';
import 'terminal_input.dart';

/// Coordinates one interactive, read-only Explorer workflow.
///
/// The runner connects existing CLI components:
/// - [ExplorerController] owns navigation and SDK inspection.
/// - [TerminalInput] decodes terminal bytes into navigation intent.
/// - [ExplorerPresenter] prepares immutable presentation snapshots.
/// - [Renderer] displays those snapshots.
/// - [ExplorerTerminalHost] owns terminal modes and restoration.
///
/// The runner processes navigation actions sequentially.
/// An SDK inspection must finish before another action is applied.
///
/// The initial directory inspection happens before entering
/// interactive terminal mode. Its failure cannot leave the
/// terminal in raw-input or alternate-screen mode.
///
/// Subsequent inspections occur inside the guarded terminal
/// lifecycle. The host restores terminal state on failure.
///
/// No persistent Rudra session is created or modified.
/// No cleanup decisions or filesystem mutations occur.
///
/// Each runner instance supports exactly one invocation.
///
/// Example:
/// ```dart
/// final runner = ExplorerRunner(
///   controller: controller,
///   terminal: terminal,
///   renderer: renderer,
///   error_output: stderr,
/// );
///
/// final status = await runner.run();
/// ```
final class ExplorerRunner {
  /// Creates an interactive workflow from injected dependencies.
  ///
  /// [controller] provides SDK-backed read-only navigation.
  ///
  /// [terminal] supplies input, dimensions, output capabilities,
  /// and guarded terminal lifecycle management.
  ///
  /// [renderer] displays immutable Explorer presentation models.
  ///
  /// [error_output] receives terminal configuration diagnostics.
  ///
  /// [presenter] prepares the presentation viewport.
  ///
  /// Construction performs no inspection or terminal I/O.
  ExplorerRunner({
    required ExplorerController controller,
    required ExplorerTerminalHost terminal,
    required Renderer<ExplorerViewModel> renderer,
    required StringSink error_output,
    ExplorerPresenter presenter = const ExplorerPresenter(),
  })  : _controller = controller,
        _terminal = terminal,
        _renderer = renderer,
        _error_output = error_output,
        _presenter = presenter;

  /// Read-only navigation coordinator.
  final ExplorerController _controller;

  /// Terminal lifecycle and input boundary.
  final ExplorerTerminalHost _terminal;

  /// Backend-independent presentation renderer.
  final Renderer<ExplorerViewModel> _renderer;

  /// Destination for configuration diagnostics.
  final StringSink _error_output;

  /// Stateless Explorer presentation coordinator.
  final ExplorerPresenter _presenter;

  /// Whether this runner has already been invoked.
  bool _has_started = false;

  /// Number of fixed lines rendered by BareExplorerRenderer.
  static const int _fixed_frame_rows = 6;

  /// Spare row preventing the final newline from scrolling
  /// the alternate screen.
  static const int _terminal_safety_rows = 1;

  /// Minimum height required by the existing bare renderer.
  static const int _reserved_terminal_rows =
      _fixed_frame_rows + _terminal_safety_rows;

  /// Runs one interactive Explorer navigation session.
  ///
  /// The workflow first validates terminal capabilities.
  /// Unsupported terminals return
  /// [RudraExitCode.configuration_error] without inspecting
  /// the filesystem or changing terminal modes.
  ///
  /// The initial directory is inspected through [ExplorerController].
  /// A failure during this inspection propagates directly.
  ///
  /// Once initialized, the terminal host owns the interaction.
  /// The runner:
  /// - Renders the initial directory.
  /// - Consumes decoded keyboard actions sequentially.
  /// - Navigates through the existing controller.
  /// - Re-renders after presentation state changes.
  /// - Keeps the selected row within the visible viewport.
  /// - Resets scrolling when the directory changes.
  /// - Tracks incomplete observations across all visited directories.
  ///
  /// Normal termination occurs through Quit or input EOF.
  ///
  /// Returns:
  /// - [RudraExitCode.success] for complete observations.
  /// - [RudraExitCode.inspection_incomplete] if any visited
  ///   directory produced an incomplete SDK observation.
  /// - [RudraExitCode.configuration_error] for an unsupported
  ///   or initially undersized terminal.
  ///
  /// Unexpected SDK, input, rendering, and terminal errors
  /// propagate after terminal restoration is attempted.
  ///
  /// Process interruptions forwarded by the terminal host
  /// remain typed errors rather than successful exits.
  ///
  /// The controller is closed when a hosted interaction ends,
  /// including when an exception is thrown.
  ///
  /// Terminal resizing is reflected on the next render.
  /// A terminal becoming too short during interaction causes
  /// an explicit failure and guarded terminal restoration.
  ///
  /// Throws [StateError] when invoked more than once.
  ///
  /// No filesystem mutations or cleanup operations occur.
  Future<int> run() async {
    if (_has_started) {
      throw StateError(
        'ExplorerRunner supports only one invocation.',
      );
    }

    _has_started = true;

    if (!_terminal.is_interactive ||
        _terminal.terminal_rows < _reserved_terminal_rows) {
      _error_output.writeln(
        'Interactive Explorer requires a supported terminal '
        'with at least $_reserved_terminal_rows rows.',
      );

      return RudraExitCode.configuration_error.value;
    }

    // Inspect the starting directory before changing
    // terminal modes. Unexpected SDK errors propagate
    // without requiring terminal restoration.
    final initial_model = await _controller.start();

    var encountered_incomplete = initial_model.is_incomplete;

    try {
      return await _terminal.run_interactive<int>(() async {
        ExplorerModel current_model = initial_model;
        var first_visible_index = 0;

        /// Renders the current navigation snapshot.
        ///
        /// Viewport dimensions are evaluated for each render
        /// rather than cached at interaction startup.
        void render_current() {
          final rows = _terminal.terminal_rows;

          if (rows < _reserved_terminal_rows) {
            throw StateError(
              'Terminal became too small for Explorer rendering.',
            );
          }

          final visible_row_limit = rows - _reserved_terminal_rows;

          final view_model = _presenter.present(
            current_model,
            visible_row_limit: visible_row_limit,
            first_visible_index: first_visible_index,
          );

          _renderer.render(view_model);

          // Commit the viewport position only after rendering
          // succeeds. Navigation state itself remains owned
          // by ExplorerController.
          first_visible_index = view_model.first_visible_index;
        }

        render_current();

        final input = TerminalInput(
          source: _terminal.input_bytes,
        );

        await for (final key in input.read_keys()) {
          if (key == ExplorerKey.quit) {
            break;
          }

          final previous_model = current_model;

          // Only ExplorerController may change navigation state.
          // No terminal input is interpreted as a filesystem path.
          switch (key) {
            case ExplorerKey.up:
              current_model = _controller.move_selection(-1);

            case ExplorerKey.down:
              current_model = _controller.move_selection(1);

            case ExplorerKey.open:
              current_model = await _controller.open_selected();

            case ExplorerKey.back:
              current_model = await _controller.back();

            case ExplorerKey.quit:
              // Handled before the switch.
              break;
          }

          // Opening a regular file, a symbolic link, or
          // navigating back at the root returns the same
          // model. No redundant render is necessary.
          if (identical(previous_model, current_model)) {
            continue;
          }

          if (previous_model.current_directory.value !=
              current_model.current_directory.value) {
            first_visible_index = 0;
          }

          encountered_incomplete =
              encountered_incomplete || current_model.is_incomplete;

          render_current();
        }

        return encountered_incomplete
            ? RudraExitCode.inspection_incomplete.value
            : RudraExitCode.success.value;
      });
    } finally {
      // Closing the in-memory controller never modifies
      // filesystem content or persistent session state.
      //
      // The terminal host has already attempted restoration
      // before control reaches this finally block.
      final model = _controller.model;

      if (model != null && !model.is_closed && !_controller.is_loading) {
        _controller.quit();
      }
    }
  }
}
