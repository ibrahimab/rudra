import 'dart:io';

import 'package:rudra_cli/rudra_cli.dart';

/// Starts the production Rudra command-line application.
///
/// Constructs a product-only CLI registry and dispatches the
/// supplied arguments.
///
/// No development modules are imported by this entrypoint.
///
/// This file is the compilation root for production executables.
///
/// Example:
/// ```bash
/// dart run apps/cli/bin/rudra.dart about
/// ```
Future<void> main(List<String> arguments) async {
  final cli = RudraCli.product();

  exitCode = await cli.run(arguments);
}
