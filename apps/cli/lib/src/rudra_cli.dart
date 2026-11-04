import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/about_cli_module.dart';
import 'commands/filesystem_cli_module.dart';

import 'composition/product_sdk_composition.dart';

import 'rudra_cli_module.dart';
import 'rudra_exit_code.dart';

import 'presentation/welcome/welcome_controller.dart';

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
  /// The composition boundary supplies an SDK configured with
  /// the available target adapter.
  ///
  /// A supplied [target_composition] overrides local target
  /// discovery, allowing isolated application tests.
  ///
  /// The welcome controller receives the same target composition
  /// used by the filesystem commands.
  ///
  /// [output] receives filesystem and welcome-screen output.
  /// [error_output] receives usage and inspection diagnostics.
  ///
  /// Development-only commands are never registered here.
  ///
  /// No filesystem inspection or cleanup occurs during
  /// application construction.
  factory RudraCli.product({
    StringSink? output,
    StringSink? error_output,
    ProductSdkComposition? target_composition,
  }) {
    // Resolve the target once so that every CLI component
    // observes the same SDK instance and starting directory.
    final composition =
        target_composition ?? ProductSdkComposition.for_current_host();

    final cli = RudraCli(
      error_output: error_output,
      welcome_controller: WelcomeController(
        composition: composition,
        output: output ?? stdout,
      ),
    );

    cli.register_module(AboutCliModule());

    if (composition != null) {
      cli.register_module(
        FilesystemCliModule(
          sdk: composition.sdk,
          working_directory: composition.working_directory,
          output: output,
          error_output: error_output,
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
      _welcome_controller.show();

      return RudraExitCode.success.value;
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
