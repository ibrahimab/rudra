import 'package:args/command_runner.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../core/cli/rudra_cli_module.dart';

import 'explore_command.dart';
import '../application/explorer_runner.dart';

/// Registers Rudra's interactive filesystem Explorer command.
///
/// ExplorerCliModule contributes one production command:
/// `rudra explore`.
///
/// The module receives a configured starting directory and
/// an Explorer runner factory from application composition.
///
/// It does not:
/// - Select or instantiate a platform-specific target adapter.
/// - Construct terminal rendering backends.
/// - Inspect filesystem entries.
/// - Manage persistent Rudra sessions.
/// - Mark cleanup candidates.
/// - Authorize or execute cleanup.
///
/// Explorer remains independent of the filesystem feature's
/// command implementation.
///
/// Example:
/// ```dart
/// cli.register_module(
///   ExplorerCliModule(
///     working_directory: TargetPath('/workspace'),
///     create_runner: create_explorer,
///   ),
/// );
/// ```
final class ExplorerCliModule implements RudraCliModule {
  /// Creates an Explorer module with injected dependencies.
  ///
  /// [working_directory] is the default target-native directory.
  ///
  /// [create_runner] constructs one Explorer workflow for a
  /// validated command invocation.
  ///
  /// The caller must ensure that the factory uses the SDK
  /// target associated with [working_directory].
  ///
  /// Construction does not invoke the factory, inspect
  /// the filesystem, or change terminal settings.
  ExplorerCliModule({
    required TargetPath working_directory,
    required ExplorerRunner Function(TargetPath) create_runner,
  })  : _working_directory = working_directory,
        _create_runner = create_runner;

  /// Configured default Explorer starting directory.
  final TargetPath _working_directory;

  /// Injected factory for individual Explorer invocations.
  final ExplorerRunner Function(TargetPath) _create_runner;

  /// Stable Explorer module identifier.
  @override
  String get module_id => 'rudra.product.explorer';

  /// Creates the command contributed by this module.
  ///
  /// Runner creation is deferred until the command executes.
  ///
  /// Registration performs no SDK inspection, terminal I/O,
  /// persistent session management, or filesystem modification.
  @override
  Iterable<Command<int>> create_commands() {
    return [
      ExploreCommand(
        working_directory: _working_directory,
        create_runner: _create_runner,
      ),
    ];
  }
}
