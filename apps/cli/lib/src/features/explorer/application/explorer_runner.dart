import '../../../core/cli/rudra_exit_code.dart';
import '../../../core/rendering/renderer.dart';

import 'explorer_controller.dart';
import 'explorer_model.dart';
import 'explorer_action_registry.dart';

import '../terminal/explorer_terminal_host.dart';
import '../presentation/explorer_view_model.dart';
import '../terminal/terminal_input.dart';
import '../terminal/terminal_key.dart';

/// Builds an Explorer presentation from a navigation snapshot.
///
/// [explorer] supplies the current directory and selection state.
///
/// [visible_row_limit] is the number of rows available for directory
/// entries after fixed screen elements have been reserved.
///
/// [first_visible_index] is the requested scroll position.
///
/// Returns a complete, immutable [ExplorerViewModel].
typedef ExplorerViewModelBuilder = ExplorerViewModel Function(
  ExplorerModel explorer, {
  required int visible_row_limit,
  required int first_visible_index,
});

/// Coordinates one interactive Explorer invocation.
///
/// The runner connects independently owned components:
/// - [ExplorerController] owns read-only filesystem navigation.
/// - [TerminalInput] decodes physical terminal keys.
/// - [ExplorerActionRegistry] resolves contributed actions.
/// - [ExplorerViewModelBuilder] creates immutable UI snapshots.
/// - [Renderer] displays those snapshots.
/// - [ExplorerTerminalHost] owns terminal mode restoration.
///
/// The runner understands only built-in navigation, Quit,
/// and generic action dispatch. It must not contain
/// feature-specific workflow branches or application services.
///
/// Registered actions execute sequentially. An asynchronous
/// action must complete before another key is dispatched.
///
/// The runner does not itself create workflow events,
/// open persistence stores or authorize filesystem cleanup.
/// A registered feature may invoke an explicit application
/// operation when the user activates its shortcut.
///
/// Initial filesystem inspection occurs before entering
/// interactive terminal mode. Failure therefore cannot
/// leave the terminal in a changed mode.
///
/// Once interaction begins, failures propagate through the
/// guarded terminal lifecycle, which attempts restoration.
///
/// Navigation, rendering, and Quit never implicitly submit
/// application commands.
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
///   action_registry: registry,
/// );
///
/// final exit_code = await runner.run();
/// ```
final class ExplorerRunner {
  /// Creates an Explorer interaction coordinator.
  ///
  /// [controller] owns SDK-backed filesystem navigation.
  ///
  /// [terminal] provides input, terminal dimensions, and
  /// guarded terminal lifecycle management.
  ///
  /// [renderer] renders complete Explorer view models.
  ///
  /// [error_output] receives terminal configuration diagnostics.
  ///
  /// [create_view_model] builds the presentation snapshot for
  /// the current navigation state and available viewport.
  ///
  /// [refresh_application_state] optionally reloads authoritative
  /// application state after a successfully executed action.
  ///
  /// [action_registry] supplies the registered keyboard actions.
  /// When omitted, only built-in navigation and Quit are available.
  ///
  /// Construction does not begin filesystem inspection or
  /// interactive terminal operation.
  ///
  /// Example:
  /// ```dart
  /// final runner = ExplorerRunner(
  ///   controller: controller,
  ///   terminal: terminal,
  ///   renderer: renderer,
  ///   error_output: stderr,
  ///   create_view_model: create_view_model,
  ///   action_registry: registry,
  /// );
  /// ```
  ExplorerRunner({
    required ExplorerController controller,
    required ExplorerTerminalHost terminal,
    required ViewportRenderer<ExplorerViewModel> renderer,
    required StringSink error_output,
    required ExplorerViewModelBuilder create_view_model,
    Future<void> Function()? refresh_application_state,
    ExplorerActionRegistry? action_registry,
  }) : _controller = controller,
       _terminal = terminal,
       _renderer = renderer,
       _error_output = error_output,
       _create_view_model = create_view_model,
       _refresh_application_state = refresh_application_state,
       _action_registry = action_registry ?? ExplorerActionRegistry(const []);

  /// Controller responsible for filesystem navigation.
  final ExplorerController _controller;

  /// Interactive terminal lifecycle and input provider.
  final ExplorerTerminalHost _terminal;

  /// Renderer for complete Explorer presentation snapshots.
  final ViewportRenderer<ExplorerViewModel> _renderer;

