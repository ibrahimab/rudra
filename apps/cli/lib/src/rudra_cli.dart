import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/about_cli_module.dart';
import 'rudra_cli_module.dart';
import 'rudra_exit_code.dart';

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
  /// Creates an empty CLI framework.
  ///
  /// [error_output] receives usage errors and defaults to stderr.
  ///
  /// No commands are registered automatically.
  RudraCli({StringSink? error_output})
      : _runner = CommandRunner<int>(
          'rudra',
          'Rudra - Interactive filesystem exploration and cleanup.',
        ),
        _error_output = error_output ?? stderr;

  /// Creates a CLI configured with the production modules.
  ///
  /// Development-only modules are deliberately excluded.
  factory RudraCli.product({StringSink? error_output}) {
    final cli = RudraCli(error_output: error_output);

    cli.register_module(AboutCliModule());

    return cli;
  }

  /// Underlying argument parser and command dispatcher.
  final CommandRunner<int> _runner;

  /// Output destination for usage errors.
  final StringSink _error_output;

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

  /// Executes the requested CLI command.
  ///
  /// Module registration becomes unavailable after this call.
  ///
  /// Returns the command's exit status or success for help output.
  /// Usage errors are mapped to [RudraExitCode.invalid_usage].
  ///
  /// Unexpected exceptions are allowed to propagate so their
  /// diagnostic information is not silently discarded.
  ///
  /// Throws [StateError] if called more than once.
  Future<int> run(List<String> arguments) async {
    if (_has_started) {
      throw StateError('CLI instance already executed.');
    }

    _has_started = true;

    try {
      final result = await _runner.run(arguments);

      return result ?? RudraExitCode.success.value;
    } on UsageException catch (error) {
      _error_output.writeln(error);

      return RudraExitCode.invalid_usage.value;
    }
  }
}
