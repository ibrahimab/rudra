import 'package:rudra_sdk/rudra_sdk.dart';

import '../application/welcome_controller.dart';
import '../presentation/bare_welcome_renderer.dart';

/// Assembles the product welcome screen and its standard renderer.
///
/// [connect] obtains the shared SDK when the welcome screen is invoked.
/// [starting_directory] identifies the first listing. [output] and
/// [error_output] receive presentation and diagnostics, respectively.
///
/// Example:
/// ```dart
/// final welcome = compose_welcome(
///   connect: connect_sdk,
///   starting_directory: TargetPath('/workspace'),
///   output: stdout,
///   error_output: stderr,
/// );
/// final status = await welcome.show();
/// ```
WelcomeController compose_welcome({
  required Future<RudraSdk> Function() connect,
  required TargetPath starting_directory,
  required StringSink output,
  required StringSink error_output,
}) => WelcomeController(
  connect: connect,
  starting_directory: starting_directory,
  renderer: BareWelcomeRenderer(output: output, error_output: error_output),
);
