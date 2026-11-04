import 'package:rudra_sdk/rudra_sdk.dart';

/// Immutable presentation state for Rudra's welcome screen.
///
/// Combines application identity, configured target information,
/// and an optional SDK directory observation.
///
/// This model does not inspect the filesystem or manage sessions.
final class WelcomeModel {
  /// Creates a validated welcome presentation model.
  ///
  /// Target identity and starting directory must appear together.
  /// A supplied listing must describe that same target and path.
  ///
  /// Throws [ArgumentError] for inconsistent presentation state.
  WelcomeModel({
    required this.product_name,
    this.target_id,
    this.starting_directory,
    this.listing,
  }) {
    if (product_name.trim().isEmpty) {
      throw ArgumentError.value(
        product_name,
        'product_name',
        'The product name must not be blank.',
      );
    }

    if ((target_id == null) != (starting_directory == null)) {
      throw ArgumentError(
        'Target ID and starting directory must be supplied together.',
      );
    }

    if (target_id != null && target_id!.trim().isEmpty) {
      throw ArgumentError.value(
        target_id,
        'target_id',
        'The target identifier must not be blank.',
      );
    }

    if (listing != null) {
      if (listing!.target_id != target_id ||
          listing!.directory.value != starting_directory?.value) {
        throw ArgumentError(
          'Directory listing does not match the configured target.',
        );
      }
    }
  }

  /// Human-readable application name.
  final String product_name;

  /// Configured target identifier, if available.
  final String? target_id;

  /// Initial target-native directory.
  final TargetPath? starting_directory;

  /// Read-only SDK observation of the starting directory.
  ///
  /// Null means no directory listing was requested or available.
  final DirectoryListing? listing;

  /// Whether a filesystem inspection target is configured.
  bool get can_inspect => target_id != null;
}
