import '../behaviors/workflow_ended_behavior.dart';
import '../behaviors/workflow_start_behavior.dart';
import '../behaviors/workflow_started_behavior.dart';
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

  @override
  void register(WorkflowModuleRegistration registration) {
    registration
      ..add(const WorkflowStartBehavior())
      ..add(const WorkflowStartedBehavior())
      ..add(const WorkflowEndedBehavior());
  }
}
