import '../behaviors/workflow_behavior.dart';
import '../transitions/workflow_transition.dart';
import 'workflow_module.dart';

/// Collects transitions and command-capable behaviors.
///
/// Each module contributes behavior instances through one
/// registration method. The registry automatically discovers
/// command handling capabilities from those behaviors.
///
/// Failed registrations do not modify existing contributions.
final class WorkflowModuleRegistry {
  final Set<String> _module_ids = {};
  final List<WorkflowTransitionDefinition> _transitions = [];

  final Map<Type, WorkflowCommandBehavior<dynamic>> _command_behaviors = {};

  /// Registers one workflow module.
  ///
  /// Rejects blank or duplicate module identifiers,
  /// conflicting command handlers, and mismatched
  /// command/transition event types.
  ///
  /// Registration is atomic at the configuration level.
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

    // Validate all handler ownership before committing
    // any staged contribution.
    final pending_types = <Type>{};

    for (final behavior in staging.command_behaviors) {
      final command_type = behavior.command_type;

      if (!pending_types.add(command_type) ||
          _command_behaviors.containsKey(command_type)) {
        throw StateError('Duplicate workflow command handler: $command_type');
      }
    }

    _transitions.addAll(staging.transitions);

    for (final behavior in staging.command_behaviors) {
      _command_behaviors[behavior.command_type] = behavior;
    }

    _module_ids.add(module_id);
  }

  /// Immutable snapshot of registered transitions.
  List<WorkflowTransitionDefinition> get transitions =>
      List.unmodifiable(_transitions);

  /// Immutable snapshot of registered command behaviors.
  Map<Type, WorkflowCommandBehavior<dynamic>> get command_behaviors =>
      Map.unmodifiable(_command_behaviors);

  /// Finds the behavior responsible for a concrete command.
  ///
  /// Returns null for unregistered commands or outcome-only
  /// events.
  WorkflowCommandBehavior<dynamic>? handler_for({required Type command_type}) {
    return _command_behaviors[command_type];
  }
}

/// Stages contributions from a single workflow module.
///
/// Each behavior's transition is resolved once, and a
/// command-capable behavior is registered automatically.
final class _ModuleRegistration implements WorkflowModuleRegistration {
  final List<WorkflowTransitionDefinition> transitions = [];

  final List<WorkflowCommandBehavior<dynamic>> command_behaviors = [];

  @override
  void add(WorkflowBehavior behavior) {
    final transition = behavior.transition;

    if (behavior is WorkflowCommandBehavior<dynamic>) {
      if (transition.trigger_event_type != behavior.command_type) {
        throw StateError(
          'Command behavior and transition event types differ: '
          '${behavior.command_type} / '
          '${transition.trigger_event_type}',
        );
      }

      command_behaviors.add(behavior);
    }

    transitions.add(transition);
  }
}
