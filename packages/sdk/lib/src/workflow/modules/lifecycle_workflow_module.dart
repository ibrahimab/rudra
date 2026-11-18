import '../behaviors/workflow_ended_behavior.dart';
import '../behaviors/workflow_start_behavior.dart';
import '../behaviors/workflow_started_behavior.dart';
import '../behaviors/workflow_stop_behavior.dart';

import 'lifecycle/serialization/workflow_start_serializer.dart';
import 'lifecycle/serialization/workflow_started_serializer.dart';
import 'lifecycle/serialization/workflow_stop_serializer.dart';
import 'lifecycle/serialization/workflow_ended_serializer.dart';

import 'workflow_module.dart';

/// Registers Rudra's standard workflow lifecycle behaviors.
///
/// The module owns its concrete behavior dependencies.
/// Neither WorkflowFlow nor WorkflowStateMachine needs
/// to import individual lifecycle implementations.
final class LifecycleWorkflowModule implements WorkflowModule {
  /// Creates the stateless lifecycle module.
  const LifecycleWorkflowModule();

  @override
  String get module_id => 'rudra.workflow.lifecycle';

  /// Contributes lifecycle transitions, command handling,
  /// and the serializers required to persist lifecycle events.
  @override
  void register(WorkflowModuleRegistration registration) {
    registration
      ..add(const WorkflowStartBehavior())
      ..add(const WorkflowStartedBehavior())
      ..add(const WorkflowStopBehavior())
      ..add(const WorkflowEndedBehavior())
      ..add_serializer(const WorkflowStartSerializer())
      ..add_serializer(const WorkflowStartedSerializer())
      ..add_serializer(const WorkflowStopSerializer())
      ..add_serializer(const WorkflowEndedSerializer());
  }
}
