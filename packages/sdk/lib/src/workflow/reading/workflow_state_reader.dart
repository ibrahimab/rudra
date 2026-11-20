import '../events/workflow_event.dart';
import '../states/workflow_snapshot.dart';
import '../workflow_runtime.dart';
import '../workflow_state_machine.dart';
import '../workflow_transition_exception.dart';
import 'workflow_history_store.dart';

/// Stable categories of rejected workflow restoration evidence.
///
/// A failed restoration cannot be interpreted as an absent workflow.
enum WorkflowStateReadErrorCode {
  /// Projected or committed identity belongs to another OS user.
  ownership_mismatch,

  /// Journal sequence, version or metadata is inconsistent.
  invalid_journal,

  /// A committed outcome could not be decoded correctly.
  invalid_event,

  /// Replayed domain outcomes violate state-machine invariants.
  invalid_history,

  /// Unfinished ownership projection disagrees with the journal.
  projection_mismatch,

  /// A nonterminal history has no matching owner projection.
  orphaned_workflow,
}

/// One validated unfinished workflow and its committed outcome history.
///
/// The snapshot and outcomes originate from consistent persistence evidence.
/// Reading or constructing the result never authorizes a workflow mutation.
final class WorkflowUnfinishedHistory {
  /// Freezes an authoritative snapshot and ordered domain outcomes.
  WorkflowUnfinishedHistory({
    required this.state,
    required Iterable<WorkflowOutcomeEvent> events,
  }) : events = List<WorkflowOutcomeEvent>.unmodifiable(events) {
    if (state.is_terminal) {
      throw ArgumentError.value(
        state,
        'state',
        'A current unfinished workflow cannot be terminal.',
      );
    }
  }

  /// Last committed nonterminal workflow snapshot.
  final WorkflowSnapshot state;

  /// Committed domain outcomes in workflow-version order.
  final List<WorkflowOutcomeEvent> events;
}

/// Typed failure to restore authoritative workflow state.
///
/// Restoration failures are read-only and never trigger automatic repair.
final class WorkflowStateReadException implements Exception {
  /// Creates an integrity failure, optionally referencing a journal event.
  const WorkflowStateReadException({
    required this.code,
    required this.message,
    this.event_index,
  });

  /// Machine-readable restoration error classification.
  final WorkflowStateReadErrorCode code;

  /// Diagnostic text without serialized payloads.
  final String message;

  /// Zero-based journal position if the error concerns an outcome.
  final int? event_index;

  @override
  String toString() =>
      'WorkflowStateReadException(${code.name}, '
      'event_index: $event_index): $message';
}

/// Validates owner-scoped persistence evidence using one workflow runtime.
///
/// Committed outcomes reconstruct immutable [WorkflowSnapshot] values.
/// Corrupt, foreign, stale and orphaned histories fail closed.
/// The reader performs no writes or command processing.
final class WorkflowStateReader {
  /// Creates a reader for an authenticated OS-user identity.
  ///
  /// [runtime] must match the processor and persistence committer.
  /// [history_store] supplies a consistent owner-scoped journal snapshot.
  WorkflowStateReader({
    required WorkflowRuntime runtime,
    required WorkflowHistoryStore history_store,
    required String os_user_id,
  }) : _runtime = runtime,
       _history_store = history_store,
       _os_user_id = _require_os_user_id(os_user_id),
       _machine = WorkflowStateMachine(runtime: runtime);

  /// Runtime providing the codec and registered domain transition rules.
  final WorkflowRuntime _runtime;

  /// Read-only owner-scoped history evidence boundary.
  final WorkflowHistoryStore _history_store;

  /// Trusted operating-system user identifying the current owner.
  final String _os_user_id;

  /// Single authoritative outcome-only replay engine.
  final WorkflowStateMachine _machine;

