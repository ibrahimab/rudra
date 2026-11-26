import '../behaviors/workflow_behavior.dart';

import '../serialization/workflow_event_serializer.dart';
import '../serialization/slices/workflow_slice_codec.dart';
import '../serialization/slices/registered_workflow_slice_codec.dart';

import '../states/workflow_lifecycle.dart';
import '../states/workflow_slice.dart';

import '../transitions/workflow_outcome_transition.dart';
import '../transitions/workflow_slice_reducer.dart';

import 'workflow_module.dart';

/// Collects and validates workflow capabilities contributed by SDK modules.
///
/// Each [WorkflowModule] contributes command behaviors, outcome transitions,
/// event serializers, lifecycle definitions, typed domain-slice identities,
/// and feature-owned slice serialization codecs.
///
/// Module registration is staged before validation. A failed registration
/// leaves previously accepted capabilities unchanged and does not reserve
/// the rejected module's identifier.
///
/// Identifiers and types are checked for conflicting ownership.
/// Outcome/lifecycle pairs must be unique.
///
/// Public collection getters return immutable snapshots. A previously
/// obtained collection is unaffected by subsequent registrations.
///
/// Example:
/// ```dart
/// final registry = WorkflowModuleRegistry();
///
/// registry.register(const LifecycleWorkflowModule());
///
/// final runtime = WorkflowRuntime.from_registry(registry);
/// ```
final class WorkflowModuleRegistry {
  /// Creates an empty workflow module registry.
  ///
  /// Modules are registered explicitly through [register].
  /// Each registry instance maintains independent registrations.
  WorkflowModuleRegistry();

  /// Identifiers of successfully registered modules.
  ///
  /// A module identifier is reserved only after all its
  /// contributions have passed registration validation.
  final Set<String> _module_ids = {};

  /// Command behaviors indexed by their exact Dart command type.
  ///
  /// Each command type has at most one registered handler.
  final Map<Type, WorkflowCommandBehavior<dynamic>> _command_behaviors = {};

  /// Lifecycle definitions indexed by their stable identifiers.
  ///
  /// Each identifier belongs to exactly one registered module.
  final Map<String, WorkflowLifecycle> _lifecycles = {};

  /// Domain-slice keys indexed by their stable identifiers.
  ///
  /// The generic base type permits heterogeneous key storage.
  /// Each key retains its concrete slice type for runtime validation.
  final Map<String, WorkflowSliceKey<WorkflowSlice>> _slice_keys = {};

  /// Reverse index of concrete slice types to their registered IDs.
  ///
  /// Prevents separate modules from registering the same slice type
  /// under different identifiers.
  final Map<Type, String> _slice_ids_by_type = {};

  /// Feature-owned serialization codecs indexed by stable slice identifiers.
  ///
  /// Each registered slice may have one configured codec.
  /// Registrations retain their concrete typed invocation boundaries.
  final Map<String, RegisteredWorkflowSliceCodec<WorkflowSlice>> _slice_codecs =
      {};

  /// Outcome-driven lifecycle transitions contributed by modules.
  ///
  /// The runtime validates referenced lifecycle definitions
  /// after all modules have been registered.
  final List<WorkflowOutcomeTransitionDefinition> _outcome_transitions = [];

  /// Registered source-lifecycle and outcome-event combinations.
  ///
  /// A null source lifecycle represents workflow establishment.
  final Set<(String?, Type)> _outcome_transition_pairs = {};

  /// Feature-owned reducers of immutable workflow domain slices.
  ///
  /// Each reducer changes one registered slice for one event type.
  final List<WorkflowSliceReducerDefinition> _slice_reducers = [];

  /// Registered slice-identifier and outcome-event combinations.
  ///
  /// Each combination has exactly one contributing reducer.
  final Set<(String, Type)> _slice_reducer_pairs = {};

  /// Event serializers contributed by registered modules.
  ///
  /// Multiple schema versions may exist for one event type,
  /// provided each event-type/version combination is unique.
  final List<WorkflowEventSerializer> _serializers = [];

  /// Registered event-type and schema-version combinations.
  ///
  /// Used to reject duplicate serializer registrations without
  /// discarding historical schema versions.
  final Set<(String, int)> _serializer_keys = {};

