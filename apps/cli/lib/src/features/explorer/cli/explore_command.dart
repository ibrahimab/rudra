import 'package:args/command_runner.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../application/explorer_runner.dart';

/// Starts the interactive, read-only filesystem Explorer.
///
/// The command accepts an optional target-native starting
/// directory and delegates execution to an injected
/// [ExplorerRunner] factory.
///
/// The factory is supplied by application composition.
/// The command does not construct SDK instances, native
/// adapters, renderers, or terminal hosts.
///
/// With no directory argument, the configured working
/// directory is used unchanged.
///
/// Explicit paths retain their target-native spelling.
/// Absolute-path requirements are enforced by the configured
/// SDK target rather than by interpreting paths using the
/// frontend host's filesystem conventions.
///
/// No persistent sessions, cleanup plans, or destructive
/// filesystem operations are created by this command.
///
/// CLI usage:
/// ```text
/// rudra explore
/// rudra explore /absolute/directory
/// ```
///
/// Example:
/// ```dart
/// final command = ExploreCommand(
///   working_directory: TargetPath('/workspace'),
///   create_runner: (directory) => create_explorer(directory),
/// );
/// ```
final class ExploreCommand extends Command<int> {
  /// Creates an Explorer command with injected dependencies.
  ///
  /// [working_directory] is the default target-native root.
  ///
  /// [create_runner] constructs a fresh Explorer workflow
  /// for the requested directory. It is invoked only after
  /// command arguments have been validated.
  ///
  /// The caller must supply a factory bound to the same
  /// configured SDK target as [working_directory].
  ///
  /// Construction does not invoke [create_runner] or perform
  /// any filesystem or terminal operations.
  ExploreCommand({
    required TargetPath working_directory,
    required ExplorerRunner Function(TargetPath) create_runner,
  }) : _working_directory = working_directory,
       _create_runner = create_runner;

  /// Public command identifier.
  @override
  String get name => 'explore';

  /// Description displayed in CLI help.
  @override
  String get description =>
      'Interactively explore a filesystem directory (read-only).';

  /// Usage displayed by the command parser.
  @override
  String get invocation => 'rudra explore [absolute-directory]';

  /// Default directory associated with the configured SDK.
  final TargetPath _working_directory;

  /// Factory supplied by the CLI application composition.
  final ExplorerRunner Function(TargetPath) _create_runner;

  /// Validates arguments and starts one Explorer interaction.
  ///
  /// Accepts zero or one positional directory argument.
  ///
  /// Multiple arguments and an empty explicit path produce
  /// [UsageException], which the existing CLI framework maps
  /// to [RudraExitCode.invalid_usage].
  ///
  /// Invalid [TargetPath] values also produce a usage error.
  ///
  /// With no argument, the original [working_directory]
  /// instance is passed to the runner factory.
  ///
  /// A valid explicit path is not normalized, expanded, or
  /// interpreted using host-specific path rules.
  ///
  /// The runner owns terminal capability checks, navigation,
  /// SDK inspection, rendering, and interaction exit status.
  ///
  /// Runner errors propagate without being converted into
  /// successful command completion.
  ///
  /// No filesystem mutation or cleanup authorization occurs.
  @override
  Future<int> run() async {
    final arguments = argResults?.rest ?? const <String>[];

    if (arguments.length > 1) {
      throw UsageException('Expected at most one directory argument.', usage);
    }

    if (arguments.isNotEmpty && arguments.single.isEmpty) {
      throw UsageException('The directory argument must not be empty.', usage);
    }

    TargetPath directory = _working_directory;

    if (arguments.isNotEmpty) {
      try {
        directory = TargetPath(arguments.single);
      } on ArgumentError {
        throw UsageException(
          'The directory argument is not a valid target path.',
          usage,
        );
      }
    }

    // Composition supplies a fresh runner, controller,
    // renderer, and terminal host for this invocation.
    //
    // No SDK or terminal operations occur in this command.
    final runner = _create_runner(directory);

    return runner.run();
  }
}
