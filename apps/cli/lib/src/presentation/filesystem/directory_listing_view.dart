import 'package:rudra_sdk/rudra_sdk.dart';

import '../../rendering/bare/bare_filesystem_renderer.dart';
import 'directory_listing_presenter.dart';
import 'directory_listing_view_model.dart';

/// Compatibility adapter for existing CLI directory presentations.
///
/// Delegates SDK-to-presentation conversion to
/// [DirectoryListingPresenter] and terminal output to
/// [BareFilesystemRenderer].
///
/// This class preserves the established rendering methods
/// consumed by ListCommand and WelcomeView.
///
/// It contains no filesystem formatting or terminal layout logic.
///
/// The adapter is transitional: callers can eventually inject
/// presenters and renderers directly through application
/// composition without changing the output contract.
///
/// All filesystem observations must originate from the SDK.
///
/// Rendering never inspects or modifies the filesystem.
///
/// Example:
/// ```dart
/// const view = DirectoryListingView();
///
/// view.render_compact(
///   listing,
///   output: stdout,
/// );
/// ```
final class DirectoryListingView {
  /// Creates a stateless directory listing presentation adapter.
  const DirectoryListingView();

  /// Renders the established compact filesystem listing.
  ///
  /// Preserves the TYPE, LOGICAL_BYTES, PATH layout and
  /// original SDK observation ordering.
  ///
  /// Compact output is intentionally unstyled so it remains
  /// suitable for shell pipelines and redirected output.
  ///
  /// Inspection issues are not written by this method.
  /// Call [render_issues] separately when diagnostics are needed.
  ///
  /// No SDK or native filesystem operations occur.
  void render_compact(
    DirectoryListing listing, {
    required StringSink output,
  }) {
    const presenter = DirectoryListingPresenter();

    final view_model = presenter.present(
      listing,
      layout: DirectoryListingLayout.compact,
    );

    BareFilesystemRenderer(
      output: output,
    ).render(view_model);
  }

  /// Renders the established detailed filesystem listing.
  ///
  /// Uses directory-first sorting and human-readable metadata
  /// prepared by [DirectoryListingPresenter].
  ///
  /// Preserves the existing welcome-screen listing format.
  ///
  /// Incomplete observations retain a visible warning.
  /// Detailed issues are rendered separately through
  /// [render_issues].
  ///
  /// No filesystem or session operations occur.
  void render_detailed(
    DirectoryListing listing, {
    required StringSink output,
  }) {
    const presenter = DirectoryListingPresenter();

    final view_model = presenter.present(
      listing,
      layout: DirectoryListingLayout.detailed,
    );

    BareFilesystemRenderer(
      output: output,
    ).render(view_model);
  }

  /// Writes typed SDK inspection issues to a diagnostic sink.
  ///
  /// Preserves the established diagnostic field ordering:
  /// operation, code, target path, and message.
  ///
  /// An incomplete listing with no typed issues produces
  /// an explicit incomplete-inspection diagnostic.
  ///
  /// Valid observations are never discarded because another
  /// entry could not be inspected.
  ///
  /// The output is sanitized to prevent terminal injection
  /// through untrusted filesystem paths and diagnostics.
  ///
  /// No filesystem operations are performed.
  void render_issues(
    DirectoryListing listing, {
    required StringSink output,
  }) {
    const presenter = DirectoryListingPresenter();

    // Compact presentation avoids unnecessary sorting.
    // The diagnostics are independent of entry ordering.
    final view_model = presenter.present(
      listing,
      layout: DirectoryListingLayout.compact,
    );

    final renderer = BareFilesystemRenderer(
      output: output,
    );

    renderer.render_issues(
      view_model,
      output: output,
    );
  }
}
