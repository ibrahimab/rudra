import 'behaviors/workflow_behavior.dart';
import 'modules/standard_workflow_modules.dart';
import 'modules/workflow_module_registry.dart';
import 'serialization/workflow_event_codec.dart';
import 'workflow_flow.dart';

/// Immutable configuration for a Rudra workflow runtime.
///
/// Captures a consistent snapshot of registered command behaviors,
/// state transitions, and event serializers.
///
/// The same instance should be supplied to workflow processing
/// and persistence composition. This prevents those components
/// from independently selecting different workflow rules.
///
/// Modules are registered before constructing the runtime.
/// Subsequent changes to the registry do not modify this snapshot.
///
/// Construction performs no persistence or filesystem operations.
///
/// Example:
/// ```dart
/// final runtime = WorkflowRuntime.standard();
///
/// final machine = WorkflowStateMachine(flow: runtime.flow);
/// ```
final class WorkflowRuntime {
  /// Builds a runtime from an explicitly configured registry.
  ///
  /// Registration is complete at this boundary. The runtime
  /// validates and snapshots the transition graph and serializers.
  factory WorkflowRuntime.from_registry(WorkflowModuleRegistry registry) {
    return WorkflowRuntime._(
      flow: WorkflowFlow(transitions: registry.transitions),
      codec: WorkflowEventCodec.from_registry(registry),
      command_behaviors: registry.command_behaviors,
    );
  }

  /// Creates the standard Rudra workflow configuration.
  ///
  /// All standard modules are registered into one registry
  /// before any runtime components are constructed.
  factory WorkflowRuntime.standard() {
    final registry = WorkflowModuleRegistry();

    for (final module in standard_workflow_modules()) {
      registry.register(module);
    }

    return WorkflowRuntime.from_registry(registry);
  }

  /// Stores validated, immutable runtime components.
  WorkflowRuntime._({
    required this.flow,
    required this.codec,
    required Map<Type, WorkflowCommandBehavior<dynamic>> command_behaviors,
  }) : command_behaviors = Map.unmodifiable(command_behaviors);

  /// Immutable state-transition graph.
  final WorkflowFlow flow;

  /// Registry-driven codec for durable workflow events.
  final WorkflowEventCodec codec;

  /// Command handlers indexed by their concrete Dart event types.
  final Map<Type, WorkflowCommandBehavior<dynamic>> command_behaviors;
}
