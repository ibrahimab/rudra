import 'package:args/command_runner.dart';

import 'dev_tasks.dart';

/// Executes test suites belonging to Rudra workspace packages.
///
/// Supports running all packages or narrowing execution using package
/// name, test name, inclusion tags, and exclusion tags.
///
/// The command discovers packages through the Dart workspace.
/// Packages do not need to register test suites with the CLI.
///
/// Filtering is delegated to Dart's existing test runner rather
/// than implementing a separate test matching algorithm.
///
/// Examples:
/// ```bash
/// ./rudra test
/// ./rudra test --package rudra_sdk
/// ./rudra test --name TargetDescriptor
/// ./rudra test --tags integration
/// ./rudra test --exclude-tags slow
/// ```
final class TestCommand extends Command<int> {
  /// Creates the test command with its repository task dependency.
  TestCommand(this._tasks) {
    argParser
      ..addOption(
        'package',
        abbr: 'p',
        help: 'Run tests from one workspace package.',
        valueHelp: 'package_name',
      )
      ..addOption(
        'name',
        abbr: 'n',
        help: 'Filter test names using a regular expression.',
        valueHelp: 'pattern',
      )
      ..addOption(
        'tags',
        help: 'Run tests matching a tag selector.',
        valueHelp: 'selector',
      )
      ..addOption(
        'exclude-tags',
        help: 'Exclude tests matching a tag selector.',
        valueHelp: 'selector',
      );
  }

  /// Repository task service used to execute tests.
  final DevTasks _tasks;

  /// Name registered with the Rudra CLI.
  @override
  String get name => 'test';

  /// Description shown in generated help.
  @override
  String get description => 'Run workspace tests with optional filters.';

  /// Executes matching test suites.
  ///
  /// The test command accepts no positional arguments.
  ///
  /// Throws [UsageException] when unexpected positional arguments
  /// are provided.
  ///
  /// Returns the exit status supplied by [DevTasks.test].
  @override
  Future<int> run() {
    final results = argResults!;

    if (results.rest.isNotEmpty) {
      throw UsageException(
        'Unexpected positional arguments: ${results.rest.join(' ')}',
        usage,
      );
    }

    return _tasks.test(
      package_name: results['package'] as String?,
      test_name: results['name'] as String?,
      tags: results['tags'] as String?,
      exclude_tags: results['exclude-tags'] as String?,
    );
  }
}
