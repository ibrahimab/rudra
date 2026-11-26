import 'behaviors/workflow_behavior.dart';

import 'modules/standard_workflow_modules.dart';
import 'modules/workflow_module_registry.dart';

import 'serialization/workflow_event_codec.dart';
import 'serialization/slices/registered_workflow_slice_codec.dart';

import 'states/workflow_lifecycle.dart';
import 'states/workflow_slice.dart';

import 'transitions/workflow_outcome_transition.dart';
import 'transitions/workflow_slice_reducer.dart';

/// Immutable configuration for a Rudra workflow runtime.
///
/// Captures a consistent snapshot of registered command behaviors,
/// outcome transitions, event serializers, lifecycle definitions,
/// typed domain slices, and slice serialization codecs.
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
/// final machine = WorkflowStateMachine(runtime: runtime);
/// ```
final class WorkflowRuntime {
  /// Builds a runtime from a completed module registry.
  ///
  /// Validates lifecycle references and reducer event ownership
  /// after all modules have been registered. This permits
  /// cross-module lifecycle references without imposing a
  /// particular module registration order.
  ///
  /// Throws [StateError] for unknown lifecycle references,
  /// transitions originating from terminal lifecycles, or
  /// reducers referencing unsupported outcome events.
  ///
  /// The resulting runtime captures immutable copies of all
  /// registered capabilities.
  factory WorkflowRuntime.from_registry(WorkflowModuleRegistry registry) {
    final lifecycles = registry.lifecycles;
    final slice_keys = registry.slice_keys;
    final slice_codecs = registry.slice_codecs;
    final outcome_transitions = registry.outcome_transitions;
    final slice_reducers = registry.slice_reducers;

    final supported_outcomes = <Type>{};

    for (final transition in outcome_transitions) {
      final source_id = transition.source_lifecycle_id;
      final destination_id = transition.destination_lifecycle_id;

      // A source lifecycle is optional only for initial
      // establishment. Established terminal workflows cannot
      // transition to another lifecycle.
      if (source_id != null) {
        final source = lifecycles[source_id];

        if (source == null) {
          throw StateError('Unknown source workflow lifecycle: $source_id');
        }

        if (source.is_terminal) {
          throw StateError(
            'Terminal workflow lifecycle cannot be a '
            'transition source: $source_id',
          );
        }
      }

      if (!lifecycles.containsKey(destination_id)) {
        throw StateError(
          'Unknown destination workflow lifecycle: $destination_id',
        );
      }

      supported_outcomes.add(transition.event_type);
    }

    for (final reducer in slice_reducers) {
      final registered_key = slice_keys[reducer.key.id];

      if (registered_key == null ||
          registered_key.slice_type != reducer.key.slice_type) {
        throw StateError(
          'Unregistered workflow reducer slice: ${reducer.key.id}',
        );
      }

      // A reducer cannot define an independently replayable
      // event type. Every event it handles must have a registered
      // lifecycle transition in the same runtime.
      if (!supported_outcomes.contains(reducer.event_type)) {
        throw StateError(
          'No workflow outcome transition registered for '
          'slice reducer event: ${reducer.event_type}',
        );
      }
    }

    return WorkflowRuntime._(
      codec: WorkflowEventCodec.from_registry(registry),
      command_behaviors: registry.command_behaviors,
      lifecycles: lifecycles,
      slice_keys: slice_keys,
      slice_codecs: slice_codecs,
      outcome_transitions: outcome_transitions,
      slice_reducers: slice_reducers,
    );
  }

  /// Immutable lifecycle definitions enabled in this runtime.
  final Map<String, WorkflowLifecycle> lifecycles;

  /// Immutable typed slice ownership enabled in this runtime.
  final Map<String, WorkflowSliceKey<WorkflowSlice>> slice_keys;

  /// Immutable slice serialization configuration enabled in this runtime.
  ///
  /// Keys identify registered domain slices. Each value retains
  /// its concrete codec contract and supported schema version.
  ///
  /// Domain execution may use registered slices without codecs.
  /// State serialization requires complete codec coverage.
  final Map<String, RegisteredWorkflowSliceCodec<WorkflowSlice>> slice_codecs;

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

  /// Captures validated workflow configuration as immutable collections.
  ///
  /// [codec] serializes and restores registered event types.
  /// [command_behaviors] contains the exact-type command handlers.
  /// [lifecycles] defines the registered workflow lifecycles.
  /// [slice_keys] identifies the registered domain slices.
  /// [slice_codecs] contains the validated serialization capabilities
  /// contributed by the owning domain modules.
  /// [outcome_transitions] contains the registered lifecycle rules.
  /// [slice_reducers] contains the feature-owned projection functions.
  ///
  /// Every supplied collection is defensively copied. Subsequent
  /// registrations cannot modify an already constructed runtime.
  ///
  /// Configuration validation occurs in [WorkflowRuntime.from_registry]
  /// before this constructor is called.
  WorkflowRuntime._({
    required this.codec,
    required Map<Type, WorkflowCommandBehavior<dynamic>> command_behaviors,
    required Map<String, WorkflowLifecycle> lifecycles,
    required Map<String, WorkflowSliceKey<WorkflowSlice>> slice_keys,
    required Map<String, RegisteredWorkflowSliceCodec<WorkflowSlice>>
    slice_codecs,
    required List<WorkflowOutcomeTransitionDefinition> outcome_transitions,
    required List<WorkflowSliceReducerDefinition> slice_reducers,
  }) : command_behaviors = Map.unmodifiable(command_behaviors),
       lifecycles = Map.unmodifiable(lifecycles),
       slice_keys = Map.unmodifiable(slice_keys),
       slice_codecs = Map.unmodifiable(slice_codecs),
       outcome_transitions = List.unmodifiable(outcome_transitions),
       slice_reducers = List.unmodifiable(slice_reducers);

  /// Registry-driven codec for durable workflow events.
  final WorkflowEventCodec codec;

  /// Command handlers indexed by their concrete Dart event types.
  final Map<Type, WorkflowCommandBehavior<dynamic>> command_behaviors;

  /// Validated lifecycle transitions driven by committed outcomes.
  ///
  /// Each definition describes an exact source-lifecycle and
  /// outcome-event combination. The collection is immutable.
  ///
  /// These rules become authoritative when the composite
  /// workflow state machine replaces the existing state hierarchy.
  final List<WorkflowOutcomeTransitionDefinition> outcome_transitions;

  /// Registered feature-owned reducers of workflow domain slices.
  ///
  /// Reducers are evaluated against one common previous snapshot
  /// when an outcome is applied. Their results are combined into
  /// one immutable workflow state.
  ///
  /// The collection is immutable and retains registration order.
  final List<WorkflowSliceReducerDefinition> slice_reducers;
}
