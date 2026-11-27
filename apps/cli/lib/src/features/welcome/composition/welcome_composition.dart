import '../../../composition/product_sdk_composition.dart';

import '../application/welcome_controller.dart';
import '../presentation/bare_welcome_renderer.dart';

/// Assembles the product welcome screen and its standard renderer.
///
/// [sdk_composition] supplies the shared SDK and root when Welcome is invoked.
/// [output] and
/// [error_output] receive presentation and diagnostics, respectively.
///
/// Example:
/// ```dart
/// final welcome = compose_welcome(
///   sdk_composition: composition,
///   output: stdout,
///   error_output: stderr,
/// );
/// final status = await welcome.show();
/// ```
WelcomeController compose_welcome({
  required ProductSdkComposition sdk_composition,
  required StringSink output,
  required StringSink error_output,
}) => WelcomeController(
  connect: sdk_composition.connect,
  starting_directory: sdk_composition.working_directory,
  renderer: BareWelcomeRenderer(output: output, error_output: error_output),
);
