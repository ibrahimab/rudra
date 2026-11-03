import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

/// Displays basic information about the Rudra application.
///
/// This command performs no filesystem inspection or modification.
///
/// It is available in both development and production builds.
///
/// Example:
/// ```bash
/// rudra about
/// ```
final class AboutCommand extends Command<int> {
  /// The command name used for argument parsing.
  @override
  String get name => 'about';

  /// A short description displayed in the CLI help output.
  @override
  String get description => 'Display information about Rudra.';

  /// Prints application information and returns a successful exit code.
  ///
  /// No target adapter or user session is required.
  ///
  /// Returns `0` after writing the information to standard output.
  @override
  int run() {
    stdout.writeln(
      '$application_name - User-directed filesystem exploration.',
    );

    return 0;
  }
}
