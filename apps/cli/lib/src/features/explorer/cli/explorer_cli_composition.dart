import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../core/rendering/bare/ansi_text.dart';
import '../../../core/rendering/theme.dart';

import '../../workflow/explorer/workflow_explorer_composition.dart';

import '../application/explorer_action_registry.dart';
import '../application/explorer_controller.dart';
import '../application/explorer_runner.dart';
import '../presentation/bare_explorer_renderer.dart';
import '../presentation/explorer_view_model.dart';
import '../terminal/dart_explorer_terminal_host.dart';
import '../terminal/explorer_terminal_host.dart';

import 'explorer_cli_module.dart';

/// Composes Explorer for the production CLI.
///
/// [connect] establishes the shared SDK session after argument validation.
/// [working_directory] supplies the default navigation root. [error_output]
/// receives diagnostics. [create_terminal_host] optionally supplies an
/// isolated terminal. Its factory runs only after verified state is available.
///
/// Returns the registered feature module. Runner initialization and state
/// read failures propagate through its command execution.
///
/// Example:
/// ```dart
/// cli.register_module(compose_explorer_cli(
///   connect: composition.connect,
///   working_directory: composition.working_directory,
///   error_output: stderr,
/// ));
/// ```
ExplorerCliModule compose_explorer_cli({
  required Future<RudraSdk> Function() connect,
  required TargetPath working_directory,
  required StringSink error_output,
  ExplorerTerminalHost Function()? create_terminal_host,
}) => ExplorerCliModule(
  working_directory: working_directory,
  create_runner: (directory) async {
    final sdk = await connect();
    final workflows = WorkflowExplorerComposition(sdk);

    // Load verified workflow state before constructing the terminal host.
    await workflows.refresh();

    final terminal = (create_terminal_host ?? DartExplorerTerminalHost.new)();
    return ExplorerRunner(
      controller: ExplorerController(sdk: sdk, starting_directory: directory),
      terminal: terminal,
      renderer: BareExplorerRenderer(
        output: terminal.output,
        terminal_columns: () => terminal.terminal_columns,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: true),
        redraw_screen: true,
      ),
      error_output: error_output,
      create_view_model:
          (
            explorer, {
            required visible_row_limit,
            required first_visible_index,
          }) => ExplorerViewModel.from_navigation(
            explorer: explorer,
            workflows: workflows.view_model,
            visible_row_limit: visible_row_limit,
            first_visible_index: first_visible_index,
          ),
      refresh_application_state: workflows.refresh,
      action_registry: ExplorerActionRegistry([workflows.contribution()]),
    );
  },
);
