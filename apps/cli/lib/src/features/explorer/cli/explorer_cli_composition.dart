import '../../../composition/product_sdk_composition.dart';
import '../../../core/rendering/bare/ansi_text.dart';
import '../../../core/rendering/theme.dart';

import '../application/explorer_action_registry.dart';
import '../application/explorer_controller.dart';
import '../application/explorer_runner.dart';
import '../presentation/bare_explorer_renderer.dart';
import '../terminal/dart_explorer_terminal_host.dart';
import '../terminal/explorer_terminal_host.dart';

import 'explorer_cli_module.dart';

/// Assembles the Explorer command for the given [sdk_composition].
///
/// The composition supplies the default root and borrows an authenticated SDK
/// after argument validation. [action_registry] supplies the product's chosen
/// contributions. [error_output] receives diagnostics. [create_terminal_host]
/// optionally supplies an isolated terminal after controller initialization.
///
/// Returns the feature module. Connection and initialization errors propagate
/// when the command executes. SDK disposal belongs to the caller.
///
/// Example:
/// ```dart
/// cli.register_module(compose_explorer_cli(
///   sdk_composition: composition,
///   action_registry: actions,
///   error_output: stderr,
/// ));
/// ```
ExplorerCliModule compose_explorer_cli({
  required ProductSdkComposition sdk_composition,
  ExplorerActionRegistry? action_registry,
  required StringSink error_output,
  ExplorerTerminalHost Function()? create_terminal_host,
}) => ExplorerCliModule(
  working_directory: sdk_composition.working_directory,
  create_runner: (directory) async {
    final controller = await ExplorerController.create(
      sdk: await sdk_composition.connect(),
      starting_directory: directory,
      action_registry: action_registry,
    );
    final terminal = (create_terminal_host ?? DartExplorerTerminalHost.new)();
    return ExplorerRunner(
      controller: controller,
      terminal: terminal,
      renderer: BareExplorerRenderer(
        output: terminal.output,
        terminal_columns: () => terminal.terminal_columns,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: true),
        redraw_screen: true,
      ),
      error_output: error_output,
    );
  },
);
