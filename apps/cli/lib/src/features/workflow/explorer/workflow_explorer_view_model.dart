import 'package:rudra_sdk/rudra_sdk.dart' show WorkflowSnapshot;

/// Immutable workflow presentation state for Explorer.
///
/// Contains the last confirmed workflow snapshot supplied by
/// the application. Absence is represented by a null snapshot.
///
/// The view model exposes simple properties used by Explorer
/// components when rendering workflow information.
///
/// Example:
/// ```dart
/// final view_model = WorkflowExplorerViewModel(
///   current_workflow: restored_workflow,
/// );
///
/// print(view_model.show_start);
/// ```
final class WorkflowExplorerViewModel {
  /// Creates a view model from a confirmed workflow snapshot.
  ///
  /// [current_workflow] is the workflow returned by authoritative
  /// restoration or a completed application operation.
  ///
  /// Null indicates that no unfinished workflow was found.
  const WorkflowExplorerViewModel({required this.current_workflow});

  /// Currently confirmed active workflow, or null when absent.
  ///
  /// This snapshot is read-only. A subsequent observation creates
  /// a new view model rather than modifying this instance.
  final WorkflowSnapshot? current_workflow;

  /// Whether Explorer should display its Start instruction.
  bool get show_start => current_workflow == null;

  /// Whether Explorer should display its Stop instruction.
  bool get show_stop => current_workflow != null;
}
