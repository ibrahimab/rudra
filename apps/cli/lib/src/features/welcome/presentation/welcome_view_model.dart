import '../../filesystem/presentation/filesystem_view_model.dart';
import '../../filesystem/presentation/widgets/directory_listing/directory_listing_view_model.dart';

import 'widgets/commands/welcome_commands_view_model.dart';
import 'widgets/footer/welcome_footer_view_model.dart';
import 'widgets/header/welcome_header_view_model.dart';
import 'widgets/target/welcome_target_view_model.dart';

/// Immutable composition of Welcome's presentation components.
///
/// Each visual component owns its own prepared view model:
/// - [header] supplies the application title.
/// - [target] supplies target configuration or unsupported status.
/// - [commands] supplies command-hint visibility.
/// - [footer] supplies the read-only safety statement.
///
/// [filesystem] optionally supplies reusable directory-listing
/// and inspection-diagnostic presentations.
///
/// No flattened copies of child presentation data are kept.
///
/// This model validates cross-component consistency without
/// accessing SDK services or the filesystem.
///
/// Example:
/// ```dart
/// final model = WelcomeViewModel(
///   header: WelcomeHeaderViewModel(product_title: 'RUDRA'),
///   target: WelcomeTargetViewModel(),
///   commands: const WelcomeCommandsViewModel(
///     show_filesystem_commands: false,
///   ),
///   footer: WelcomeFooterViewModel(
///     safety_statement: 'Exploration is read-only.',
///   ),
/// );
///
/// print(model.can_inspect);
/// // false
/// ```
final class WelcomeViewModel {
  /// Composes and validates one Welcome presentation snapshot.
  ///
  /// Command visibility must agree with target availability.
  ///
  /// When [filesystem] is present:
  /// - A target must be configured.
  /// - The target identifier and directory must match.
  /// - The directory listing must use the detailed layout.
  ///
  /// Throws [ArgumentError] when these invariants are violated.
  ///
  /// Construction performs no terminal or filesystem operations.
  WelcomeViewModel({
    required this.header,
    required this.target,
    required this.commands,
    required this.footer,
    this.filesystem,
  }) {
    if (commands.show_filesystem_commands != target.can_inspect) {
      throw ArgumentError('Command hints must match target availability.');
    }

    final observation = filesystem;

    if (observation == null) {
      return;
    }

    if (!target.can_inspect ||
        observation.listing.target_id != target.target_id ||
        observation.listing.directory_path != target.starting_directory) {
      throw ArgumentError(
        'The filesystem presentation must match '
        'the configured target and starting directory.',
      );
    }

    if (observation.listing.layout != DirectoryListingLayout.detailed) {
      throw ArgumentError('Welcome requires a detailed directory listing.');
    }
  }

  /// Application title presentation.
  final WelcomeHeaderViewModel header;

  /// Configured filesystem target presentation.
  final WelcomeTargetViewModel target;

  /// Available command hints presentation.
  final WelcomeCommandsViewModel commands;

  /// Informational safety footer presentation.
  final WelcomeFooterViewModel footer;

  /// Optional filesystem presentation composed of independent widgets.
  ///
  /// Null means no directory observation was supplied.
  /// It does not imply that an inspection was attempted.
  final FilesystemViewModel? filesystem;

  /// Whether a supported filesystem target is configured.
  bool get can_inspect => target.can_inspect;

  /// Whether the supplied directory observation is incomplete.
  ///
  /// False when no observation was supplied.
  bool get has_incomplete_listing =>
      filesystem?.inspection_issues.is_incomplete ?? false;
}
