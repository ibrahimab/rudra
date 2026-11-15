import '../events/workflow_event.dart';

import '../states/workflow_active_state.dart';
import '../states/workflow_ended_state.dart';
import '../states/workflow_state.dart';

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

  /// Active workflow history is missing its expected ownership projection.
  orphaned_workflow,
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

  /// Restores the current workflow from a consistent persisted snapshot.
  ///
  /// Every history located through the trusted owner's
  /// authoritative owner index is validated through SDK replay.
  ///
  /// This includes histories whose derived unfinished-workflow
  /// projection is missing or incorrectly assigned.
  ///
  /// Unrelated OS users' journals do not participate in this read.
  ///
  /// An active workflow belonging to this OS user but missing
  /// the expected projection is an integrity failure.
  ///
  /// Terminal histories do not occupy unfinished-workflow slots.
  ///
  /// No commands, events, repairs, or filesystem operations occur.
  Future<WorkflowActiveState?> current() async {
    final evidence = await _history_store.load_restoration_evidence(
      os_user_id: _os_user_id,
    );

    final projected = evidence.projected;

    // Check other histories even when a current projection exists.
    // Otherwise a duplicated active workflow could remain hidden.
    final seen_workflows = <String>{
      if (projected != null) projected.projected_identity.workflow_id,
    };

    for (final history in evidence.other_histories) {
      if (!seen_workflows.add(history.workflow_id)) {
        throw const WorkflowStateReadException(
          code: WorkflowStateReadErrorCode.invalid_journal,
          message: 'Duplicate workflow history in restoration evidence.',
        );
      }

      final state = _replay_history(history);

      if (state is WorkflowActiveState) {
        if (state.identity.os_user_id != _os_user_id) {
          throw const WorkflowStateReadException(
            code: WorkflowStateReadErrorCode.ownership_mismatch,
            message: 'Indexed workflow owner disagrees with committed history.',
          );
        }

        throw const WorkflowStateReadException(
          code: WorkflowStateReadErrorCode.orphaned_workflow,
          message:
              'An active workflow exists without its expected '
              'OS-user ownership projection.',
        );
      }

      if (state is WorkflowEndedState) {
        if (state.identity.os_user_id != _os_user_id) {
          throw const WorkflowStateReadException(
            code: WorkflowStateReadErrorCode.ownership_mismatch,
            message: 'Indexed workflow owner disagrees with terminal history.',
          );
        }

        continue;
      }

      // The current committer never persists a standalone
      // start-request state. Such history is inconsistent.
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.invalid_history,
        message: 'Committed history contains an unestablished workflow.',
      );
    }

    if (projected == null) {
      return null;
    }

    final identity = projected.projected_identity;

    if (identity.os_user_id != _os_user_id) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.ownership_mismatch,
        message: 'Workflow projection belongs to another OS user.',
      );
    }

    final replayed = _replay_history(
      WorkflowHistoryJournal(
        workflow_id: identity.workflow_id,
        journal: projected.journal,
      ),
    );

    if (replayed is! WorkflowActiveState) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.projection_mismatch,
        message: 'The projected unfinished workflow is not active.',
      );
    }

    final restored_identity = replayed.identity;

    if (restored_identity.os_user_id != _os_user_id) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.ownership_mismatch,
        message: 'Replayed workflow belongs to another OS user.',
      );
    }

    if (replayed.version != projected.projected_version ||
        restored_identity.workflow_id != identity.workflow_id ||
        restored_identity.target_id != identity.target_id ||
        restored_identity.root.value != identity.root.value) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.projection_mismatch,
        message: 'Unfinished projection disagrees with history.',
      );
    }

    return replayed;
  }

  /// Validates and replays one complete committed journal.
  ///
  /// This method is shared by projected and unprojected histories.
  /// Consequently, neither path can bypass ordering, decoding,
  /// or domain-transition validation.
  ///
  /// The journal is never modified.
  WorkflowState _replay_history(WorkflowHistoryJournal history) {
    if (history.workflow_id.trim().isEmpty || history.journal.isEmpty) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.invalid_journal,
        message: 'Missing workflow identifier or committed history.',
      );
    }

    final events = <WorkflowEvent>[];
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

    final WorkflowState replayed;

    try {
      replayed = _machine.replay(events);
    } on WorkflowReplayException catch (error) {
      throw WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.invalid_history,
        message: 'Committed history violates workflow transitions.',
        event_index: error.event_index,
      );
    }

    // Journal metadata must agree with the identity established
    // by domain events, even without an ownership projection.
    final replayed_workflow_id = switch (replayed) {
      WorkflowActiveState state => state.identity.workflow_id,
      WorkflowEndedState state => state.identity.workflow_id,
      _ => null,
    };

    if (replayed_workflow_id != null &&
        replayed_workflow_id != history.workflow_id) {
      throw const WorkflowStateReadException(
        code: WorkflowStateReadErrorCode.invalid_history,
        message: 'Replayed workflow identity disagrees with journal.',
      );
    }

    return replayed;
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
