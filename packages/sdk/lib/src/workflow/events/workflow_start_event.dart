import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import 'workflow_event.dart';

/// A request to create a new workflow.
///
/// The request identifies the intended filesystem target and
/// inspection root without establishing successful creation.
///
/// It contains no trusted operating-system user identity.
/// Authentication and workflow uniqueness are enforced outside
/// the pure state machine.
///
/// Example:
/// ```dart
/// final event = WorkflowStartEvent(
///   target_id: 'local-macos',
///   root: TargetPath('/Users/example/Downloads'),
/// );
/// ```
final class WorkflowStartEvent implements WorkflowCommandEvent {
  /// Creates a workflow-start request.
  ///
  /// Throws [ArgumentError] if [target_id] is blank.
  /// The original target-native path is preserved.
  WorkflowStartEvent({
    required this.target_id,
    required this.root,
  }) {
    if (target_id.trim().isEmpty) {
      throw ArgumentError.value(
        target_id,
        'target_id',
        'The target identifier must not be blank.',
      );
    }
  }

  /// Stable semantic event type.
  static const String type_id = 'workflow.start';

  @override
  String get event_type => type_id;

  /// Requested configured filesystem target.
  final String target_id;

  /// Requested original inspection root.
  final TargetPath root;
}