  /// Atomically registers the capabilities contributed by [module].
  ///
  /// The module's [WorkflowModule.register] method contributes definitions
  /// into a temporary staging area. All ownership and identifier checks
  /// complete before any contribution becomes visible in this registry.
  ///
  /// Throws [ArgumentError] for an empty module identifier or invalid
  /// event serializer or slice codec schema metadata.
  ///
  /// Throws [StateError] for duplicate module identifiers, command
  /// handlers, lifecycle identifiers, slice identifiers or slice types,
  /// conflicting serializer identities, duplicate slice codecs,
  /// incompatible slice codec types, duplicate outcome-transition pairs,
  /// duplicate slice-reducer pairs, or codecs and reducers referencing
  /// slices not owned by the contributing module.
  ///
  /// Exceptions raised by the module during registration propagate
  /// without modifying previously accepted registrations.
  ///
  /// Successful registration performs no workflow processing or
  /// persistence operations.
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

    // Validate command ownership before publishing any contributions.
    final pending_command_types = <Type>{};

    for (final behavior in staging.command_behaviors) {
      final command_type = behavior.command_type;

      if (!pending_command_types.add(command_type) ||
          _command_behaviors.containsKey(command_type)) {
        throw StateError('Duplicate workflow command handler: $command_type');
      }
    }

    // Maintain a one-to-one relationship between stable event IDs
    // and Dart event types across all serializer schema versions.
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

