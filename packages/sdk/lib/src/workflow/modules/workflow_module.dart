import '../behaviors/workflow_behavior.dart';

/// A composable contribution to Rudra's workflow engine.
///
/// Modules register their behaviors without executing them.
abstract interface class WorkflowModule {
  /// Stable identifier unique across registered modules.
  String get module_id;

  /// Contributes this module's workflow behaviors.
  ///
  /// Registration must not perform persistence or I/O.
  void register(WorkflowModuleRegistration registration);
}

/// Receives behaviors contributed by a workflow module.
///
/// All contributions are collected before the module
/// registration is committed.
abstract interface class WorkflowModuleRegistration {
  /// Registers one self-contained workflow behavior.
  void add(WorkflowBehavior behavior);
}
