import 'dart:io';

import 'package:rudra_cli/rudra_cli.dart';

import 'src/dev_tasks.dart';
import 'src/dev_tools_cli_module.dart';

/// Starts Rudra with development commands registered.
///
/// The development application uses the same [RudraCli] implementation
/// as the production application.
///
/// It registers product modules first, then explicitly registers
/// the development module.
///
/// This entrypoint must run from the repository root because its
/// commands operate on the shared Dart workspace.
///
/// Returns exit status 66 when repository structure validation fails.
/// This status follows the conventional EX_NOINPUT value.
///
/// Example:
/// ```bash
/// dart run apps/cli/tool/rudra_dev.dart test
/// ```
Future<void> main(List<String> arguments) async {
  final repo_root = Directory.current.absolute;

  final cli_manifest = File(
    '${repo_root.path}/apps/cli/pubspec.yaml',
  );

  final sdk_manifest = File(
    '${repo_root.path}/packages/sdk/pubspec.yaml',
  );

  if (!cli_manifest.existsSync() || !sdk_manifest.existsSync()) {
    stderr.writeln(
      'Rudra development commands must run from '
      'the repository root.',
    );

    // We will add a typed missing-input status below.
    exitCode = RudraExitCode.missing_input.value;
    return;
  }

  final cli = RudraCli.product();

  final tasks = DevTasks(repo_root);

  cli.register_module(
    DevToolsCliModule(tasks),
  );

  exitCode = await cli.run(arguments);
}
