import '../behaviors/workflow_behavior.dart';
import '../serialization/workflow_event_serializer.dart';
import '../states/workflow_lifecycle.dart';
import '../states/workflow_slice.dart';
import '../transitions/workflow_transition.dart';
import 'workflow_module.dart';

/// Collects workflow capabilities contributed by modules.
///
/// Supports state transitions, command behaviors, and
/// event-specific serialization strategies.
///
/// Each module's registration is staged and validated before
/// any of its contributions become visible.
final class WorkflowModuleRegistry {
  final Set<String> _module_ids = {};
  final List<WorkflowTransitionDefinition> _transitions = [];

  final Map<Type, WorkflowCommandBehavior<dynamic>> _command_behaviors = {};

  /// Registered lifecycle identities.
  final Map<String, WorkflowLifecycle> _lifecycles = {};

  /// Registered slice ownership, indexed by stable identity.
  final Map<String, WorkflowSliceKey<WorkflowSlice>> _slice_keys = {};

  /// Reverse index preventing one slice type from being
  /// registered under multiple identities.
  final Map<Type, String> _slice_ids_by_type = {};

  /// Registered serialization strategies.
  ///
  /// Each serializer exposes its concrete event type
  /// through the non-generic contract.
  final List<WorkflowEventSerializer> _serializers = [];
  final Set<(String, int)> _serializer_keys = {};

  /// Registers all contributions from one workflow module.
  ///
  /// Rejects duplicate module IDs, command handlers, serializer
  /// versions, and inconsistent serializer event identities.
  ///
  /// Failed registrations leave existing contributions unchanged.
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

    // Validate command handler ownership without changing
    // the existing registry.
    final pending_command_types = <Type>{};

    for (final behavior in staging.command_behaviors) {
      final command_type = behavior.command_type;

      if (!pending_command_types.add(command_type) ||
          _command_behaviors.containsKey(command_type)) {
        throw StateError('Duplicate workflow command handler: $command_type');
      }
    }

    // Preserve the mapping between a stable event identifier
    // and its concrete Dart event type across schema versions.
    final known_types = <String, Type>{
      for (final serializer in _serializers)
        serializer.event_type: serializer.dart_type,
    };

    final known_ids = <Type, String>{
      for (final serializer in _serializers)
        serializer.dart_type: serializer.event_type,
    };

    final pending_serializer_keys = <(String, int)>{};

    for (final serializer in staging.serializers) {
      if (serializer.event_type.trim().isEmpty ||
          serializer.schema_version <= 0) {
        throw ArgumentError(
          'Serializer requires a nonblank event type '
          'and a positive schema version.',
        );
      }

      final key = (serializer.event_type, serializer.schema_version);

      if (!pending_serializer_keys.add(key) || _serializer_keys.contains(key)) {
        throw StateError('Duplicate workflow serializer: $key');
      }

      final known_type = known_types[serializer.event_type];

      if (known_type != null && known_type != serializer.dart_type) {
        throw StateError(
          'Event identifier is registered for another Dart type: '
          '${serializer.event_type}',
        );
      }

      final known_id = known_ids[serializer.dart_type];

      if (known_id != null && known_id != serializer.event_type) {
        throw StateError(
          'Dart event type is registered under another event ID: '
          '${serializer.dart_type}',
        );
      }

      known_types[serializer.event_type] = serializer.dart_type;
      known_ids[serializer.dart_type] = serializer.event_type;
    }

    // Validate lifecycle ownership before publishing anything.
    final pending_lifecycles = <String, WorkflowLifecycle>{};

    for (final lifecycle in staging.lifecycles) {
      if (_lifecycles.containsKey(lifecycle.id) ||
          pending_lifecycles.containsKey(lifecycle.id)) {
        throw StateError('Duplicate workflow lifecycle: ${lifecycle.id}');
      }

      pending_lifecycles[lifecycle.id] = lifecycle;
    }

    // Slice identities and types must both have one owner.
    final pending_slice_keys = <String, WorkflowSliceKey<WorkflowSlice>>{};
    final pending_slice_types = <Type, String>{};

    for (final key in staging.slice_keys) {
      if (key.slice_type == WorkflowSlice) {
        throw StateError('Workflow slice ${key.id} requires a concrete type.');
      }

      if (_slice_keys.containsKey(key.id) ||
          pending_slice_keys.containsKey(key.id)) {
        throw StateError('Duplicate workflow slice identifier: ${key.id}');
      }

      if (_slice_ids_by_type.containsKey(key.slice_type) ||
          pending_slice_types.containsKey(key.slice_type)) {
        throw StateError('Duplicate workflow slice type: ${key.slice_type}');
      }

      pending_slice_keys[key.id] = key;
      pending_slice_types[key.slice_type] = key.id;
    }

    // All checks succeeded. Commit the configuration together.
    _transitions.addAll(staging.transitions);

    for (final behavior in staging.command_behaviors) {
      _command_behaviors[behavior.command_type] = behavior;
    }

    _serializers.addAll(staging.serializers);
    _serializer_keys.addAll(pending_serializer_keys);

    _lifecycles.addAll(pending_lifecycles);
    _slice_keys.addAll(pending_slice_keys);
    _slice_ids_by_type.addAll(pending_slice_types);

    _module_ids.add(module_id);
  }

  /// Immutable snapshot of registered transition definitions.
  List<WorkflowTransitionDefinition> get transitions =>
      List.unmodifiable(_transitions);

  /// Immutable snapshot of registered command behaviors.
  Map<Type, WorkflowCommandBehavior<dynamic>> get command_behaviors =>
      Map.unmodifiable(_command_behaviors);

  /// Immutable snapshot of registered event serializers.
  List<WorkflowEventSerializer> get serializers =>
      List.unmodifiable(_serializers);

  /// Immutable snapshot of registered lifecycle definitions.
  Map<String, WorkflowLifecycle> get lifecycles =>
      Map.unmodifiable(_lifecycles);

  /// Immutable snapshot of registered typed slice identities.
  ///
  /// The type-erased registry representation retains each
  /// key's runtime type validation.
  Map<String, WorkflowSliceKey<WorkflowSlice>> get slice_keys =>
      Map.unmodifiable(_slice_keys);

  /// Finds the handler responsible for an exact command type.
  WorkflowCommandBehavior<dynamic>? handler_for({required Type command_type}) {
    return _command_behaviors[command_type];
  }
}

/// Collects one module's contributions before validation.
final class _ModuleRegistration implements WorkflowModuleRegistration {
  final List<WorkflowTransitionDefinition> transitions = [];
  final List<WorkflowCommandBehavior<dynamic>> command_behaviors = [];
  final List<WorkflowEventSerializer> serializers = [];
  final List<WorkflowLifecycle> lifecycles = [];
  final List<WorkflowSliceKey<WorkflowSlice>> slice_keys = [];

  /// Stages a workflow behavior and its optional command handler.
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

  @override
  void add_serializer(WorkflowEventSerializer serializer) {
    serializers.add(serializer);
  }

  @override
  void add_lifecycle(WorkflowLifecycle lifecycle) {
    lifecycles.add(lifecycle);
  }

  @override
  void add_slice<T extends WorkflowSlice>(WorkflowSliceKey<T> key) {
    slice_keys.add(key);
  }
}
