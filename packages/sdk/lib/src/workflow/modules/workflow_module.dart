import '../transitions/workflow_transition.dart';

/// A composable contribution to Rudra's workflow engine.
///
/// Modules declare their behavior through a registration
/// interface rather than depending on the engine itself.
abstract interface class WorkflowModule {
  /// Stable identifier unique across registered modules.
  String get module_id;

  /// Registers the behavior provided by this module.
  ///
  /// Registration must not execute domain operations or
  /// perform persistence or filesystem I/O.
  void register(WorkflowModuleRegistration registration);
}

/// Receives behavior contributed by workflow modules.
///
/// Additional registration capabilities, such as command
/// handlers, can be introduced as they are implemented.
abstract interface class WorkflowModuleRegistration {
  /// Registers a typed state transition.
  void add_transition(WorkflowTransitionDefinition transition);
}