      // Include earlier contributions from this same module when
      // validating subsequent serializer registrations.
      known_types[serializer.event_type] = serializer.dart_type;
      known_ids[serializer.dart_type] = serializer.event_type;
    }

    // Lifecycle ownership is exclusive, even when two modules
    // contribute definitions with otherwise identical values.
    final pending_lifecycles = <String, WorkflowLifecycle>{};

    for (final lifecycle in staging.lifecycles) {
      if (_lifecycles.containsKey(lifecycle.id) ||
          pending_lifecycles.containsKey(lifecycle.id)) {
        throw StateError('Duplicate workflow lifecycle: ${lifecycle.id}');
      }

      pending_lifecycles[lifecycle.id] = lifecycle;
    }

    // Enforce uniqueness in both directions: one registered ID
    // per slice type, and one registered slice type per ID.
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

    // A serialization codec belongs exclusively to the module
    // declaring ownership of its corresponding domain slice.
    // Validate against all staged keys, independent of call order.
    final pending_slice_codecs =
        <String, RegisteredWorkflowSliceCodec<WorkflowSlice>>{};

    for (final codec in staging.slice_codecs) {
      final key = codec.key;
      final owned_key = pending_slice_keys[key.id];

      if (owned_key == null || owned_key != key) {
        throw StateError(
          'Workflow module $module_id does not own '
          'codec slice ${key.id}.',
        );
      }

      if (_slice_codecs.containsKey(key.id) ||
          pending_slice_codecs.containsKey(key.id)) {
        throw StateError('Duplicate workflow slice codec: ${key.id}');
      }

      pending_slice_codecs[key.id] = codec;
    }

    // An exact lifecycle/event pair must have one transition.
    // The same event may have different transitions from
    // different source lifecycles.
    final pending_outcome_pairs = <(String?, Type)>{};

    for (final transition in staging.outcome_transitions) {
      final pair = (transition.source_lifecycle_id, transition.event_type);

      if (!pending_outcome_pairs.add(pair) ||
          _outcome_transition_pairs.contains(pair)) {
        throw StateError('Duplicate workflow outcome transition: $pair');
      }
    }

    // A module may reduce only a slice it declares ownership of.
    // Validate ownership independently of staging call order.
    final pending_reducer_pairs = <(String, Type)>{};

    for (final reducer in staging.slice_reducers) {
      final owned_key = pending_slice_keys[reducer.key.id];

      if (owned_key == null || owned_key.slice_type != reducer.key.slice_type) {
        throw StateError(
          'Workflow module $module_id does not own '
          'reducer slice ${reducer.key.id}.',
        );
      }

      final pair = (reducer.key.id, reducer.event_type);

      if (!pending_reducer_pairs.add(pair) ||
          _slice_reducer_pairs.contains(pair)) {
        throw StateError('Duplicate workflow slice reducer: $pair');
      }
    }

    // Every validation has passed. Publish the staged contributions
    // together so registration failures cannot leave partial ownership.
    for (final behavior in staging.command_behaviors) {
      _command_behaviors[behavior.command_type] = behavior;
    }

    _serializers.addAll(staging.serializers);
    _serializer_keys.addAll(pending_serializer_keys);

    _lifecycles.addAll(pending_lifecycles);
    _slice_keys.addAll(pending_slice_keys);
    _slice_ids_by_type.addAll(pending_slice_types);
    _slice_codecs.addAll(pending_slice_codecs);

    _outcome_transitions.addAll(staging.outcome_transitions);
    _outcome_transition_pairs.addAll(pending_outcome_pairs);

    _slice_reducers.addAll(staging.slice_reducers);
    _slice_reducer_pairs.addAll(pending_reducer_pairs);

    _module_ids.add(module_id);
  }

  /// Returns an immutable snapshot of registered command behaviors.
  ///
  /// Keys are concrete Dart command types. A command can have only
  /// one handler within the configured runtime.
  ///
  /// Subsequent registrations do not modify the returned map.
  Map<Type, WorkflowCommandBehavior<dynamic>> get command_behaviors =>
      Map.unmodifiable(_command_behaviors);

  /// Returns an immutable snapshot of event serializer registrations.
  ///
  /// The collection includes all registered schema versions,
  /// including historical versions retained for event decoding.
  ///
  /// Subsequent registrations do not modify the returned list.
  List<WorkflowEventSerializer> get serializers =>
      List.unmodifiable(_serializers);

  /// Returns an immutable snapshot of registered lifecycle definitions.
  ///
  /// Keys are stable lifecycle identifiers. Each definition contains
  /// its lifecycle identity and terminality.
  ///
  /// Subsequent registrations do not modify the returned map.
  Map<String, WorkflowLifecycle> get lifecycles =>
      Map.unmodifiable(_lifecycles);

  /// Returns an immutable snapshot of registered domain-slice keys.
  ///
  /// Keys are stable slice identifiers. The heterogeneous collection
  /// uses the [WorkflowSlice] base type, while each
  /// [WorkflowSliceKey] retains its declared concrete type.
  ///
  /// Subsequent registrations do not modify the returned map.
  Map<String, WorkflowSliceKey<WorkflowSlice>> get slice_keys =>
      Map.unmodifiable(_slice_keys);

  /// Returns an immutable snapshot of registered slice codecs.
  ///
  /// Keys are stable domain-slice identifiers. Each registration
  /// preserves its concrete slice type and supported schema version.
  ///
  /// Subsequent registrations do not modify the returned map.
  Map<String, RegisteredWorkflowSliceCodec<WorkflowSlice>> get slice_codecs =>
      Map.unmodifiable(_slice_codecs);

  /// Returns an immutable snapshot of outcome lifecycle transitions.
  ///
  /// Definitions are retained in registration order, but this
  /// ordering does not determine transition precedence.
  ///
  /// Each definition identifies one source lifecycle and one
  /// concrete committed outcome event type.
  List<WorkflowOutcomeTransitionDefinition> get outcome_transitions =>
      List.unmodifiable(_outcome_transitions);

  /// Returns an immutable snapshot of registered slice reducers.
  ///
  /// Reducers retain their owning typed slice identities.
  /// Multiple features may reduce different slices for the same
  /// outcome event without introducing write conflicts.
  ///
  /// Subsequent registrations do not modify the returned list.
  List<WorkflowSliceReducerDefinition> get slice_reducers =>
      List.unmodifiable(_slice_reducers);

  /// Finds the command behavior registered for [command_type].
  ///
  /// Matching uses exact Dart types, without inheritance-based
  /// fallback or registration-order precedence.
  ///
  /// Returns the registered behavior, or `null` when the
  /// command type has no handler.
  ///
  /// Lookup does not execute the handler or modify the registry.
  WorkflowCommandBehavior<dynamic>? handler_for({required Type command_type}) {
    return _command_behaviors[command_type];
  }
}

/// Collects one module's contributions before registry validation.
///
/// This mutable staging area belongs to a single call to
/// [WorkflowModuleRegistry.register]. It preserves the module's
/// submitted definitions until they can be validated together.
///
/// Successful validation copies the contributions into the registry.
/// A failed registration discards the staging area.
final class _ModuleRegistration implements WorkflowModuleRegistration {
  /// Creates an empty staging area for one module registration.
  ///
  /// The enclosing registry owns its lifetime and validation.
  _ModuleRegistration();

  /// Command behaviors contributed by this module.
  ///
  /// Exact command type ownership is validated by the enclosing registry.
  final List<WorkflowCommandBehavior<dynamic>> command_behaviors = [];

