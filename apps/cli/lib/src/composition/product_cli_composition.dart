import 'dart:io';

import 'package:rudra_host/rudra_host.dart';

import '../core/cli/rudra_exit_code.dart';

import '../features/about/cli/about_cli_module.dart';
import '../features/explorer/application/explorer_action_registry.dart';
import '../features/explorer/cli/explorer_cli_composition.dart';
import '../features/explorer/terminal/explorer_terminal_host.dart';
import '../features/filesystem/cli/filesystem_cli_module.dart';
import '../features/host/cli/host_cli_module.dart';
import '../features/welcome/composition/welcome_composition.dart';
import '../features/workflow/cli/workflow_cli_module.dart';
import '../features/workflow/explorer/workflow_explorer_contribution.dart';

import '../rudra_cli.dart';

import 'product_sdk_composition.dart';

/// Assembles production features around one invocation-owned SDK lifecycle.
///
/// [sdk_composition] optionally supplies an isolated SDK, starting directory
/// and endpoint. [output] and [error_output] receive user-facing presentation
/// and diagnostics. [explorer_terminal_host_factory] optionally supplies
/// Explorer's terminal, which owns interactive output.
///
/// Returns a CLI with registered product modules. Connection establishment
/// occurs on demand after argument validation. SDK disposal runs after command
/// completion, including interactive terminal restoration.
///
/// Example:
/// ```dart
/// final cli = compose_product_cli();
/// final status = await cli.run(['about']);
/// ```
RudraCli compose_product_cli({
  StringSink? output,
  StringSink? error_output,
  ProductSdkComposition? sdk_composition,
  ExplorerTerminalHost Function()? explorer_terminal_host_factory,
}) {
  final composition =
      sdk_composition ?? ProductSdkComposition.for_current_host();
  final presentation = output ?? stdout;
  final diagnostics = error_output ?? stderr;

  return RudraCli(
      error_output: diagnostics,
      run_default: compose_welcome(
        sdk_composition: composition,
        output: presentation,
        error_output: diagnostics,
      ).show,
      invoke: (dispatch) async {
        try {
          return await dispatch();
        } on CliHostUnavailableException catch (error) {
          diagnostics.writeln('Rudra Host unavailable: ${error.cause}');
          return RudraExitCode.host_unavailable.value;
        } finally {
          await composition.sdk.close();
        }
      },
    )
    ..register_module(AboutCliModule.product(output: presentation))
    ..register_module(
      HostCliModule(
        run_host: run_local_host,
        output: presentation,
        error_output: diagnostics,
      ),
    )
    ..register_module(
      FilesystemCliModule.product(
        sdk_composition: composition,
        output: presentation,
        error_output: diagnostics,
      ),
    )
    ..register_module(
      WorkflowCliModule.product(
        sdk_composition: composition,
        output: presentation,
        error_output: diagnostics,
      ),
    )
    ..register_module(
      compose_explorer_cli(
        sdk_composition: composition,
        action_registry: ExplorerActionRegistry([
          WorkflowExplorerContribution(composition.sdk.workflows),
        ]),
        error_output: diagnostics,
        create_terminal_host: explorer_terminal_host_factory,
      ),
    );
}
