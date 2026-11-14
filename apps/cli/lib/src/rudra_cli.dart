import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:rudra_sdk/rudra_sdk.dart' show application_name;

import 'composition/product_sdk_composition.dart';

import 'core/cli/rudra_cli_module.dart';
import 'core/cli/rudra_exit_code.dart';

import 'core/rendering/bare/ansi_text.dart';
import 'core/rendering/theme.dart';

import 'features/about/cli/about_cli_module.dart';
import 'features/about/presentation/bare_about_renderer.dart';

import 'features/filesystem/cli/filesystem_cli_module.dart';
import 'features/filesystem/presentation/bare_filesystem_renderer.dart';

import 'features/welcome/application/welcome_controller.dart';
import 'features/welcome/presentation/bare_welcome_renderer.dart';

import 'features/explorer/presentation/bare_explorer_renderer.dart';

import 'features/explorer/terminal/dart_explorer_terminal_host.dart';
import 'features/explorer/terminal/explorer_terminal_host.dart';

import 'features/explorer/cli/explorer_cli_module.dart';

import 'features/explorer/application/explorer_controller.dart';
import 'features/explorer/application/explorer_runner.dart';

/// Coordinates command registration and execution for Rudra.
///
/// The CLI framework owns a single command runner and manages the
/// lifecycle of registered modules.
///
/// Product and development applications use the same framework,
/// but register different sets of modules.
///
/// Registration is allowed only before command execution begins.
///
/// Each instance supports one command invocation.
///
/// Example:
/// ```dart
/// final cli = RudraCli.product();
/// final status = await cli.run(['about']);
/// ```
final class RudraCli {
  /// Creates a CLI framework.
  ///
  /// [error_output] receives usage diagnostics.
  ///
  /// [welcome_controller] optionally handles an invocation
  /// without command-line arguments.
  ///
  /// When no controller is supplied, the existing command
  /// runner behavior remains unchanged.
  ///
  /// Construction registers no commands and performs no
  /// filesystem operations.
  RudraCli({
    StringSink? error_output,
    WelcomeController? welcome_controller,
  })  : _runner = CommandRunner<int>(
          'rudra',
          'Rudra - Interactive filesystem exploration and cleanup.',
        ),
        _error_output = error_output ?? stderr,
        _welcome_controller = welcome_controller;

  /// Creates a production CLI with supported application modules.
  ///
  /// The application composition boundary owns:
  /// - SDK and target-adapter selection.
  /// - Starting-directory configuration.
  /// - Concrete renderer construction.
  /// - Terminal host construction.
  /// - Controller, runner, and command-module assembly.
  ///
  /// A supplied [target_composition] overrides local target
  /// discovery for isolated application testing.
  ///
  /// [output] receives existing welcome and filesystem command
  /// presentation. Their established output formats are unchanged.
  ///
  /// Interactive Explorer presentation uses the output destination
  /// supplied by its terminal host. This avoids writing terminal
  /// control sequences into an unrelated output sink.
  ///
  /// [error_output] receives CLI usage and inspection diagnostics.
  ///
  /// [explorer_terminal_host_factory] optionally overrides the
  /// production terminal host constructor.
  ///
  /// The factory is invoked only when the Explorer command runs.
  /// This supports deterministic interaction tests without
  /// modifying real terminal modes.
  ///
  /// Existing non-interactive output remains unstyled.
  /// Interactive Explorer uses the ANSI theme and bare renderer.
  ///
  /// Development-only commands are not registered.
  ///
  /// Construction does not inspect or modify filesystem content
  /// or change terminal settings.
  factory RudraCli.product({
    StringSink? output,
    StringSink? error_output,
    ProductSdkComposition? target_composition,
    ExplorerTerminalHost Function()? explorer_terminal_host_factory,
  }) {
    // Resolve the target once so that all application
    // components share the same SDK and starting directory.
    final composition =
        target_composition ?? ProductSdkComposition.for_current_host();

    // Resolve output destinations once at the application
    // boundary rather than inside individual controllers.
    final presentation_output = output ?? stdout;
    final diagnostic_output = error_output ?? stderr;

    // Select the concrete welcome rendering backend here.
    // Feature controllers depend only on Renderer<TViewModel>.
    final welcome_renderer = BareWelcomeRenderer(
      output: presentation_output,
      error_output: diagnostic_output,
    );

    final welcome_controller = WelcomeController(
      sdk: composition?.sdk,
      starting_directory: composition?.working_directory,
      renderer: welcome_renderer,
    );

    final cli = RudraCli(
      error_output: diagnostic_output,
      welcome_controller: welcome_controller,
    );

    // About uses the same application-owned output destination
    // as other non-interactive product commands.
    //
    // The command receives only the rendering contract.
    // It never writes directly to stdout.
    final about_renderer = BareAboutRenderer(
      output: presentation_output,
    );

    cli.register_module(
      AboutCliModule(
        product_name: application_name,
        renderer: about_renderer,
      ),
    );

    if (composition != null) {
      // The application composition boundary selects the
      // concrete filesystem rendering implementation.
      //
      // Commands receive a backend-independent
      // Renderer<FilesystemViewModel>.
      //
      // The concrete renderer independently presents
      // directory entries and inspection diagnostics.
      //
      // Compact output intentionally remains plain text.
      final filesystem_renderer = BareFilesystemRenderer(
        output: presentation_output,
        error_output: diagnostic_output,
      );

      cli.register_module(
        FilesystemCliModule(
          sdk: composition.sdk,
          working_directory: composition.working_directory,
          renderer: filesystem_renderer,
        ),
      );

      // Construct terminal hosts lazily so ordinary commands
      // never probe or modify interactive terminal state.
      final create_terminal_host =
          explorer_terminal_host_factory ?? () => DartExplorerTerminalHost();

      cli.register_module(
        ExplorerCliModule(
          working_directory: composition.working_directory,
          create_runner: (directory) {
            final terminal = create_terminal_host();

            // All filesystem observations pass through the
            // configured public Rudra SDK.
            //
            // The original requested directory is preserved.
            final controller = ExplorerController(
              sdk: composition.sdk,
              starting_directory: directory,
            );

            // Interactive presentation uses the same output
            // destination owned by the terminal host.
            //
            // The renderer never changes terminal modes.
            final renderer = BareExplorerRenderer(
              output: terminal.output,
              terminal_columns: () => terminal.terminal_columns,
              theme: TerminalTheme.ansi,
              ansi_text: const AnsiText(enabled: true),
              redraw_screen: true,
            );

            return ExplorerRunner(
              controller: controller,
              terminal: terminal,
              renderer: renderer,
              error_output: diagnostic_output,
            );
          },
        ),
      );
    }

    return cli;
  }

