import 'package:rudra_sdk/rudra_sdk.dart';

import '../../composition/product_sdk_composition.dart';
import '../../rendering/renderer.dart';
import '../../rudra_exit_code.dart';
import 'welcome_model.dart';
import 'welcome_presenter.dart';
import 'welcome_view_model.dart';

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
/// A null SDK composition represents an unsupported target.
///
/// The controller never:
/// - Calls a platform-specific TargetInspector directly.
/// - Modifies filesystem content.
/// - Creates or executes cleanup sessions.
/// - Authorizes deletion or other destructive operations.
///
/// Example:
/// ```dart
/// final controller = WelcomeController(
///   composition: composition,
///   renderer: renderer,
/// );
///
/// final exit_code = await controller.show();
/// ```
final class WelcomeController {
  /// Creates a welcome controller with explicit dependencies.
  ///
  /// [composition] contains the configured SDK and starting
  /// directory, or null when inspection is unsupported.
  ///
  /// [renderer] receives the prepared welcome ViewModel.
  /// Its concrete implementation is selected by application
  /// composition rather than by this controller.
  ///
  /// [presenter] performs the application-to-ViewModel
  /// transformation. The stateless default can be replaced
  /// when constructing the application or testing.
  ///
  /// No filesystem inspection or terminal I/O occurs
  /// during construction.
  WelcomeController({
    required ProductSdkComposition? composition,
    required Renderer<WelcomeViewModel> renderer,
    WelcomePresenter presenter = const WelcomePresenter(),
  })  : _composition = composition,
        _renderer = renderer,
        _presenter = presenter;

  /// Configured SDK and starting directory, if available.
  final ProductSdkComposition? _composition;

  /// Backend-independent welcome rendering contract.
  final Renderer<WelcomeViewModel> _renderer;

  /// Converts application state into presentation-ready data.
  final WelcomePresenter _presenter;

  /// Inspects the starting directory and renders the result.
  ///
  /// When a target is configured, exactly one SDK directory
  /// listing operation is requested.
  ///
  /// When no target is available, the welcome screen is
  /// rendered without attempting filesystem inspection.
  ///
  /// Incomplete observations retain their successfully
  /// inspected entries and typed diagnostic information.
  ///
  /// Returns:
  /// - [RudraExitCode.success] when inspection completes.
  /// - [RudraExitCode.success] for an unsupported target.
  /// - [RudraExitCode.inspection_incomplete] when the SDK
  ///   reports an incomplete directory listing.
  ///
  /// Unexpected SDK and renderer exceptions propagate
  /// without being converted into successful results.
  ///
  /// This operation is strictly read-only.
  Future<int> show() async {
    final composition = _composition;

    // Only the public SDK may obtain filesystem observations.
    final DirectoryListing? listing = composition == null
        ? null
        : await composition.sdk.filesystem.list(
            directory: composition.working_directory,
          );

    final model = WelcomeModel(
      product_name: application_name,
      target_id: composition?.sdk.target_id,
      starting_directory: composition?.working_directory,
      listing: listing,
    );

    // The presenter owns the application-to-presentation
    // transformation. The controller does not format output.
    final view_model = _presenter.present(model);

    // Rendering is backend-independent and injected.
    _renderer.render(view_model);

    return listing != null && !listing.is_complete
        ? RudraExitCode.inspection_incomplete.value
        : RudraExitCode.success.value;
  }
}
