import '../behaviors/workflow_behavior.dart';
import '../transitions/workflow_transition.dart';
import 'workflow_module.dart';

/// Collects workflow behavior definitions from modules.
///
/// Failed module registrations do not modify the registry.
/// Duplicate transition pairs are validated by WorkflowFlow.
final class WorkflowModuleRegistry {
  final Set<String> _module_ids = {};
  final List<WorkflowTransitionDefinition> _transitions = [];

  /// Registers a module atomically at the configuration level.
  ///
  /// Rejects blank or duplicate module identifiers.
  ///
  /// If registration throws, no contributions from that module
  /// are installed.
  void register(WorkflowModule module) {
    final module_id = module.module_id;

    if (module_id.trim().isEmpty) {
      throw ArgumentError.value(module_id, 'module_id');
    }

    if (_module_ids.contains(module_id)) {
      throw StateError('Duplicate workflow module: $module_id');
    }

    final staging = _ModuleRegistration();

    module.register(staging);

    _transitions.addAll(staging.transitions);
    _module_ids.add(module_id);
  }

  /// Immutable snapshot of contributed transitions.
  ///
  /// Each transition comes from a registered behavior.
  List<WorkflowTransitionDefinition> get transitions =>
      List.unmodifiable(_transitions);
}

/// Stages a module's behavior contributions.
///
/// Resolves transition definitions exactly once during
/// registration, before they enter the shared registry.
final class _ModuleRegistration implements WorkflowModuleRegistration {
  final List<WorkflowTransitionDefinition> transitions = [];

  @override
  void add(WorkflowBehavior behavior) {
    transitions.add(behavior.transition);
  }
}
