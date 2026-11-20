import '../events/workflow_event.dart';
import '../states/workflow_snapshot.dart';

/// Type-erased contract for a registered domain-outcome transition.
///
/// A transition identifies the lifecycle in which an outcome
/// is permitted and the lifecycle established by that outcome.
///
/// A null [source_lifecycle_id] represents initial workflow
/// establishment, when no workflow snapshot exists yet.
///
/// The workflow state machine owns lifecycle lookup, terminality,
/// identity preservation, version advancement, and construction
/// of the resulting immutable snapshot.
sealed class WorkflowOutcomeTransitionDefinition {
  /// Creates an outcome-transition definition.
  const WorkflowOutcomeTransitionDefinition();

  /// Required source lifecycle, or null for workflow establishment.
  String? get source_lifecycle_id;

  /// Lifecycle established by the outcome.
  String get destination_lifecycle_id;

  /// Exact Dart type of the supported domain outcome.
  Type get event_type;

  /// Evaluates domain-specific transition guards.
  ///
  /// [previous] is the current committed snapshot, if established.
  /// [event] is the outcome being validated.
  ///
  /// A rejected guard must throw before state construction.
  /// Validation must not mutate either argument.
  void validate(WorkflowSnapshot? previous, WorkflowOutcomeEvent event);
}

/// Strongly typed lifecycle transition triggered by a domain outcome.
///
/// [E] is the exact outcome type accepted by the transition.
///
/// Domain behaviors contribute these definitions through the
/// workflow module registry. Transition selection uses both
/// the source lifecycle and the concrete event type.
///
/// Example:
/// ```dart
/// final transition = WorkflowOutcomeTransition<WorkflowEndedEvent>(
///   source_lifecycle_id: 'rudra.workflow.active',
///   destination_lifecycle_id: 'rudra.workflow.ended',
///   guard: (previous, event) {
///     if (previous?.identity.workflow_id != event.workflow_id) {
///       throw StateError('Workflow identity mismatch.');
///     }
///   },
/// );
/// ```
final class WorkflowOutcomeTransition<E extends WorkflowOutcomeEvent>
    extends WorkflowOutcomeTransitionDefinition {
  /// Creates a typed outcome transition.
  ///
  /// [source_lifecycle_id] is null only for initial establishment.
  /// [destination_lifecycle_id] must identify a registered lifecycle.
  /// [guard] optionally validates domain-specific invariants.
  ///
  /// Identifiers must contain non-whitespace characters.
  /// Their original representations are preserved.
  ///
  /// Throws [ArgumentError] for blank lifecycle identifiers.
  WorkflowOutcomeTransition({
    required String? source_lifecycle_id,
    required String destination_lifecycle_id,
    this.guard,
  }) : source_lifecycle_id = _require_optional_id(source_lifecycle_id),
       destination_lifecycle_id = _require_id(destination_lifecycle_id);

  @override
  final String? source_lifecycle_id;

  @override
  final String destination_lifecycle_id;

  /// Optional pure domain guard evaluated before the transition.
  ///
  /// The callback must not perform I/O or modify the supplied state.
  final void Function(WorkflowSnapshot? previous, E event)? guard;

  @override
  Type get event_type => E;

  /// Evaluates the registered typed guard against [event].
  ///
  /// Rejects an unexpected concrete event type instead of relying
  /// on inheritance or a matching string event identifier.
  ///
  /// Exceptions raised by [guard] propagate to the caller.
  @override
  void validate(WorkflowSnapshot? previous, WorkflowOutcomeEvent event) {
    if (event.runtimeType != E) {
      throw StateError(
        'Outcome transition requires $E, '
        'but received ${event.runtimeType}.',
      );
    }

    guard?.call(previous, event as E);
  }

  /// Validates an optional source lifecycle identifier.
  static String? _require_optional_id(String? value) {
    return value == null ? null : _require_id(value);
  }

  /// Validates a lifecycle identifier without normalizing it.
  static String _require_id(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        'lifecycle_id',
        'Lifecycle identifier must not be blank.',
      );
    }

    return value;
  }
}
