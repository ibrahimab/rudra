import '../../../../../core/rendering/widgets/terminal_widget.dart';

import '../../../application/explorer_model.dart';

/// Immutable presentation state for the Explorer header.
final class ExplorerHeaderViewModel {
  /// Creates the header presentation snapshot.
  ///
  /// [explorer] supplies the displayed directory. [statuses] supplies the
  /// contributed status text in display order and is copied on construction.
  ExplorerHeaderViewModel({
    required this.explorer,
    Iterable<TerminalLine> statuses = const [],
  }) : statuses = List<TerminalLine>.unmodifiable(statuses);

  /// Navigation snapshot associated with the displayed header.
  final ExplorerModel explorer;

  /// Contributed text for the header's single status row.
  final List<TerminalLine> statuses;
}