  /// Output destination for terminal configuration diagnostics.
  final StringSink _error_output;

  /// Constructs the current Explorer view model.
  ///
  /// Invoked on each render using the latest navigation state
  /// and terminal viewport dimensions.
  final ExplorerViewModelBuilder _create_view_model;

  /// Reloads confirmed application state after action completion.
  ///
  /// The callback is awaited before the next presentation is
  /// built. Errors propagate through terminal restoration.
  final Future<void> Function()? _refresh_application_state;

  /// Whether this runner has already been invoked.
  bool _has_started = false;

  /// Spare row preventing the final newline from scrolling
  /// the terminal's alternate screen.
  static const int _terminal_safety_rows = 1;

  /// Immutable registration of Explorer keyboard actions.
  ///
  /// Shortcut resolution uses the current physical character.
  /// Actions are invoked sequentially.
  final ExplorerActionRegistry _action_registry;

  /// Terminal rows reserved outside the scrollable viewport.
  ///
  /// Fixed presentation height comes from the injected renderer,
  /// which owns its layout implementation.
  ///
  /// The terminal safety row is separate from the widget tree
  /// because it protects terminal lifecycle behavior.
  ///
  /// The value is evaluated when required, allowing a renderer
  /// to adjust its layout contract between frames.
  ///
  /// Throws [StateError] if the renderer reports an invalid
  /// negative fixed height.
  int get _reserved_terminal_rows {
    final fixed_rows = _renderer.fixed_rows;

    if (fixed_rows < 0) {
      throw StateError('Explorer renderer reported a negative fixed height.');
    }

    return fixed_rows + _terminal_safety_rows;
  }

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
      throw StateError('ExplorerRunner supports only one invocation.');
    }

    _has_started = true;

    final required_rows = _reserved_terminal_rows;

    if (!_terminal.is_interactive || _terminal.terminal_rows < required_rows) {
      _error_output.writeln(
        'Interactive Explorer requires a supported terminal '
        'with at least $required_rows rows.',
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

          final reserved_rows = _reserved_terminal_rows;

          if (rows < reserved_rows) {
            throw StateError(
              'Terminal became too small for Explorer rendering.',
            );
          }

          final visible_row_limit = rows - reserved_rows;

          // Construct the screen from the latest navigation and
          // application snapshots at the current terminal size.
          final view_model = _create_view_model(
            current_model,
            visible_row_limit: visible_row_limit,
            first_visible_index: first_visible_index,
          );

          _renderer.render(view_model);

          // Commit the viewport position only after rendering
          // succeeds. Navigation state itself remains owned
          // by ExplorerController.
          first_visible_index = view_model.directory.first_visible_index;
        }

        render_current();

        final input = TerminalInput(source: _terminal.input_bytes);

        await for (final key in input.read_keys()) {
          // Raw Ctrl+C is a controlled exit request.
          // OS-generated SIGINT remains a typed terminal error.
          if (key == TerminalSpecialKey.interrupt) {
            break;
          }

          if (key is TerminalCharacterKey) {
            // Quit is an Explorer lifecycle operation, not a
            // contributed application action.
            if (key.character.toLowerCase() == 'q') {
              break;
            }

            // Resolve the physical shortcut through the
            // registered action index.
            final action = _action_registry.resolve(key.character);

            if (action == null) {
              continue;
            }

            // Complete and validate the requested operation
            // before refreshing the displayed application state.
            await action.execute(current_model);

            final refresh = _refresh_application_state;

            if (refresh != null) {
              await refresh();
            }

            // Build the next frame from the refreshed snapshot.
            render_current();
            continue;
          }

          final previous_model = current_model;

          // Only ExplorerController owns navigation transitions.
          // Terminal keys are never interpreted as paths.
          if (key == TerminalSpecialKey.up) {
            current_model = _controller.move_selection(-1);
          } else if (key == TerminalSpecialKey.down) {
            current_model = _controller.move_selection(1);
          } else if (key == TerminalSpecialKey.enter) {
            current_model = await _controller.open_selected();
          } else if (key == TerminalSpecialKey.left ||
              key == TerminalSpecialKey.backspace) {
            current_model = await _controller.back();
          } else {
            continue;
          }

          // No navigation change means no redundant render.
          if (identical(previous_model, current_model)) {
            continue;
          }

          // Entering or leaving a directory resets its viewport.
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
