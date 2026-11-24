import 'dart:io';

import 'package:args/args.dart';
import 'package:rudra_host/src/composition/host_composition.dart';
import 'package:rudra_host_macos/rudra_host_macos.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

/// Exit status for invalid command-line usage.
const int _usage_exit_code = 64;

/// Exit status for unsuccessful host execution.
const int _failure_exit_code = 1;

/// Executes the standalone Rudra development host.
///
/// [arguments] supplies the explicit development persistence
/// directory and optional workflow startup operation.
///
/// The entrypoint selects native platform implementations,
/// constructs the host composition and establishes process
/// lifecycle handling.
///
/// Example:
/// ```sh
/// dart run apps/host/bin/rudra_host.dart --data-dir /private/tmp/rudra-dev
/// ```
///
/// Invalid arguments and execution failures produce a nonzero
/// process exit status.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'data-dir',
      help: 'Existing dedicated development persistence directory.',
    )
    ..addFlag(
      'start-workflow',
      negatable: false,
      help: 'Explicitly start a workflow at the working directory.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Display host usage information.',
    );

  final ArgResults options;

  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = _usage_exit_code;
    return;
  }

  if (options['help'] as bool) {
    stdout.writeln('Rudra development host');
    stdout.writeln(parser.usage);
    return;
  }

  final data_dir = options['data-dir'] as String?;

  if (data_dir == null || data_dir.trim().isEmpty || options.rest.isNotEmpty) {
    stderr.writeln('A development data directory is required.');
    stderr.writeln(parser.usage);
    exitCode = _usage_exit_code;
    return;
  }

  try {
    // Concrete platform selection belongs to the executable
    // rather than the portable SDK host runtime.
    if (!Platform.isMacOS) {
      throw UnsupportedError(
        'A native host adapter is not available for this platform.',
      );
    }

    final composition = HostComposition(
      identity_provider: const MacOsHostIdentity(),
      data_directory: Directory(data_dir),
      target_id: 'local-macos',
    );

    final start_workflow = options['start-workflow'] as bool;

    // An explicit Start uses the absolute native working directory.
    // Ordinary host startup only restores existing workflow state.
    final startup_root = start_workflow
        ? TargetPath(Directory.current.absolute.path)
        : null;

    stdout.writeln('Rudra Host starting');

    const lifecycle = MacOsHostShutdown();

    // Register process termination handling before opening
    // application resources or performing startup operations.
    await lifecycle.run((shutdown) async {
      await composition.run(
        shutdown: shutdown,
        startup_root: startup_root,
        on_ready: (os_user_id, workflow) {
          stdout.writeln('Host identity: $os_user_id');

          if (workflow == null) {
            stdout.writeln('Workflow: NONE');
          } else {
            stdout.writeln(
              start_workflow ? 'Workflow started' : 'Workflow restored',
            );
            stdout.writeln('Workflow ID: ${workflow.identity.workflow_id}');
            stdout.writeln('Workflow version: ${workflow.version}');
          }

          stdout.writeln('Host ready (pid: $pid)');
        },
      );
    });

    stdout.writeln('Rudra Host stopped');
  } catch (error) {
    stderr.writeln('Rudra Host failed: $error');
    exitCode = _failure_exit_code;
  }
}
