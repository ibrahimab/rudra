import 'package:args/command_runner.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../rudra_cli_module.dart';
import 'list_command.dart';

/// Registers filesystem commands for Rudra's CLI frontend.
///
/// FilesystemCliModule adapts the public Rudra SDK to the
/// modular CLI framework.
///
/// The module owns command construction and dependency injection.
///
/// It does not implement filesystem inspection algorithms,
/// session lifecycle rules, or cleanup authorization.
///
/// All filesystem behavior is delegated to SDK services.
///
/// Additional filesystem commands may be registered here
/// as their corresponding SDK capabilities are implemented.
///
/// Module construction and command registration perform
/// no filesystem operations.
///
/// Example:
/// ```dart
/// final module = FilesystemCliModule(
///   sdk: sdk,
///   working_directory: TargetPath('/Users/example'),
/// );
///
/// cli.register_module(module);
/// ```
final class FilesystemCliModule implements RudraCliModule {
  /// Creates a CLI module backed by a configured SDK.
  ///
  /// [sdk] contains the filesystem service to be consumed.
  ///
  /// [working_directory] is the default target-native path for
  /// filesystem commands when no explicit path is supplied.
  ///
  /// The caller must ensure the directory belongs to the
  /// SDK's configured target.
  ///
  /// [output] and [error_output] allow terminal output to be
  /// redirected or captured during tests.
  ///
  /// Creating this module performs no filesystem inspection.
  FilesystemCliModule({
    required RudraSdk sdk,
    required TargetPath working_directory,
    StringSink? output,
    StringSink? error_output,
  })  : _sdk = sdk,
        _working_directory = working_directory,
        _output = output,
        _error_output = error_output;

  /// SDK instance shared by commands in this module.
  final RudraSdk _sdk;

  /// Default directory for CLI filesystem operations.
  final TargetPath _working_directory;

  /// Optional output destination for command results.
  final StringSink? _output;

  /// Optional destination for inspection diagnostics.
  final StringSink? _error_output;

  /// Unique identifier of this CLI module.
  @override
  String get module_id => 'rudra.product.filesystem';

  /// Creates the filesystem commands contributed by this module.
  ///
  /// Commands receive the SDK and working directory explicitly.
  ///
  /// No filesystem operations are performed during registration.
  ///
  /// The returned commands are owned by the CLI framework.
  @override
  Iterable<Command<int>> create_commands() {
    return [
      ListCommand(
        sdk: _sdk,
        working_directory: _working_directory,
        output: _output,
        error_output: _error_output,
      ),
    ];
  }
}
