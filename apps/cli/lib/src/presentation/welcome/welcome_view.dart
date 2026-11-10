import '../../rendering/bare/bare_welcome_renderer.dart';
import 'welcome_model.dart';
import 'welcome_presenter.dart';

/// Compatibility adapter for Rudra's welcome presentation.
///
/// This class preserves the existing interface used by
/// [WelcomeController] while delegating presentation work
/// to the shared rendering architecture.
///
/// The rendering pipeline is:
///
/// 1. The controller supplies an existing [WelcomeModel].
/// 2. [WelcomePresenter] creates a presentation-ready model.
/// 3. [BareWelcomeRenderer] renders the resulting view model.
///
/// The bare renderer also delegates nested filesystem tables
/// to the shared filesystem rendering implementation.
///
/// This class contains no:
/// - Filesystem inspection or SDK calls.
/// - Terminal layout or metadata formatting.
/// - ANSI escape-sequence generation.
/// - Terminal input or navigation logic.
/// - Persistent session or cleanup functionality.
///
/// The adapter is intentionally lightweight and can be
/// removed when application composition directly injects
/// presenters and rendering backends.
///
/// Example:
/// ```dart
/// const view = WelcomeView();
///
/// view.render(
///   model,
///   output: stdout,
///   error_output: stderr,
/// );
/// ```
final class WelcomeView {
  /// Creates a stateless welcome presentation adapter.
  ///
  /// Construction performs no filesystem or terminal I/O.
  ///
  /// The existing const constructor is preserved for
  /// compatibility with WelcomeController.
  const WelcomeView();

  /// Renders the welcome screen using the shared bare backend.
  ///
  /// [model] contains application identity and any SDK
  /// directory observation already obtained by the caller.
  ///
  /// [output] receives the welcome presentation.
  ///
  /// [error_output], when provided, receives typed filesystem
  /// inspection diagnostics.
  ///
  /// The presenter performs no additional SDK operations.
  /// The renderer receives presentation-ready data only.
  ///
  /// Plain, unstyled output is the default, preserving the
  /// existing welcome-screen behavior.
  ///
  /// Rendering errors propagate to the caller.
  /// Terminal lifecycle cleanup is not owned by this adapter.
  ///
  /// No filesystem modifications or session operations occur.
  void render(
    WelcomeModel model, {
    required StringSink output,
    StringSink? error_output,
  }) {
    const presenter = WelcomePresenter();

    final view_model = presenter.present(model);

    final renderer = BareWelcomeRenderer(
      output: output,
      error_output: error_output,
    );

    renderer.render(view_model);
  }
}