  /// Event serializers awaiting identity and schema validation.
  ///
  /// Multiple versions of the same event may be contributed,
  /// subject to unique event-type/version combinations.
  final List<WorkflowEventSerializer> serializers = [];

  /// Lifecycle definitions awaiting identifier validation.
  ///
  /// Each lifecycle must have exclusive ownership within
  /// the completed workflow runtime.
  final List<WorkflowLifecycle> lifecycles = [];

  /// Typed domain-slice identities awaiting ownership validation.
  ///
  /// The base-type collection retains the generic key instances,
  /// including their concrete slice-type information.
  final List<WorkflowSliceKey<WorkflowSlice>> slice_keys = [];

  /// Typed slice codecs awaiting module ownership validation.
  ///
  /// Each registration retains the concrete codec type and
  /// captured serialization metadata.
  final List<RegisteredWorkflowSliceCodec<WorkflowSlice>> slice_codecs = [];

  /// Outcome lifecycle transitions staged by this module.
  ///
  /// Duplicate pairs are validated before publication.
  /// Referenced lifecycle definitions are resolved at runtime
  /// assembly after all modules have contributed their contracts.
  final List<WorkflowOutcomeTransitionDefinition> outcome_transitions = [];

  /// Typed domain-slice reducers staged by this module.
  ///
  /// Every reducer must refer to a slice key registered by
  /// this same module. Ownership is validated before publication.
  final List<WorkflowSliceReducerDefinition> slice_reducers = [];

  /// Stages one typed command behavior.
  ///
  /// Duplicate ownership is validated by the enclosing registry
  /// before the module's contributions become visible.
  @override
  void add(WorkflowCommandBehavior<dynamic> behavior) {
    command_behaviors.add(behavior);
  }

  /// Stages [serializer] for the module's event serialization contract.
  ///
  /// Identifier consistency, schema-version validity, and duplicate
  /// registrations are checked by the enclosing registry.
  ///
  /// This method appends the serializer without executing it.
  @override
  void add_serializer(WorkflowEventSerializer serializer) {
    serializers.add(serializer);
  }

  /// Stages a module-owned [lifecycle] definition.
  ///
  /// The enclosing registry verifies that its stable identifier
  /// is not already owned by another registered or pending lifecycle.
  @override
  void add_lifecycle(WorkflowLifecycle lifecycle) {
    lifecycles.add(lifecycle);
  }

  /// Stages a typed domain-state slice identity.
  ///
  /// [T] identifies the concrete [WorkflowSlice] contract owned
  /// by the contributing module.
  /// [key] provides the stable identifier and retains the declared type
  /// for subsequent validation.
  ///
  /// The enclosing registry rejects duplicate identifiers, duplicate
  /// concrete types, and keys declared for the base [WorkflowSlice].
  @override
  void add_slice<T extends WorkflowSlice>(WorkflowSliceKey<T> key) {
    slice_keys.add(key);
  }

  /// Stages a feature-owned serialization [codec].
  ///
  /// [T] preserves the concrete slice contract when the codec
  /// is placed into the heterogeneous staging collection.
  ///
  /// Invalid codec metadata throws during registration construction.
  /// Module ownership and duplicate registrations are validated
  /// by the enclosing registry before publication.
  ///
  /// This method does not invoke encoding or decoding.
  @override
  void add_slice_codec<T extends WorkflowSlice>(WorkflowSliceCodec<T> codec) {
    slice_codecs.add(RegisteredWorkflowSliceCodec<T>(codec: codec));
  }

  /// Stages an outcome-driven lifecycle transition.
  ///
  /// [transition] declares the source lifecycle, destination
  /// lifecycle, and exact event type accepted by the rule.
  ///
  /// Duplicate pairs are checked by the enclosing registry.
  /// Cross-module lifecycle references are resolved when the
  /// complete workflow runtime is constructed.
  @override
  void add_outcome_transition(WorkflowOutcomeTransitionDefinition transition) {
    outcome_transitions.add(transition);
  }

  /// Stages a reducer for one module-owned domain slice.
  ///
  /// [reducer] supplies the typed slice key and exact outcome
  /// type responsible for invoking its pure reduction callback.
  ///
  /// The enclosing registry verifies slice ownership and
  /// duplicate reducer pairs before accepting the module.
  @override
  void add_slice_reducer(WorkflowSliceReducerDefinition reducer) {
    slice_reducers.add(reducer);
  }
}
