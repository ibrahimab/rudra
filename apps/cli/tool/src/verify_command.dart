import 'package:args/command_runner.dart';

import 'dev_tasks.dart';

/// Short aliases for Rudra workspace packages.
///
/// Full package names remain supported without registration.
const Map<String, String> _package_aliases = {
  'cli': 'rudra_cli',
  'sdk': 'rudra_sdk',
  'sqlite': 'rudra_persistence_sqlite',
  'contracts': 'rudra_target_contracts',
  'macos': 'rudra_target_macos',
};

/// Resolves a verification target to its workspace package name.
///
/// The `all` target selects the complete workspace.
/// Unknown names pass through for authoritative workspace
/// validation by [DevTasks].
///
/// Example:
/// ```dart
/// assert(resolve_verify_target('sqlite') ==
///     'rudra_persistence_sqlite');
/// ```
String? resolve_verify_target(String target) {
  if (target == 'all') {
    return null;
  }

  return _package_aliases[target] ?? target;
}

/// Formats and verifies a selected Rudra workspace target.
///
/// This development-only command delegates execution to
/// [DevTasks] and never performs filesystem cleanup.
final class VerifyCommand extends Command<int> {
  /// Creates a verification command backed by development tasks.
  VerifyCommand(this._tasks);

  /// Repository development operations.
  final DevTasks _tasks;

  @override
  String get name => 'verify';

  @override
  String get description =>
      'Format and verify all packages or a selected workspace package.';

  @override
  String get invocation => 'rudra verify [all|package]';

  /// Resolves the target and executes the verification pipeline.
  ///
  /// Defaults to the complete workspace when no target is given.
  /// Invalid argument counts produce a usage error.
  @override
  Future<int> run() {
    final arguments = argResults!.rest;

    if (arguments.length > 1) {
      throw UsageException('Expected at most one verification target.', usage);
    }

    final target = arguments.isEmpty ? 'all' : arguments.single;

    if (target.trim().isEmpty) {
      throw UsageException('Verification target must not be empty.', usage);
    }

    return _tasks.verify(package_name: resolve_verify_target(target));
  }
}
