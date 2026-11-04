import 'package:rudra_sdk/rudra_sdk.dart';

import '../../composition/product_sdk_composition.dart';
import 'welcome_model.dart';
import 'welcome_view.dart';

/// Coordinates Rudra's CLI welcome screen.
///
/// WelcomeController connects application configuration to
/// the welcome presentation model and view.
///
/// The controller belongs exclusively to the CLI frontend.
/// It does not implement domain behavior or filesystem inspection.
///
/// Responsibilities:
/// - Read the configured target identity.
/// - Build a WelcomeModel.
/// - Delegate rendering to WelcomeView.
///
/// It does not:
/// - Inspect filesystem entries.
/// - Manage persistent sessions.
/// - Modify filesystem contents.
/// - Execute cleanup.
/// - Implement navigation or terminal input.
///
/// Example:
/// ```dart
/// final output = StringBuffer();
///
/// final controller = WelcomeController(
///   composition: composition,
///   output: output,
/// );
///
/// controller.show();
/// ```
final class WelcomeController {
  /// Creates a controller for the welcome screen.
  ///
  /// [composition] contains the configured SDK and initial
  /// directory, or null when no supported target is available.
  ///
  /// [output] receives the rendered welcome screen.
  ///
  /// [view] allows the presentation implementation to be
  /// supplied explicitly. It defaults to the standard
  /// stateless terminal view.
  ///
  /// Construction performs no filesystem inspection, terminal
  /// output, session changes, or cleanup operations.
  WelcomeController({
    required ProductSdkComposition? composition,
    required StringSink output,
    WelcomeView view = const WelcomeView(),
  })  : _composition = composition,
        _output = output,
        _view = view;

  /// Application composition used to construct welcome state.
  ///
  /// Null indicates that no supported filesystem inspection
  /// target was configured.
  final ProductSdkComposition? _composition;

  /// Destination for terminal presentation.
  final StringSink _output;

  /// Stateless presentation view.
  final WelcomeView _view;

  /// Builds and renders the current welcome screen.
  ///
  /// Uses the public SDK application name and the configured
  /// target information.
  ///
  /// If no composition is available, the view describes the
  /// lack of a supported inspection target.
  ///
  /// Returns after rendering the welcome information.
  ///
  /// The controller performs no filesystem inspection and
  /// does not invoke any SDK application service.
  ///
  /// Rendering does not start or resume an inspection session.
  ///
  /// Example:
  /// ```dart
  /// final controller = WelcomeController(
  ///   composition: composition,
  ///   output: stdout,
  /// );
  ///
  /// controller.show();
  /// ```
  void show() {
    final composition = _composition;

    // Target availability comes from application composition.
    // The view must not attempt to detect the operating system.
    final model = WelcomeModel(
      product_name: application_name,
      target_id: composition?.sdk.target_id,
      starting_directory: composition?.working_directory,
    );

    _view.render(
      model,
      output: _output,
    );
  }
}
