import 'package:args/command_runner.dart';

import 'dev_tasks.dart';

/// Runs Rudra's repository quality checks.
///
/// The command verifies dependencies, formatting, static analysis,
/// and automated tests.
///
/// By default, checks cover the complete workspace.
/// The optional package argument scopes formatting, analysis,
/// and testing to a named workspace member.
///
/// Dependency resolution remains workspace-wide because Pub
/// Workspaces use shared dependency resolution.
///
/// Examples:
/// ```bash
/// ./rudra check
/// ./rudra check --package rudra_target_contracts
/// ```
final class CheckCommand extends Command<int> {
  /// Creates the check command and its options.
  CheckCommand(this._tasks) {
    argParser.addOption(
      'package',
      abbr: 'p',
      help: 'Restrict checks to a workspace package.',
      valueHelp: 'package_name',
    );
  }

  /// Repository task service performing the checks.
  final DevTasks _tasks;

  /// CLI command identifier.
  @override
  String get name => 'check';

  /// Description displayed in command help.
  @override
  String get description =>
      'Verify dependencies, formatting, analysis, and tests.';

  /// Executes the repository quality gate.
  ///
  /// Returns a successful status only when every selected stage passes.
  ///
  /// Throws [UsageException] for unsupported positional arguments.
  @override
  Future<int> run() {
    final results = argResults!;

    if (results.rest.isNotEmpty) {
      throw UsageException(
        'Unexpected positional arguments: ${results.rest.join(' ')}',
        usage,
      );
    }

    return _tasks.check(
      package_name: results['package'] as String?,
    );
  }
}
