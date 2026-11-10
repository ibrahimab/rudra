/// Defines the shared rendering contract for Rudra's CLI.
///
/// A renderer transforms a feature-specific presentation model
/// into an output appropriate for its rendering backend.
///
/// The CLI initially uses a bare terminal renderer. Future
/// implementations may use Nocterm or another presentation
/// technology without changing feature controllers or models.
///
/// Renderers belong to the CLI application layer, not the SDK.
///
/// Architecture:
/// - Controllers consume SDK application services.
/// - Presenters prepare feature-specific view models.
/// - Renderers consume view models.
/// - Rendering implementations own their output technology.
///
/// A renderer must not:
/// - Inspect or modify the filesystem.
/// - Invoke Rudra SDK application services.
/// - Implement navigation or business rules.
/// - Modify the supplied view model.
/// - Manage persistent inspection sessions.
/// - Authorize cleanup operations.
///
/// Rendering dependencies such as output sinks, themes, and
/// terminal capabilities are supplied through composition.
///
/// This interface deliberately does not prescribe a terminal
/// output mechanism or widget framework.
///
/// Example:
/// ```dart
/// final Renderer<ExplorerViewModel> renderer =
///     BareExplorerRenderer(
///       output: stdout,
///       theme: theme,
///     );
///
/// renderer.render(view_model);
/// ```
abstract interface class Renderer<TViewModel extends Object> {
  /// Renders the supplied presentation model.
  ///
  /// [view_model] contains data prepared by the corresponding
  /// feature presenter.
  ///
  /// Implementations determine how that information is displayed.
  /// They may use plain text, ANSI terminal styling, or a
  /// framework-specific widget tree.
  ///
  /// The method may be called repeatedly as presentation state
  /// changes, including after navigation and terminal resizing.
  ///
  /// Implementations must not mutate [view_model].
  ///
  /// Rendering errors propagate to the caller. The application
  /// hosting the renderer is responsible for error handling and
  /// restoring terminal state.
  ///
  /// This operation performs no filesystem inspection or mutation.
  void render(TViewModel view_model);
}
