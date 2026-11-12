import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import 'workflow_identity.dart';

/// Contract for events interpreted by the workflow state machine.
///
/// Each event identifies its semantic type using [event_type].
///
/// Events describe requests or established outcomes. They do not
/// independently authorize operations or mutate workflow state.
///
/// Durable event identity, sequence numbers, correlation metadata,
/// and persistence envelopes belong to later implementation blocks.
///
/// New workflow events may implement this contract incrementally.
abstract interface class WorkflowEvent {
  /// Stable semantic identifier of this event type.
  ///
  /// Identifiers must not depend on Dart runtime class names.
  String get event_type;
}

/// Records a request to create a workflow.
///
/// This event does not establish successful workflow creation.
///
/// The requested [target_id] and [root] are retained so the
/// state machine can later verify the successful outcome.
///
/// This event does not claim an authenticated OS user owner.
///
/// Example:
/// ```dart
/// final event = WorkflowStartEvent(
///   target_id: 'local-macos',
///   root: TargetPath('/Users/example/Downloads'),
/// );
/// ```
final class WorkflowStartEvent implements WorkflowEvent {
  /// Creates a workflow-start request.
  ///
  /// Throws [ArgumentError] if [target_id] is blank.
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

  /// Stable event type identifier.
  static const String type_id = 'workflow.start';

  @override
  String get event_type => type_id;

  /// Requested filesystem target identifier.
  final String target_id;

  /// Requested inspection root, using target-native path syntax.
  final TargetPath root;
}

/// Records successful workflow creation.
///
/// The [identity] contains the authoritative workflow identifier
/// and original bindings established by trusted processing.
///
/// This is an outcome event, not a request.
/// It must not be emitted solely because a start request was stored.
///
/// Example:
/// ```dart
/// final event = WorkflowStartedEvent(
///   identity: identity,
/// );
/// ```
final class WorkflowStartedEvent implements WorkflowEvent {
  /// Creates a successful workflow-start outcome.
  ///
  /// The caller must already have established the domain outcome.
  const WorkflowStartedEvent({
    required this.identity,
  });

  /// Stable event type identifier.
  static const String type_id = 'workflow.started';

  @override
  String get event_type => type_id;

  /// Established identity and immutable original bindings.
  final WorkflowIdentity identity;
}

/// Records that an established workflow has ended.
///
/// This is a confirmed terminal outcome, not a request to end.
///
/// The state machine must reject this event unless the workflow
/// is active and its identity matches [workflow_id].
///
/// The actual terminal outcome and any required recovery checks
/// will be introduced with the expanded workflow lifecycle.
///
/// Example:
/// ```dart
/// final event = WorkflowEndedEvent(
///   workflow_id: 'workflow-1',
/// );
/// ```
final class WorkflowEndedEvent implements WorkflowEvent {
  /// Creates a confirmed workflow-ended outcome.
  ///
  /// Throws [ArgumentError] if [workflow_id] is blank.
  WorkflowEndedEvent({
    required this.workflow_id,
  }) {
    if (workflow_id.trim().isEmpty) {
      throw ArgumentError.value(
        workflow_id,
        'workflow_id',
        'The workflow identifier must not be blank.',
      );
    }
  }

  /// Stable event type identifier.
  static const String type_id = 'workflow.ended';

  @override
  String get event_type => type_id;

  /// Identifier of the workflow that has ended.
  final String workflow_id;
}
