import '../filesystem/directory_listing_view_model.dart';

/// Immutable presentation data for Rudra's welcome screen.
///
/// The view model contains information prepared for rendering,
/// without references to Rudra SDK services, filesystem adapters,
/// terminal input, or concrete rendering technologies.
///
/// The welcome screen may display:
/// - The application title.
/// - The configured filesystem target.
/// - The starting directory.
/// - An optional detailed directory listing.
/// - Available application commands.
///
/// The nested [DirectoryListingViewModel] allows the welcome
/// renderer to reuse the shared filesystem rendering system.
///
/// This model is not an inspection session and contains no
/// cleanup or authorization state.
///
/// No filesystem operations occur during construction.
///
/// Example:
/// ```dart
/// final model = WelcomeViewModel(
///   product_title: 'RUDRA',
///   target_id: 'local-macos',
///   starting_directory: '/workspace',
/// );
///
/// print(model.can_inspect);
/// // true
/// ```
final class WelcomeViewModel {
  /// Creates an immutable welcome presentation model.
  ///
  /// [product_title] must contain nonblank display text.
  ///
  /// [target_id] and [starting_directory] must be provided
  /// together or both be absent.
  ///
  /// When [listing] is provided:
  /// - A target must be configured.
  /// - Its target ID must match [target_id].
  /// - Its directory must match [starting_directory].
  /// - Its layout must be detailed.
  ///
  /// The constructor validates these presentation invariants
  /// without inspecting or changing filesystem state.
  ///
  /// Throws [ArgumentError] for inconsistent input.
  WelcomeViewModel({
    required this.product_title,
    this.target_id,
    this.starting_directory,
    this.listing,
  }) {
    if (product_title.trim().isEmpty) {
      throw ArgumentError.value(
        product_title,
        'product_title',
        'The application title must not be blank.',
      );
    }

    if ((target_id == null) != (starting_directory == null)) {
      throw ArgumentError(
        'Target ID and starting directory must be '
        'provided together.',
      );
    }

    if (target_id != null && target_id!.trim().isEmpty) {
      throw ArgumentError.value(
        target_id,
        'target_id',
        'The target identifier must not be blank.',
      );
    }

    if (starting_directory != null && starting_directory!.trim().isEmpty) {
      throw ArgumentError.value(
        starting_directory,
        'starting_directory',
        'The starting directory must not be blank.',
      );
    }

    final directory_listing = listing;

    if (directory_listing != null) {
      if (directory_listing.target_id != target_id ||
          directory_listing.directory_path != starting_directory) {
        throw ArgumentError(
          'The directory listing must match the '
          'configured target and starting directory.',
        );
      }

      if (directory_listing.layout != DirectoryListingLayout.detailed) {
        throw ArgumentError(
          'The welcome screen requires a detailed '
          'directory listing.',
        );
      }
    }
  }

  /// Display-ready application title.
  ///
  /// Capitalization is determined by the presenter rather
  /// than by the rendering backend.
  final String product_title;

  /// Configured filesystem target identifier, if available.
  final String? target_id;

  /// Target-native starting directory, if available.
  ///
  /// This value is for presentation only.
  /// Renderers must not interpret it as a host filesystem path.
  final String? starting_directory;

  /// Optional detailed filesystem listing presentation.
  ///
  /// Null means no listing was supplied for display.
  ///
  /// A non-null listing may still be incomplete.
  /// Completeness must be determined from the nested model.
  final DirectoryListingViewModel? listing;

  /// Whether a filesystem inspection target is configured.
  bool get can_inspect => target_id != null;

  /// Whether the displayed filesystem listing is incomplete.
  ///
  /// Returns false when no listing is available.
  /// Absence of a listing does not imply that an inspection
  /// was successfully completed.
  bool get has_incomplete_listing => listing?.is_incomplete ?? false;
}
