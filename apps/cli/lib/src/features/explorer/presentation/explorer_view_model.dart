import 'widgets/directory/explorer_directory_view_model.dart';
import 'widgets/footer/explorer_footer_view_model.dart';
import 'widgets/header/explorer_header_view_model.dart';

/// Immutable composition of Explorer component view models.
///
/// This object exists only to supply a complete presentation
/// snapshot to the Explorer screen renderer.
///
/// It contains no flattened copies of child presentation data.
///
/// Each child widget receives only its corresponding view model:
///
/// - ExplorerHeader receives [header].
/// - ExplorerDirectory receives [directory].
/// - ExplorerFooter receives [footer].
///
/// The screen itself has no filesystem or workflow authority.
///
/// Example:
/// ```dart
/// final screen = ExplorerScreen(
///   ExplorerViewModel(
///     header: header_model,
///     directory: directory_model,
///     footer: footer_model,
///   ),
/// );
/// ```
final class ExplorerViewModel {
  /// Composes independently prepared component presentations.
  ///
  /// All components belong to the same presentation snapshot.
  /// Construction performs no filesystem or terminal operations.
  const ExplorerViewModel({
    required this.header,
    required this.directory,
    required this.footer,
  });

  /// Explorer title and current directory.
  final ExplorerHeaderViewModel header;

  /// Directory entry viewport and selection.
  final ExplorerDirectoryViewModel directory;

  /// Inspection status, summary, and keyboard hints.
  final ExplorerFooterViewModel footer;
}
