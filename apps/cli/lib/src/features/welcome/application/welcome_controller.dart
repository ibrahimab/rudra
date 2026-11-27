import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../core/cli/rudra_exit_code.dart';
import '../../../core/rendering/renderer.dart';

import '../presentation/welcome_presenter.dart';
import '../presentation/welcome_view_model.dart';

import 'welcome_model.dart';

/// Coordinates Rudra's read-only welcome workflow.
///
/// The controller obtains filesystem observations exclusively
/// through the public Rudra SDK and prepares them for rendering.
///
/// Presentation responsibilities are separated:
/// - [WelcomeModel] represents validated application state.
/// - [WelcomePresenter] creates a rendering-ready view model.
/// - [Renderer] displays that view model.
///
/// The controller does not know which rendering backend is used.
///
/// In particular, it does not construct terminal templates,
/// encode ANSI text, or write directly to an output sink.
///
/// Application composition supplies the authenticated SDK and its
/// corresponding target-native starting directory.
///
/// Example:
/// ```dart
/// final controller = WelcomeController(
///   connect: connect_sdk,
///   starting_directory: TargetPath('/workspace'),
///   renderer: renderer,
/// );
///
/// final exit_code = await controller.show();
/// ```
final class WelcomeController {
  /// Creates a welcome controller with explicitly injected dependencies.
  ///
  /// [connect] establishes the invocation's authenticated SDK session.
  /// [starting_directory] is inspected through that SDK after connecting.
  ///
  /// [renderer] receives the prepared [WelcomeViewModel].
  /// Its concrete implementation is selected by application composition,
  /// not by this controller.
  ///
  /// [presenter] transforms welcome application state into an immutable
  /// presentation model. The default implementation is stateless and
  /// may be replaced for testing.
  ///
  /// Construction performs no filesystem inspection, terminal I/O,
  /// session management, or filesystem mutation.
  ///
  /// Example:
  /// ```dart
  /// final controller = WelcomeController(
  ///   connect: connect_sdk,
  ///   starting_directory: TargetPath('/workspace'),
  ///   renderer: renderer,
  /// );
  ///
  /// final exit_code = await controller.show();
  /// ```
  WelcomeController({
    required Future<RudraSdk> Function() connect,
    required TargetPath starting_directory,
    required Renderer<WelcomeViewModel> renderer,
    WelcomePresenter presenter = const WelcomePresenter(),
  }) : _connect = connect,
       _starting_directory = starting_directory,
       _renderer = renderer,
       _presenter = presenter;

  final Future<RudraSdk> Function() _connect;
  final TargetPath _starting_directory;

  /// Backend-independent welcome rendering contract.
  final Renderer<WelcomeViewModel> _renderer;

  /// Converts application state into presentation-ready data.
  final WelcomePresenter _presenter;

  /// Inspects the starting directory and renders the result.
  ///
  /// Returns success for a complete listing or the incomplete-inspection
  /// status for partial observations. Connection and rendering errors propagate.
  Future<int> show() async {
    final sdk = await _connect();
    final listing = await sdk.filesystem.list(directory: _starting_directory);
    final model = WelcomeModel(
      product_name: application_name,
      target_id: listing.target_id,
      starting_directory: _starting_directory,
      listing: listing,
    );

    // The presenter owns the application-to-presentation
    // transformation. The controller does not format output.
    final view_model = _presenter.present(model);

    // Rendering is backend-independent and injected.
    _renderer.render(view_model);

    return !listing.is_complete
        ? RudraExitCode.inspection_incomplete.value
        : RudraExitCode.success.value;
  }
}
