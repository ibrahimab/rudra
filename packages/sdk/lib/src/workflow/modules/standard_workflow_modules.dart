import 'workflow_module.dart';
import 'lifecycle_workflow_module.dart';

/// Returns the workflow modules enabled in standard Rudra.
///
/// Feature composition is explicit and deterministic.
///
/// Modules are registered without reflection or runtime
/// filesystem discovery.
List<WorkflowModule> standard_workflow_modules() {
  return [const LifecycleWorkflowModule()];
}
