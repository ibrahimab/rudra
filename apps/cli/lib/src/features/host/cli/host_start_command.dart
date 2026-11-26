import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:rudra_host/rudra_host.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../core/cli/rudra_exit_code.dart';

/// Starts the Rudra host through the configured application operation.
///
/// Translates explicit command-line configuration into a host
/// lifecycle request and presents verified startup information.
///
/// Host execution, platform selection, persistence ownership and
/// graceful termination remain responsibilities of the injected
/// application operation.
///
/// Example:
/// ```dart
/// final command = HostStartCommand(
///   run_host: run_local_host,
///   output: stdout,
///   error_output: stderr,
/// );
/// ```
final class HostStartCommand extends Command<int> {
  /// Creates a host start command with injected dependencies.
  ///
  /// [run_host] executes the configured host application lifecycle.
  /// [output] receives lifecycle and readiness information.
  /// [error_output] receives host execution diagnostics.
  ///
  /// Construction defines the supported command options without
  /// starting the host or acquiring application resources.
  HostStartCommand({
    required HostRunOperation run_host,
    required StringSink output,
    required StringSink error_output,
  }) : _run_host = run_host,
       _output = output,
       _error_output = error_output {
    argParser.addFlag(
      'foreground',
      negatable: false,
      help: 'Run the host in the current process.',
    );
  }

  /// Application operation responsible for executing the host lifecycle.
  final HostRunOperation _run_host;

  /// Destination for host lifecycle and readiness information.
  final StringSink _output;

  /// Destination for host execution diagnostics.
  final StringSink _error_output;

  /// Command identifier within the host command group.
  @override
  String get name => 'start';

  /// Description displayed by the shared CLI help system.
  @override
  String get description => 'Start the Rudra host.';

  /// Supported invocation for a provisioned foreground host.
  @override
  String get invocation => 'rudra host start --foreground';

  /// Validates and executes an explicit host start request.
  ///
  /// Returns [RudraExitCode.success] after graceful termination.
  ///
  /// Unsupported platform configuration returns
  /// [RudraExitCode.configuration_error]. Other host execution
  /// failures return [RudraExitCode.software_error].
  ///
  /// An existing Rudra host for this operating-system user returns
  /// [RudraExitCode.host_conflict].
  ///
  /// Throws [UsageException] for unsupported arguments or missing
  /// foreground selection.
  @override
  Future<int> run() async {
    final options = argResults!;

    if (options.rest.isNotEmpty) {
      throw UsageException(
        'Host start does not accept positional arguments.',
        usage,
      );
    }

    // Reserve managed background startup for the process ownership
    // implementation rather than reporting unsupported behavior
    // as a successfully launched background service.
    if (!(options['foreground'] as bool)) {
      throw UsageException(
        'Only foreground host execution is currently supported.',
        usage,
      );
    }

    _output.writeln('Rudra Host starting');

    try {
      await _run_host(
        on_ready: (os_user_id, workflow) {
          // Readiness is reported only after the application has
          // completed initialization and restored committed state.
          _output.writeln('Host identity: $os_user_id');

          if (workflow == null) {
            _output.writeln('Workflow: NONE');
          } else {
            _output.writeln('Workflow restored');

            _output.writeln('Workflow ID: ${workflow.identity.workflow_id}');

            _output.writeln('Workflow version: ${workflow.version}');
          }

          _output.writeln('Host ready (pid: $pid)');
        },
      );
    } on HostAlreadyOwnedException catch (error) {
      _error_output.writeln(
        'Rudra Host already running for user ${error.os_user_id}.',
      );

      return RudraExitCode.host_conflict.value;
    } on UnsupportedError catch (error) {
      _error_output.writeln('Host unavailable: $error');

      return RudraExitCode.configuration_error.value;
    } catch (error) {
      _error_output.writeln('Rudra Host failed: $error');

      return RudraExitCode.software_error.value;
    }

    // The host operation returns only after releasing its
    // application resources and native lifecycle subscriptions.
    _output.writeln('Rudra Host stopped');

    return RudraExitCode.success.value;
  }
}
