import 'package:args/command_runner.dart';
import 'package:rudra_host/rudra_host.dart';

import '../../../core/cli/rudra_cli_module.dart';

import 'host_start_command.dart';

/// Registers explicit Rudra host lifecycle commands.
///
/// Provides the command-line integration boundary for the
/// independently composed host application.
///
/// Host operations and output destinations are supplied through
/// dependency injection at the CLI composition boundary.
///
/// Example:
/// ```dart
/// cli.register_module(
///   HostCliModule(
///     run_host: run_local_host,
///     output: output,
///     error_output: error_output,
///   ),
/// );
/// ```
final class HostCliModule implements RudraCliModule {
  /// Creates a host command contribution.
  ///
  /// [run_host] supplies the configured host execution operation.
  /// [output] receives lifecycle information.
  /// [error_output] receives execution diagnostics.
  ///
  /// Construction retains dependencies for command registration.
  const HostCliModule({
    required HostRunOperation run_host,
    required StringSink output,
    required StringSink error_output,
  }) : _run_host = run_host,
       _output = output,
       _error_output = error_output;

  /// Injected application-level host execution operation.
  final HostRunOperation _run_host;

  /// Shared destination for host command output.
  final StringSink _output;

  /// Shared destination for host command diagnostics.
  final StringSink _error_output;

  /// Stable identifier of the host command contribution.
  @override
  String get module_id => 'rudra.product.host';

  /// Creates the host command group and its lifecycle commands.
  ///
  /// Returns the commands contributed to the shared CLI registry.
  /// Registration constructs command objects without executing
  /// host operations or acquiring application resources.
  @override
  Iterable<Command<int>> create_commands() {
    return [
      _HostCommand(
        start_command: HostStartCommand(
          run_host: _run_host,
          output: _output,
          error_output: _error_output,
        ),
      ),
    ];
  }
}

/// Groups host lifecycle operations under `rudra host`.
///
/// Provides the command namespace through which independently
/// implemented host lifecycle actions are exposed.
///
/// Example:
/// ```dart
/// final group = _HostCommand(
///   start_command: start_command,
/// );
/// ```
final class _HostCommand extends Command<int> {
  /// Creates a host command group.
  ///
  /// [start_command] supplies the explicit host startup action.
  /// Command registration performs no host execution.
  _HostCommand({required HostStartCommand start_command}) {
    addSubcommand(start_command);
  }

  /// Top-level identifier of the host command group.
  @override
  String get name => 'host';

  /// Description displayed by the shared CLI help system.
  @override
  String get description => 'Manage the Rudra host lifecycle.';
}
