import '../behaviors/workflow_behavior.dart';

import '../serialization/workflow_event_serializer.dart';
import '../serialization/slices/workflow_slice_codec.dart';

import '../states/workflow_lifecycle.dart';
import '../states/workflow_slice.dart';

import '../transitions/workflow_outcome_transition.dart';
import '../transitions/workflow_slice_reducer.dart';

/// A composable contribution to Rudra's workflow engine.
///
/// Modules register their behavior and domain-state contracts
/// without executing them or performing I/O.
abstract interface class WorkflowModule {
  /// Stable identifier unique across registered modules.
  String get module_id;

  /// Contributes this module's workflow contracts.
  ///
  /// All registrations are staged and committed atomically.
  void register(WorkflowModuleRegistration registration);
}

/// Receives contracts contributed by a workflow module.
///
/// Registrations become visible only after the complete module
/// has passed validation. Duplicate ownership fails closed.
abstract interface class WorkflowModuleRegistration {
  /// Registers one typed command behavior.
  void add(WorkflowCommandBehavior<dynamic> behavior);

  /// Registers an event-specific serialization strategy.
  ///
  /// A concrete event may have multiple schema versions, but
  /// the same event identifier and version must be unique.
  void add_serializer(WorkflowEventSerializer serializer);

  /// Registers a module-owned lifecycle phase.
  ///
  /// Lifecycle identifiers must be globally unique within
  /// the runtime, including across separate modules.
  void add_lifecycle(WorkflowLifecycle lifecycle);

  /// Registers ownership of one typed domain-state slice.
  ///
  /// Both the stable identifier and the concrete slice type
  /// must be unique within the runtime.
  void add_slice<T extends WorkflowSlice>(WorkflowSliceKey<T> key);

  /// Registers a feature-owned serialization codec.
  ///
  /// [T] identifies the concrete domain slice represented by [codec].
  /// The contributing module must also declare ownership of the
  /// corresponding typed key through [add_slice].
  ///
  /// A slice may have one configured codec with a positive
  /// schema version.
  ///
  /// Ownership and duplicate registrations are validated before
  /// the module's contributions become visible.
  ///
  /// Registration does not invoke serialization.
  void add_slice_codec<T extends WorkflowSlice>(WorkflowSliceCodec<T> codec);

  /// Registers a lifecycle transition driven by a committed outcome.
  ///
  /// [transition] declares the allowed source lifecycle, the
  /// resulting lifecycle, and the exact outcome event type.
  ///
  /// Duplicate transition pairs are rejected during module
  /// registration. Lifecycle references are verified when the
  /// complete runtime is assembled.
  void add_outcome_transition(WorkflowOutcomeTransitionDefinition transition);

  /// Registers a feature-owned typed domain-slice reducer.
  ///
  /// [reducer] computes changes to a single slice when its
  /// supported outcome event is committed.
  ///
  /// The contributing module must also register ownership of
  /// that slice through [add_slice]. Duplicate reducer pairs
  /// are rejected during module registration.
  void add_slice_reducer(WorkflowSliceReducerDefinition reducer);
}
