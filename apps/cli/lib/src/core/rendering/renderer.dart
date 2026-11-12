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

/// Rendering contract for screens with a scrollable content viewport.
///
/// A viewport-aware renderer declares how many terminal rows
/// are occupied by non-scrollable presentation components.
///
/// The application runner uses [fixed_rows] to determine how
/// many remaining rows may be allocated to scrollable content.
///
/// The reported value must be nonnegative and consistent with
/// the layout produced by [render].
///
/// The renderer does not reserve terminal safety margins.
/// The application host remains responsible for those.
///
/// This contract is independent of the concrete rendering
/// backend and can be implemented by bare or widget-based
/// terminal renderers.
///
/// Example:
/// ```dart
/// final ViewportRenderer<ExplorerViewModel> renderer =
///     BareExplorerRenderer(
///       output: stdout,
///       terminal_columns: () => stdout.terminalColumns,
///     );
///
/// final available_rows = terminal_rows - renderer.fixed_rows;
/// ```
abstract interface class ViewportRenderer<TViewModel extends Object>
    implements Renderer<TViewModel> {
  /// Terminal rows occupied by fixed screen components.
  ///
  /// This excludes the scrollable entry viewport.
  int get fixed_rows;
}
