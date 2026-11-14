import '../../filesystem/presentation/directory_listing_presenter.dart';
import '../../filesystem/presentation/filesystem_view_model.dart';
import '../../filesystem/presentation/widgets/directory_listing/directory_listing_view_model.dart';

import '../application/welcome_model.dart';

import 'welcome_view_model.dart';
import 'widgets/commands/welcome_commands_view_model.dart';
import 'widgets/footer/welcome_footer_view_model.dart';
import 'widgets/header/welcome_header_view_model.dart';
import 'widgets/target/welcome_target_view_model.dart';

/// Prepares a composable Welcome presentation.
///
/// The presenter converts [WelcomeModel] into independently
/// prepared visual component models.
///
/// Filesystem observations are delegated to the shared
/// [DirectoryListingPresenter], which returns a
/// [FilesystemViewModel] containing listing and diagnostic data.
///
/// The Welcome presenter owns presentation-only decisions:
/// - Application title capitalization.
/// - Target and command-hint visibility.
/// - Informational safety wording.
/// - Composition of one consistent Welcome snapshot.
///
/// It never performs filesystem or terminal I/O, changes
/// navigation state, or authorizes cleanup operations.
///
/// Example:
/// ```dart
/// const presenter = WelcomePresenter();
///
/// final presentation = presenter.present(welcome_model);
///
/// print(presentation.header.product_title);
/// ```
final class WelcomePresenter {
  /// Creates a stateless presenter with a reusable filesystem presenter.
  ///
  /// Dependency injection allows the presentation transformation
  /// to be tested without a native target or terminal.
  const WelcomePresenter({
    DirectoryListingPresenter directory_listing_presenter =
        const DirectoryListingPresenter(),
  }) : _directory_listing_presenter = directory_listing_presenter;

  /// Shared filesystem presentation dependency.
  final DirectoryListingPresenter _directory_listing_presenter;

  /// Converts already prepared application state into visual data.
  ///
  /// The original target-native path is preserved.
  ///
  /// If the model contains a directory observation, the shared
  /// filesystem presenter prepares its detailed listing and
  /// typed diagnostics without requesting another inspection.
  ///
  /// Returns one validated [WelcomeViewModel].
  WelcomeViewModel present(WelcomeModel model) {
    final observation = model.listing;

    final FilesystemViewModel? filesystem = observation == null
        ? null
        : _directory_listing_presenter.present(
            observation,
            layout: DirectoryListingLayout.detailed,
          );

    return WelcomeViewModel(
      header: WelcomeHeaderViewModel(
        product_title: model.product_name.toUpperCase(),
      ),
      target: WelcomeTargetViewModel(
        target_id: model.target_id,
        starting_directory: model.starting_directory?.value,
      ),
      commands: WelcomeCommandsViewModel(
        show_filesystem_commands: model.can_inspect,
      ),
      footer: WelcomeFooterViewModel(
        safety_statement:
            'Inspection never authorizes file modification or deletion.',
      ),
      filesystem: filesystem,
    );
  }
}
