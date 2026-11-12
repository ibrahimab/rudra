import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import 'workflow_state.dart';

/// State after a workflow-start request has been recorded.
///
/// The requested target and root are retained for validating
/// the eventual successful start outcome.
///
/// This state does not establish an active workflow or a trusted
/// operating-system owner.
///
/// Its version must be positive.
final class WorkflowStartRequestedState extends WorkflowState {
  /// Creates the immutable requested state.
  ///
  /// Throws [ArgumentError] for blank target identifiers or
  /// nonpositive event-derived versions.
  WorkflowStartRequestedState({
    required String target_id,
    required this.root,
    required int version,
  })  : target_id = _require_target_id(target_id),
        version = WorkflowState.require_positive_version(version);

  /// Requested configured filesystem target.
  final String target_id;

  /// Original requested inspection root.
  final TargetPath root;

  @override
  final int version;

  /// Validates a target identifier without normalizing it.
  static String _require_target_id(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        'target_id',
        'The target identifier must not be blank.',
      );
    }

    return value;
  }
}
