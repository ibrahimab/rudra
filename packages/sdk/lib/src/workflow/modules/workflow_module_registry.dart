import '../transitions/workflow_transition.dart';
import 'workflow_module.dart';

/// Collects and validates workflow module registrations.
///
/// Module identities must be unique. Contributions are
/// exposed as immutable snapshots.
final class WorkflowModuleRegistry implements WorkflowModuleRegistration {
  final Set<String> _module_ids = {};
  final List<WorkflowTransitionDefinition> _transitions = [];

  /// Registers a module and collects its contributions.
  ///
  /// Rejects blank or duplicate module identifiers.
  void register(WorkflowModule module) {
    final module_id = module.module_id;

    if (module_id.trim().isEmpty) {
      throw ArgumentError.value(module_id, 'module_id');
    }

    if (_module_ids.contains(module_id)) {
      throw StateError('Duplicate workflow module: $module_id');
    }

    // Only commit a module's contributions after its
    // registration completes successfully.
    final staging = _ModuleRegistration();

    module.register(staging);

    _transitions.addAll(staging.transitions);
    _module_ids.add(module_id);
  }

  /// Registers a transition directly.
  ///
  /// Duplicate state/event combinations are validated when
  /// WorkflowFlow is constructed.
  @override
  void add_transition(WorkflowTransitionDefinition transition) {
    _transitions.add(transition);
  }

  /// Returns an immutable snapshot of registered transitions.
  List<WorkflowTransitionDefinition> get transitions =>
      List.unmodifiable(_transitions);
}

/// Temporarily collects one module's contributions.
///
/// Failed module registration cannot partially modify the
/// owning registry.
final class _ModuleRegistration implements WorkflowModuleRegistration {
  final List<WorkflowTransitionDefinition> transitions = [];

  @override
  void add_transition(WorkflowTransitionDefinition transition) {
    transitions.add(transition);
  }
}
