import '../filesystem/presentation/directory_listing_presenter.dart';
import '../filesystem/presentation/filesystem_view_model.dart';
import '../filesystem/presentation/widgets/directory_listing/directory_listing_view_model.dart';

import 'welcome_model.dart';
import 'welcome_view_model.dart';

/// Prepares Rudra's welcome screen for presentation.
///
/// The presenter transforms an existing [WelcomeModel]
/// into an immutable [WelcomeViewModel].
///
/// Application and filesystem presentation remain separate:
/// - Welcome-specific display data is prepared here.
/// - Directory entry presentation is delegated to
///   [DirectoryListingPresenter].
/// - Physical layout and styling belong to renderers.
///
/// The presenter performs no filesystem inspection.
///
/// It does not:
/// - Call Rudra SDK services.
/// - Access platform-specific target adapters.
/// - Write to a terminal.
/// - Generate ANSI escape sequences.
/// - Implement navigation or terminal input.
/// - Create persistent sessions.
/// - Authorize filesystem modifications.
///
/// A nested directory listing always uses the detailed
/// presentation layout, preserving the existing welcome
/// screen's behavior.
///
/// Example:
/// ```dart
/// const presenter = WelcomePresenter();
///
/// final view_model = presenter.present(welcome_model);
///
/// print(view_model.product_title);
/// ```
final class WelcomePresenter {
  /// Creates a stateless welcome presenter.
  ///
  /// [directory_listing_presenter] prepares nested filesystem
  /// observations using the shared filesystem presentation
  /// contract.
  ///
  /// Dependency injection allows isolated testing without
  /// requiring a rendering engine or filesystem adapter.
  ///
  /// Construction performs no filesystem operations.
  const WelcomePresenter({
    DirectoryListingPresenter directory_listing_presenter =
        const DirectoryListingPresenter(),
  }) : _directory_listing_presenter = directory_listing_presenter;

  /// Shared filesystem presentation dependency.
  final DirectoryListingPresenter _directory_listing_presenter;

  /// Converts welcome application state into display-ready data.
  ///
  /// [model] is the existing welcome presentation state,
  /// constructed by [WelcomeController].
  ///
  /// The application name is capitalized for the welcome
  /// title, matching the established CLI output.
  ///
  /// Target-native path spelling is preserved unchanged.
  ///
  /// If the model contains an SDK directory observation,
  /// that observation is converted to a detailed filesystem
  /// view model by [DirectoryListingPresenter].
  ///
  /// Incomplete inspection results and their typed issues
  /// remain available in the nested view model.
  ///
  /// No inspection requests or filesystem mutations occur.
  ///
  /// Returns a validated, immutable [WelcomeViewModel].
  WelcomeViewModel present(WelcomeModel model) {
    final listing = model.listing;

    final FilesystemViewModel? listing_view_model = listing == null
        ? null
        : _directory_listing_presenter.present(
            listing,
            layout: DirectoryListingLayout.detailed,
          );

    return WelcomeViewModel(
      product_title: model.product_name.toUpperCase(),
      target_id: model.target_id,
      starting_directory: model.starting_directory?.value,
      listing: listing_view_model,
    );
  }
}
