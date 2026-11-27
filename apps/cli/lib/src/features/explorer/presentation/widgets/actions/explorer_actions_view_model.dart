import '../../../application/explorer_model.dart';

/// Immutable presentation state for Explorer's keyboard instructions.
final class ExplorerActionsViewModel {
  /// Creates a keyboard-instruction snapshot.
  ///
  /// [explorer] supplies the current closed state. [instructions] supplies
  /// contributed shortcut hints in display order and is copied on construction.
  ExplorerActionsViewModel({
    required this.explorer,
    Iterable<String> instructions = const [],
  }) : instructions = List<String>.unmodifiable(instructions);

  /// Navigation state associated with the rendered instructions.
  final ExplorerModel explorer;

  /// Visible feature shortcut hints for the current application snapshot.
  final List<String> instructions;
}
