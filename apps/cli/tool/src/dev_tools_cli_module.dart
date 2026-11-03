import 'package:args/command_runner.dart';
import 'package:rudra_cli/rudra_cli.dart';

import 'check_command.dart';
import 'dev_command.dart';
import 'dev_tasks.dart';
import 'test_command.dart';

/// Integrates repository development tools into the Rudra CLI.
///
/// This module adds verification, formatting, analysis, testing,
/// and release-build commands to the shared command framework.
///
/// It must only be imported from development composition code.
/// The production entrypoint must never depend on this module.
///
/// The module receives an initialized [DevTasks] instance and
/// delegates all repository operations to that service.
///
/// Example:
/// ```dart
/// cli.register_module(DevToolsCliModule(tasks));
/// ```
final class DevToolsCliModule implements RudraCliModule {
  /// Creates the development CLI module.
  ///
  /// [tasks] supplies the repository operations executed by commands.
  const DevToolsCliModule(this._tasks);

  /// Repository development operations.
  final DevTasks _tasks;

  /// Unique identifier used for registration validation.
  @override
  String get module_id => 'rudra.development.tools';

  /// Creates the commands available to development builds.
  ///
  /// No command actions are executed during registration.
  @override
  Iterable<Command<int>> create_commands() {
    return [
      CheckCommand(_tasks),
      TestCommand(_tasks),
      DevCommand(
        name: 'analyze',
        description: 'Run static analysis.',
        action: _tasks.analyze,
      ),
      DevCommand(
        name: 'format',
        description: 'Format repository Dart source files.',
        action: _tasks.format,
      ),
      DevCommand(
        name: 'build',
        description: 'Build and verify the production executable.',
        action: _tasks.build,
      ),
    ];
  }
}
