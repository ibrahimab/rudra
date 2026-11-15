import '../behaviors/workflow_behavior.dart';
import '../serialization/workflow_event_serializer.dart';

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

  /// Registers an event-specific serialization strategy.
  ///
  /// Multiple versions of the same event type may be registered,
  /// but the same event type and schema version must be unique.
  void add_serializer(WorkflowEventSerializer<dynamic> serializer);
}
