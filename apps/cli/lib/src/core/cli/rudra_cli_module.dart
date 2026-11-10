import 'package:args/command_runner.dart';

/// Contract for contributing commands to the Rudra CLI.
///
/// A CLI module integrates application functionality into the shared
/// command framework without owning the process lifecycle.
///
/// Implementations may contribute one or more commands. Each command
/// is registered by [RudraCli] during application composition.
///
/// Module registration must be free of filesystem modifications,
/// network requests, and command execution.
///
/// Modules should construct command objects and inject their required
/// dependencies, leaving actual work until a command is invoked.
///
/// The underlying SDK must not depend on this interface. CLI modules
/// serve as adapters between SDK functionality and the command layer.
///
/// Example:
/// ```dart
/// final cli = RudraCli();
/// cli.register_module(ExplorerCliModule());
/// ```
abstract interface class RudraCliModule {
  /// Stable identifier used to prevent duplicate module registration.
  ///
  /// Identifiers must be nonblank and unique within a CLI instance.
  ///
  /// Example: `rudra.product.explorer`.
  String get module_id;

  /// Creates the commands contributed by this module.
  ///
  /// Implementations must return at least one command.
  ///
  /// Command names and aliases must not conflict with commands
  /// registered by other modules.
  ///
  /// This method must not execute the contributed commands or
  /// perform destructive actions.
  Iterable<Command<int>> create_commands();
}
