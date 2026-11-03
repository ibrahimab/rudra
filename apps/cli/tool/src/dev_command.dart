import 'package:args/command_runner.dart';

/// Signature of a development command's executable action.
///
/// The returned integer becomes the command's process exit status.
/// A nonzero result indicates failure.
typedef DevelopmentAction = Future<int> Function();

/// Adapts a development action to Rudra's CLI command framework.
///
/// Development commands use the same command registration, argument
/// parsing, and error handling as production commands.
///
/// This class belongs to development tooling and must not be
/// imported by the production entrypoint.
///
/// Example:
/// ```dart
/// final command = DevCommand(
///   name: 'verify',
///   description: 'Execute verification.',
///   action: () async => 0,
/// );
/// ```
final class DevCommand extends Command<int> {
  /// Creates a development command.
  ///
  /// [name] is the command identifier.
  /// [description] appears in generated help.
  /// [action] performs the command's work and returns its exit status.
  DevCommand({
    required this.name,
    required this.description,
    required DevelopmentAction action,
  }) : _action = action;

  /// Identifier used to invoke the command.
  @override
  final String name;

  /// Description displayed by the command runner.
  @override
  final String description;

  /// Action executed when the command is invoked.
  final DevelopmentAction _action;

  /// Invokes the configured development action.
  ///
  /// Errors that are not handled by the action propagate to the
  /// command runner and retain their original stack traces.
  @override
  Future<int> run() => _action();
}
