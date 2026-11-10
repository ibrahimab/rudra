import 'package:args/command_runner.dart';

import '../../core/cli/rudra_cli_module.dart';
import 'about_command.dart';

/// Registers the informational commands provided by Rudra.
///
/// This module is included in both development and production builds.
///
/// It does not require filesystem access, target adapters, or
/// persistent application state.
///
/// Example:
/// ```dart
/// cli.register_module(AboutCliModule());
/// ```
final class AboutCliModule implements RudraCliModule {
  /// Unique identifier of the module.
  @override
  String get module_id => 'rudra.product.about';

  /// Creates the commands exposed by this module.
  ///
  /// Constructing these commands does not execute them.
  @override
  Iterable<Command<int>> create_commands() {
    return [AboutCommand()];
  }
}