  /// Underlying argument parser and command dispatcher.
  final CommandRunner<int> _runner;

  /// Output destination for usage errors.
  final StringSink _error_output;

  /// Optional controller for the root welcome screen.
  ///
  /// Only application compositions explicitly supplying
  /// a controller enable welcome-screen rendering.
  final WelcomeController? _welcome_controller;

  /// Identifiers of registered modules.
  final Set<String> _module_ids = <String>{};

  /// Tracks whether execution has started.
  bool _has_started = false;

  /// Returns an immutable set of registered command names.
  Set<String> get command_names =>
      Set<String>.unmodifiable(_runner.commands.keys);

  /// Returns an immutable set of registered module identifiers.
  Set<String> get module_ids => Set<String>.unmodifiable(_module_ids);

  /// Registers all commands contributed by [module].
  ///
  /// Validates the module identifier, command names, and aliases
  /// before modifying the command registry.
  ///
  /// Throws [StateError] if:
  /// - Execution has already started.
  /// - The module identifier is blank or duplicated.
  /// - The module contributes no commands.
  /// - A command name or alias conflicts with an existing name.
  ///
  /// Registration must not perform destructive operations.
  void register_module(RudraCliModule module) {
    if (_has_started) {
      throw StateError(
        'Cannot register modules after execution has started.',
      );
    }

    final module_id = module.module_id;

    if (module_id.trim().isEmpty) {
      throw StateError('Module identifiers must not be blank.');
    }

    if (_module_ids.contains(module_id)) {
      throw StateError('Module already registered: $module_id');
    }

    // Materialize commands once to avoid re-evaluating lazy iterables.
    final commands = module.create_commands().toList(growable: false);

    if (commands.isEmpty) {
      throw StateError('Module has no commands: $module_id');
    }

    // Command names and aliases share one namespace.
    final occupied_names = <String>{
      'help',
      ..._runner.commands.keys,
    };

    for (final command in _runner.commands.values) {
      occupied_names.addAll(command.aliases);
    }

    // Validate the entire contribution before registering any command.
    for (final command in commands) {
      final names = <String>[
        command.name,
        ...command.aliases,
      ];

      for (final name in names) {
        if (name.trim().isEmpty) {
          throw StateError('Blank command name in $module_id');
        }

        if (!occupied_names.add(name)) {
          throw StateError(
            'Duplicate command name or alias: $name',
          );
        }
      }
    }

    for (final command in commands) {
      _runner.addCommand(command);
    }

    _module_ids.add(module_id);
  }

  /// Executes a single CLI invocation.
  ///
  /// When no arguments are supplied and a welcome controller
  /// is configured, renders the welcome screen and returns
  /// [RudraExitCode.success].
  ///
  /// Explicit commands continue through the existing
  /// CommandRunner dispatch mechanism.
  ///
  /// Usage errors return [RudraExitCode.invalid_usage].
  ///
  /// Unexpected errors propagate to the caller.
  ///
  /// An instance cannot be executed more than once.
  ///
  /// Throws [StateError] for repeated invocation.
  ///
  /// No filesystem modifications are performed by dispatch.
  Future<int> run(List<String> arguments) async {
    if (_has_started) {
      throw StateError('CLI instance already executed.');
    }

    _has_started = true;

    // The welcome screen is the application's root view,
    // not another filesystem operation or SDK service.
    if (arguments.isEmpty && _welcome_controller != null) {
      return await _welcome_controller.show();
    }

    try {
      final result = await _runner.run(arguments);

      return result ?? RudraExitCode.success.value;
    } on UsageException catch (error) {
      _error_output.writeln(error);

      return RudraExitCode.invalid_usage.value;
    }
  }
}
