import 'behaviors/workflow_behavior.dart';
import 'events/workflow_event.dart';
import 'modules/workflow_module_registry.dart';
import 'workflow_flow.dart';
import 'workflow_processing_store.dart';
import 'workflow_state_machine.dart';

/// Processes accepted workflow commands through registered
/// behaviors and a deterministic workflow state machine.
///
/// This service does not:
/// - Know concrete workflow command implementations.
/// - Generate or authenticate workflow identities.
/// - Execute filesystem operations.
/// - Access SQLite directly.
///
/// Durable commitment belongs exclusively to the injected store.
final class WorkflowProcessor {
  /// Creates a processor from registered module contributions.
  ///
  /// Handler and transition registrations are snapshotted
  /// together during construction.
  WorkflowProcessor({
    required WorkflowModuleRegistry registry,
    required WorkflowProcessingStore store,
  }) : _store = store,
       _handlers = Map.unmodifiable(registry.command_behaviors),
       _machine = WorkflowStateMachine(
         flow: WorkflowFlow(transitions: registry.transitions),
       );

  /// Durable processing boundary.
  final WorkflowProcessingStore _store;

  /// Exact-type command dispatch registry.
  final Map<Type, WorkflowCommandBehavior<dynamic>> _handlers;

  /// Deterministic domain transition engine.
  final WorkflowStateMachine _machine;

  /// Processes the next pending command, if one exists.
  ///
  /// Returns null when the inbox is empty.
  ///
  /// The returned plan has been committed by the persistence
  /// adapter. Validation or persistence failures propagate
  /// without claiming success.
  Future<WorkflowProcessingPlan?> process_next() async {
    final pending = await _store.next_pending();

    if (pending == null) {
      return null;
    }

    final behavior = _handlers[pending.command.runtimeType];

    if (behavior == null) {
      throw StateError(
        'No workflow command behavior registered for '
        '${pending.command.runtimeType}.',
      );
    }

    // Reconstruct the authoritative state from committed history.
    final previous_state = _machine.replay(pending.committed_events);

    // Reject invalid commands before generating outcomes.
    var next_state = _machine.transition(
      state: previous_state,
      event: pending.command,
    );

    final outcomes = behavior.propose_outcomes(
      pending.command,
      identity: pending.identity,
    );

    if (outcomes.isEmpty) {
      throw StateError('A workflow command handler must propose an outcome.');
    }

    // Outcome handlers may not recursively submit commands.
    if (outcomes.any((event) => event is WorkflowCommandEvent)) {
      throw StateError(
        'A workflow command handler cannot emit command events.',
      );
    }

    // Validate every outcome before requesting persistence.
    for (final outcome in outcomes) {
      next_state = _machine.transition(state: next_state, event: outcome);
    }

    final events = <WorkflowEvent>[pending.command, ...outcomes];

    final plan = WorkflowProcessingPlan(
      submission: pending,
      previous_state: previous_state,
      resulting_state: next_state,
      events_to_append: events,
    );

    // This must be one atomic transaction in the concrete
    // persistence adapter. No success is returned beforehand.
    await _store.commit(plan);

    return plan;
  }
}
