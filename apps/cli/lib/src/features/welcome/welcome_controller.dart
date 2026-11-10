import 'package:rudra_sdk/rudra_sdk.dart';

import '../../core/cli/rudra_exit_code.dart';
import '../../core/rendering/renderer.dart';

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
/// A null SDK and starting directory represent an unsupported target.
///
/// Application composition supplies the SDK and its corresponding
/// target-native starting directory. This controller does not depend
/// on concrete application composition or platform adapter types.
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
  /// Creates a welcome controller with explicitly injected dependencies.
  ///
  /// [sdk] provides the platform-independent Rudra application services
  /// used to inspect the configured starting directory.
  ///
  /// [starting_directory] identifies the initial target-native directory
  /// to inspect through [sdk].
  ///
  /// [sdk] and [starting_directory] must either both be provided or
  /// both be null. Null values represent an unsupported target,
  /// allowing the welcome screen to render without filesystem inspection.
  ///
  /// Throws [ArgumentError] if exactly one of [sdk] or
  /// [starting_directory] is null.
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
  ///   sdk: sdk,
  ///   starting_directory: TargetPath('/workspace'),
  ///   renderer: renderer,
  /// );
  ///
  /// final exit_code = await controller.show();
  /// ```
  WelcomeController({
    required RudraSdk? sdk,
    required TargetPath? starting_directory,
    required Renderer<WelcomeViewModel> renderer,
    WelcomePresenter presenter = const WelcomePresenter(),
  })  : _sdk = sdk,
        _starting_directory = starting_directory,
        _renderer = renderer,
        _presenter = presenter {
    if ((sdk == null) != (starting_directory == null)) {
      throw ArgumentError(
        'SDK and starting directory must be provided together.',
      );
    }
  }

  /// Configured SDK providing read-only filesystem inspection services.
  ///
  /// Null indicates that no supported inspection target is configured.
  final RudraSdk? _sdk;

  /// Initial target-native directory associated with [_sdk].
  ///
  /// Null when no SDK is configured.
  ///
  /// The original path spelling is preserved and passed to the SDK
  /// without interpretation using host filesystem rules.
  final TargetPath? _starting_directory;

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
    final sdk = _sdk;
    final starting_directory = _starting_directory;

    final DirectoryListing? listing = sdk == null
        ? null
        : await sdk.filesystem.list(
            directory: starting_directory!,
          );

    final model = WelcomeModel(
      product_name: application_name,
      target_id: sdk?.target_id,
      starting_directory: starting_directory,
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
