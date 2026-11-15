import '../transitions/workflow_ended_transition.dart';
import '../transitions/workflow_start_transition.dart';
import '../transitions/workflow_started_transition.dart';

import 'workflow_module.dart';

/// Contributes the standard workflow lifecycle behavior.
///
/// Owns its transition imports and registration.
final class LifecycleWorkflowModule implements WorkflowModule {
  /// Creates the stateless lifecycle module.
  const LifecycleWorkflowModule();

  @override
  String get module_id => 'rudra.workflow.lifecycle';

  @override
  void register(WorkflowModuleRegistration registration) {
    registration
      ..add_transition(workflow_start_transition())
      ..add_transition(workflow_started_transition())
      ..add_transition(workflow_ended_transition());
  }
}
