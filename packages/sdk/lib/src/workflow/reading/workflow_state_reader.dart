import '../events/workflow_event.dart';
import '../states/workflow_active_state.dart';
import '../workflow_runtime.dart';
import '../workflow_state_machine.dart';
import '../workflow_transition_exception.dart';

import 'workflow_history_store.dart';

/// Stable categories of workflow restoration failures.
///
/// A failed restoration must not be interpreted as the
/// absence of an unfinished workflow.
enum WorkflowStateReadErrorCode {
  /// The returned projection belongs to another OS user.
  ownership_mismatch,

  /// Persisted journal ordering or metadata is invalid.
  invalid_journal,

  /// A committed event cannot be decoded.
  invalid_event,

  /// Committed events violate domain transition rules.
  invalid_history,

  /// Replayed state disagrees with the unfinished projection.
  projection_mismatch,
}

/// Indicates that persisted workflow state is inconsistent.
///
/// These failures are read-only diagnostics. They never
/// initiate recovery, rollback, or automatic repair.
final class WorkflowStateReadException implements Exception {
  /// Creates a typed restoration failure.
  const WorkflowStateReadException({
    required this.code,
    required this.message,
    this.event_index,
  });

  /// Machine-readable failure category.
  final WorkflowStateReadErrorCode code;

  /// Human-readable diagnostic without serialized payloads.
  final String message;

  /// Zero-based journal position, when applicable.
  final int? event_index;

  @override
  String toString() {
    return 'WorkflowStateReadException('
        '${code.name}, event_index: $event_index): $message';
  }
}

/// Reconstructs authoritative workflow state from persisted history.
///
/// The reader retrieves a consistent history snapshot through
/// [WorkflowHistoryStore], decodes the committed events, and
/// replays them using [WorkflowRuntime.flow].
///
/// Journal metadata, ownership, version continuity, and the
/// unfinished-workflow projection are validated before state
/// is returned.
///
/// This initial implementation supports the established active
/// lifecycle. Additional nonterminal states will be supported
/// as their lifecycle transitions are implemented.
///
/// No commands, event submissions, filesystem operations,
/// or persistence writes are performed.
///
/// Example:
/// ```dart
/// final reader = WorkflowStateReader(
///   runtime: runtime,
///   history_store: history_store,
///   os_user_id: trusted_os_user_id,
/// );
///
/// final active = await reader.current();
///
/// print(active?.identity.workflow_id);
/// ```
final class WorkflowStateReader {
  /// Creates a reader bound to one trusted OS-user identity.
  ///
  /// The caller is responsible for providing an authenticated
  /// OS-user identity, not a frontend-supplied identifier.
  ///
  /// The runtime must match the configuration used to process
  /// and persist the workflow's events.
  ///
  /// Construction performs no I/O.
  WorkflowStateReader({
    required WorkflowRuntime runtime,
    required WorkflowHistoryStore history_store,
    required String os_user_id,
  }) : _runtime = runtime,
       _history_store = history_store,
       _os_user_id = _require_os_user_id(os_user_id),
       _machine = WorkflowStateMachine(flow: runtime.flow);

  final WorkflowRuntime _runtime;
  final WorkflowHistoryStore _history_store;
  final String _os_user_id;
  final WorkflowStateMachine _machine;

  /// Restores the current established workflow, if one exists.
  ///
  /// Returns null only when persistence reports that no
  /// unfinished workflow exists for the trusted OS user.
  ///
  /// Invalid history, unauthorized ownership, and projection
  /// inconsistencies throw [WorkflowStateReadException].
  ///
  /// Reads never trigger commands or events.
  Future<WorkflowActiveState?> current() async {
    final snapshot = await _history_store.load_unfinished(
      os_user_id: _os_user_id,
    );

    if (snapshot == null) {
      return null;
    }

    final projected = snapshot.projected_identity;

    if (projected.os_user_id != _os_user_id) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.ownership_mismatch,
        message: 'Workflow projection belongs to another OS user.',
      );
    }

    final journal = snapshot.journal;

    if (journal.isEmpty) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.invalid_journal,
        message: 'An unfinished workflow has no committed history.',
      );
    }

    final events = <WorkflowEvent>[];
    final event_ids = <String>{};

    var previous_sequence = 0;

    for (var index = 0; index < journal.length; index++) {
      final entry = journal[index];
      final expected_version = index + 1;

      // Global sequences may contain gaps, but must be
      // strictly increasing in committed workflow order.
      //
      // Workflow-local versions must be contiguous.
      if (entry.sequence <= previous_sequence ||
          entry.version != expected_version ||
          entry.workflow_id != projected.workflow_id ||
          entry.event_id.trim().isEmpty ||
          !event_ids.add(entry.event_id)) {
        throw WorkflowStateReadException(
          code: WorkflowStateReadErrorCode.invalid_journal,
          message: 'Invalid committed journal metadata.',
          event_index: index,
        );
      }

      final WorkflowEvent event;

      try {
        event = _runtime.codec.decode(
          event_type: entry.event_type,
          payload_json: entry.payload_json,
        );
      } on FormatException {
        throw WorkflowStateReadException(
          code: WorkflowStateReadErrorCode.invalid_event,
          message: 'A committed event cannot be decoded.',
          event_index: index,
        );
      }

      events.add(event);
      previous_sequence = entry.sequence;
    }

    // Use the registered domain transitions rather than
    // reconstructing lifecycle state inside persistence.
    final WorkflowActiveState active;

    try {
      final replayed = _machine.replay(events);

      if (replayed is! WorkflowActiveState) {
        throw const WorkflowStateReadException(
          code: WorkflowStateReadErrorCode.projection_mismatch,
          message: 'The projected workflow is not active.',
        );
      }

      active = replayed;
    } on WorkflowReplayException catch (error) {
      throw WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.invalid_history,
        message: 'Committed history violates workflow transitions.',
        event_index: error.event_index,
      );
    }

    final identity = active.identity;

    if (identity.os_user_id != _os_user_id) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.ownership_mismatch,
        message: 'Replayed workflow belongs to another OS user.',
      );
    }

    // A projection is accepted only if every persisted
    // identity binding and the committed version agree.
    if (active.version != snapshot.projected_version ||
        identity.workflow_id != projected.workflow_id ||
        identity.target_id != projected.target_id ||
        identity.root.value != projected.root.value) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.projection_mismatch,
        message: 'Unfinished projection disagrees with history.',
      );
    }

    return active;
  }

  /// Validates a trusted OS-user identifier without normalizing it.
  static String _require_os_user_id(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        'os_user_id',
        'OS-user identity must not be blank.',
      );
    }

    return value;
  }
}
