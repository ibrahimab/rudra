import '../behaviors/workflow_ended_behavior.dart';
import '../behaviors/workflow_start_behavior.dart';
import '../behaviors/workflow_started_behavior.dart';
import '../behaviors/workflow_stop_behavior.dart';

import '../events/workflow_ended_event.dart';
import '../events/workflow_started_event.dart';

import '../states/workflow_lifecycle.dart';

import '../transitions/workflow_outcome_transition.dart';

import 'lifecycle/serialization/workflow_start_serializer.dart';
import 'lifecycle/serialization/workflow_started_serializer.dart';
import 'lifecycle/serialization/workflow_stop_serializer.dart';
import 'lifecycle/serialization/workflow_ended_serializer.dart';

import 'workflow_module.dart';

/// Contributes Rudra's standard workflow lifecycle capabilities.
///
/// The module owns the lifecycle definitions, command behaviors,
/// outcome transitions, and event serializers used for Start and Stop.
///
/// A committed [WorkflowStartedEvent] establishes the active lifecycle.
/// A committed [WorkflowEndedEvent] completes the active workflow.
///
/// The current subclass-based transition definitions remain
/// registered until the coordinated state-machine cutover.
/// They are not used by the new outcome-transition contracts.
///
/// Runtime assembly validates lifecycle references and rejects
/// conflicting registrations before processing begins.
///
/// Example:
/// ```dart
/// final registry = WorkflowModuleRegistry();
/// registry.register(const LifecycleWorkflowModule());
///
/// final runtime = WorkflowRuntime.from_registry(registry);
/// print(runtime.outcome_transitions.length);
/// // 2
/// ```
final class LifecycleWorkflowModule implements WorkflowModule {
  /// Creates the stateless standard lifecycle module.
  const LifecycleWorkflowModule();

  /// Stable identifier of the module owning workflow lifecycle rules.
  @override
  String get module_id => 'rudra.workflow.lifecycle';

  /// Registers the standard lifecycle definitions and behaviors.
  ///
  /// [registration] stages these contributions. The enclosing
  /// registry validates ownership and duplicates atomically.
  ///
  /// The Started outcome establishes a workflow from verified
  /// absence. The Ended outcome is valid only for an active
  /// workflow with a matching workflow identifier.
  ///
  /// Registration performs no I/O and does not process commands.
  @override
  void register(WorkflowModuleRegistration registration) {
    registration
      ..add_lifecycle(
        WorkflowLifecycle(id: 'rudra.workflow.active', is_terminal: false),
      )
      ..add_lifecycle(
        WorkflowLifecycle(id: 'rudra.workflow.ended', is_terminal: true),
      )
      // Existing definitions remain until the engine cutover.
      ..add(const WorkflowStartBehavior())
      ..add(const WorkflowStartedBehavior())
      ..add(const WorkflowStopBehavior())
      ..add(const WorkflowEndedBehavior())
      // Only committed outcomes determine domain lifecycle state.
      ..add_outcome_transition(
        WorkflowOutcomeTransition<WorkflowStartedEvent>(
          source_lifecycle_id: null,
          destination_lifecycle_id: 'rudra.workflow.active',
        ),
      )
      ..add_outcome_transition(
        WorkflowOutcomeTransition<WorkflowEndedEvent>(
          source_lifecycle_id: 'rudra.workflow.active',
          destination_lifecycle_id: 'rudra.workflow.ended',
          guard: (previous, event) {
            if (previous?.identity.workflow_id != event.workflow_id) {
              throw StateError(
                'The workflow-ended outcome refers to '
                'a different established workflow.',
              );
            }
          },
        ),
      )
      ..add_serializer(const WorkflowStartSerializer())
      ..add_serializer(const WorkflowStartedSerializer())
      ..add_serializer(const WorkflowStopSerializer())
      ..add_serializer(const WorkflowEndedSerializer());
  }
}
