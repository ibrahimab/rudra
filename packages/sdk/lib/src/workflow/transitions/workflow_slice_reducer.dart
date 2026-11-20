import '../events/workflow_event.dart';
import '../states/workflow_slice.dart';
import '../states/workflow_snapshot.dart';

/// Type-erased contract for a registered domain-slice reducer.
///
/// Each reducer owns one typed slice for one concrete outcome
/// event type.
///
/// During a committed transition, reducers evaluate the same
/// previous workflow snapshot. Their proposed values are then
/// assembled into one coherent next snapshot.
///
/// A null reduction result removes the owned slice. A slice
/// without a reducer for the event retains its previous value.
sealed class WorkflowSliceReducerDefinition {
  /// Creates a slice-reducer definition.
  const WorkflowSliceReducerDefinition();

  /// Typed identity of the domain slice owned by this reducer.
  WorkflowSliceKey<WorkflowSlice> get key;

  /// Exact domain-outcome type handled by the reducer.
  Type get event_type;

  /// Computes the next value of the owned slice.
  ///
  /// [previous] is the complete prior workflow snapshot.
  /// [event] is the committed domain outcome.
  ///
  /// Returns a new immutable slice value, or null to remove it.
  ///
  /// The reducer must not mutate the previous snapshot or perform
  /// persistence, filesystem operations, or other side effects.
  WorkflowSlice? apply(WorkflowSnapshot? previous, WorkflowOutcomeEvent event);
}

/// Strongly typed, feature-owned workflow slice reducer.
///
/// [T] identifies the concrete owned slice type.
/// [E] identifies the concrete outcome event type.
///
/// The reducer receives both the previous aggregate snapshot and
/// the previous value of its own slice. It cannot directly replace
/// other slices.
///
/// Example:
/// ```dart
/// final reducer = WorkflowSliceReducer<InspectionSlice, InspectionUpdated>(
///   key: inspection_key,
///   reduce: (previous, event, current) {
///     return InspectionSlice(root: event.root);
///   },
/// );
/// ```
final class WorkflowSliceReducer<
  T extends WorkflowSlice,
  E extends WorkflowOutcomeEvent
>
    extends WorkflowSliceReducerDefinition {
  /// Creates a typed reducer for [key].
  ///
  /// [reduce] computes the replacement value of the owned slice.
  /// Returning null explicitly removes that slice.
  ///
  /// Callback execution is deferred until the state machine
  /// applies a matching committed outcome.
  const WorkflowSliceReducer({required this.key, required this.reduce});

  @override
  final WorkflowSliceKey<T> key;

  /// Pure projection function for the owned slice.
  ///
  /// The arguments are the previous aggregate snapshot, the
  /// matching outcome, and the previous slice value if present.
  final T? Function(WorkflowSnapshot? previous, E event, T? current) reduce;

  @override
  Type get event_type => E;

  /// Evaluates the reducer for its exact registered event type.
  ///
  /// Throws [StateError] for an incompatible event type.
  /// Errors from the reduction function propagate without
  /// modifying the previous snapshot.
  @override
  WorkflowSlice? apply(WorkflowSnapshot? previous, WorkflowOutcomeEvent event) {
    if (event.runtimeType != E) {
      throw StateError(
        'Slice reducer for ${key.id} requires $E, '
        'but received ${event.runtimeType}.',
      );
    }

    final current = previous?.slice(key);
    final next = reduce(previous, event as E, current);

    return next == null ? null : key.require_type(next);
  }
}