  /// Restores a verified unfinished workflow or verified absence.
  ///
  /// Returns null only when no incomplete workflow exists and all
  /// discoverable owner histories have passed integrity validation.
  /// Missing projections, invalid events and foreign ownership throw.
  Future<WorkflowUnfinishedHistory?> current() async {
    final evidence = await _history_store.load_restoration_evidence(
      os_user_id: _os_user_id,
    );
    final projected = evidence.projected;

    // Check every owner-indexed journal, including when no projection exists.
    // Otherwise a deleted projection could silently hide active ownership.
    final seen_ids = <String>{
      if (projected != null) projected.projected_identity.workflow_id,
    };

    for (final history in evidence.other_histories) {
      if (!seen_ids.add(history.workflow_id)) {
        throw const WorkflowStateReadException(
          code: WorkflowStateReadErrorCode.invalid_journal,
          message: 'Duplicate workflow history in restoration evidence.',
        );
      }
      final state = _replay_history(history).state;

      if (state.identity.os_user_id != _os_user_id) {
        throw const WorkflowStateReadException(
          code: WorkflowStateReadErrorCode.ownership_mismatch,
          message: 'Owner index disagrees with committed workflow identity.',
        );
      }
      if (!state.is_terminal) {
        throw const WorkflowStateReadException(
          code: WorkflowStateReadErrorCode.orphaned_workflow,
          message: 'Unfinished history has no ownership projection.',
        );
      }
    }

    if (projected == null) return null;
    final identity = projected.projected_identity;

    if (identity.os_user_id != _os_user_id) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.ownership_mismatch,
        message: 'The current workflow projection belongs to another user.',
      );
    }

    final restored = _replay_history(
      WorkflowHistoryJournal(
        workflow_id: identity.workflow_id,
        journal: projected.journal,
      ),
    );
    final snapshot = restored.state;

    if (snapshot.is_terminal) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.projection_mismatch,
        message: 'A terminal history still owns an unfinished projection.',
      );
    }

    if (snapshot.identity.os_user_id != _os_user_id) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.ownership_mismatch,
        message: 'Replayed workflow belongs to another OS user.',
      );
    }

    if (snapshot.version != projected.projected_version ||
        snapshot.identity.workflow_id != identity.workflow_id ||
        snapshot.identity.target_id != identity.target_id ||
        snapshot.identity.root.value != identity.root.value) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.projection_mismatch,
        message: 'Unfinished projection disagrees with committed history.',
      );
    }

    return WorkflowUnfinishedHistory(state: snapshot, events: restored.events);
  }

  /// Decodes and validates a single complete outcome-only journal.
  ///
  /// Both projected and owner-indexed histories take this same route.
  /// Every event's sequence, local version and workflow ownership is checked.
  ({WorkflowSnapshot state, List<WorkflowOutcomeEvent> events}) _replay_history(
    WorkflowHistoryJournal history,
  ) {
    if (history.workflow_id.trim().isEmpty || history.journal.isEmpty) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.invalid_journal,
        message: 'Missing workflow identifier or committed outcomes.',
      );
    }

    final outcomes = <WorkflowOutcomeEvent>[];
    final event_ids = <String>{};
    var previous_sequence = 0;

    for (var index = 0; index < history.journal.length; index++) {
      final entry = history.journal[index];
      if (entry.sequence <= previous_sequence ||
          entry.version != index + 1 ||
          entry.workflow_id != history.workflow_id ||
          entry.event_id.trim().isEmpty ||
          !event_ids.add(entry.event_id)) {
        throw WorkflowStateReadException(
          code: WorkflowStateReadErrorCode.invalid_journal,
          message: 'Invalid committed journal metadata.',
          event_index: index,
        );
      }

      final WorkflowEvent decoded;
      try {
        decoded = _runtime.codec.decode(
          event_type: entry.event_type,
          payload_json: entry.payload_json,
        );
      } on FormatException {
        throw WorkflowStateReadException(
          code: WorkflowStateReadErrorCode.invalid_event,
          message: 'Committed event cannot be decoded.',
          event_index: index,
        );
      }

      // Commands are inbox records, never journal events.
      if (decoded is! WorkflowOutcomeEvent) {
        throw WorkflowStateReadException(
          code: WorkflowStateReadErrorCode.invalid_event,
          message: 'A command event was found in the committed journal.',
          event_index: index,
        );
      }

      outcomes.add(decoded);
      previous_sequence = entry.sequence;
    }

    final WorkflowSnapshot? replayed;
    try {
      replayed = _machine.replay(outcomes);
    } on WorkflowReplayException catch (error) {
      throw WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.invalid_history,
        message: 'Committed history violates domain transition rules.',
        event_index: error.event_index,
      );
    }

    if (replayed == null ||
        replayed.identity.workflow_id != history.workflow_id ||
        replayed.version != outcomes.length) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.invalid_history,
        message: 'Replayed snapshot disagrees with committed journal.',
      );
    }

    return (
      state: replayed,
      events: List<WorkflowOutcomeEvent>.unmodifiable(outcomes),
    );
  }

  /// Validates a trusted owner without normalizing the original ID.
  static String _require_os_user_id(String id) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'os_user_id');
    }
    return id;
  }
}
