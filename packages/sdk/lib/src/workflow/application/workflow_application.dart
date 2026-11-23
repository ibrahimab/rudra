import 'dart:async';

import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../../state/rudra_state.dart';
import '../event_manager.dart';
import '../event_submission_receipt.dart';
import '../events/workflow_event.dart';
import '../events/workflow_ended_event.dart';
import '../events/workflow_start_event.dart';
import '../events/workflow_started_event.dart';
import '../events/workflow_stop_event.dart';
import '../processing/workflow_identity_provider.dart';
import '../processing/workflow_processing_result.dart';
import '../processing/workflow_processor.dart';
import '../processing/workflow_submission_resolution.dart';
import '../reading/workflow_state_reader.dart';
import '../states/workflow_snapshot.dart';
import '../states/workflows_state.dart';
import '../workflow_runtime.dart';
import '../observation/workflow_commit_channel.dart';
import '../observation/workflow_state_observer.dart';

import 'workflow_application_persistence.dart';

/// Expected conflict when a trusted owner already has an unfinished workflow.
///
/// [workflow_id] identifies the existing workflow when restoration can
/// establish its identity. The rejected Start never replaces that workflow.
final class WorkflowAlreadyActiveException implements Exception {
  /// Creates a conflict with the optional existing [workflow_id].
  const WorkflowAlreadyActiveException({this.workflow_id});

  /// Identifier of the existing unfinished workflow, when known.
  final String? workflow_id;

  /// Formats the stable conflict name and its known workflow identity.
  @override
  String toString() =>
      'WorkflowAlreadyActiveException(workflow_id: $workflow_id)';
}

/// Expected refusal of an explicit workflow Stop request.
///
/// The rejection [code] describes either a pre-submission conflict or a
/// durable business rejection from the trusted workflow processor.
final class WorkflowStopRejectedException implements Exception {
  /// Creates a Stop refusal classified by [code].
  const WorkflowStopRejectedException({required this.code});

  /// Machine-readable reason the requested workflow could not be stopped.
  final WorkflowRejectionCode code;

  /// Formats the stable conflict name and its rejection code.
  @override
  String toString() => 'WorkflowStopRejectedException(code: ${code.name})';
}

/// Owner-scoped SDK application operations over confirmed workflow state.
///
/// Host composition supplies one workflow runtime, trusted identity and
/// persistence owner. Read operations replay journal evidence without writes;
/// explicit operations durably submit commands and confirm their outcomes.
/// Frontends consume these methods rather than processing domain events.
///
/// This application does not own the supplied persistence connection. Its
/// caller must keep that connection open for every awaited operation.
///
/// Example:
/// ```dart
/// final application = WorkflowApplication(
///   runtime: runtime,
///   persistence: persistence,
///   identity_provider: identity_provider,
///   os_user_id: trusted_os_user_id,
/// );
/// final state = await application.read_state();
/// final current = state.workflows.current_workflow;
/// ```
final class WorkflowApplication {
  /// Binds SDK application services to trusted host dependencies.
  ///
  /// [runtime] must match the workflow configuration used by [persistence].
  /// [persistence] shares the history, submission and commit boundaries.
  /// [identity_provider] proposes owner-bound identities for new workflows.
  /// [os_user_id] is resolved by a trusted host, never supplied by a frontend.
  ///
  /// Throws [ArgumentError] when [os_user_id] is blank. Construction does
  /// not read persistence, submit a command or perform filesystem operations.
  factory WorkflowApplication({
    required WorkflowRuntime runtime,
    required WorkflowApplicationPersistence persistence,
    required WorkflowIdentityProvider identity_provider,
    required String os_user_id,
  }) {
    final trusted_os_user_id = _require_os_user_id(os_user_id);

    return WorkflowApplication._(
      events: EventManager(store: persistence.event_submission_store),
      reader: WorkflowStateReader(
        runtime: runtime,
        history_store: persistence.workflow_history_store,
        os_user_id: trusted_os_user_id,
      ),
      processor: WorkflowProcessor(
        runtime: runtime,
        inbox: persistence.workflow_inbox_for(os_user_id: trusted_os_user_id),
        identity_provider: identity_provider,
        committer: persistence.workflow_committer_for(
          os_user_id: trusted_os_user_id,
        ),
        rejector: persistence.workflow_rejector,
        quarantiner: persistence.workflow_quarantiner,
      ),
      statuses: persistence.workflow_status_reader,
      commits: persistence.workflow_commit_subscriber,
      os_user_id: trusted_os_user_id,
    );
  }

  /// Stores the SDK services prepared by trusted application composition.
  ///
  /// [events] accepts explicit commands into durable persistence.
  /// [reader] restores validated committed workflow state.
  /// [processor] processes accepted commands through registered behaviors.
  /// [statuses] resolves durable submission outcomes.
  /// [commits] supplies committed-change notifications for observation.
  /// [os_user_id] identifies the authenticated workflow owner.
  ///
  /// Construction retains these dependencies without performing I/O.
  /// The caller owns persistence and notification-source lifetimes.
  WorkflowApplication._({
    required EventManager events,
    required WorkflowStateReader reader,
    required WorkflowProcessor processor,
    required WorkflowSubmissionStatusReader statuses,
    required WorkflowCommitSubscriber commits,
    required String os_user_id,
  }) : _events = events,
       _reader = reader,
       _processor = processor,
       _statuses = statuses,
       _commits = commits,
       _os_user_id = os_user_id;

  /// Durable explicit command submission service.
  final EventManager _events;

  /// Validated owner-scoped history restoration service.
  final WorkflowStateReader _reader;

  /// Registered workflow command processing service.
  final WorkflowProcessor _processor;

  /// Durable submission-resolution lookup service.
  final WorkflowSubmissionStatusReader _statuses;

  /// Persistence-owned committed-change notification source.
  final WorkflowCommitSubscriber _commits;

  /// Authenticated workflow owner established by trusted composition.
  final String _os_user_id;

  /// SDK coordinator for authoritative state subscriptions.
  late final WorkflowStateObserver _observer = WorkflowStateObserver(
    read_state: read_state,
    commits: _commits,
    os_user_id: _os_user_id,
  );

  /// Observes verified application state for the trusted workflow owner.
  ///
  /// Returns a stream beginning with an authoritative [RudraState], followed
  /// by reconciled state after committed local workflow changes.
  ///
  /// Each subscription owns its reconciliation and cancellation lifecycle.
  /// Rapid commits may be coalesced into the latest validated state.
  ///
  /// Restoration or notification-source failures terminate observation with
  /// a stream error; they are never represented as verified absence.
  ///
  /// Subscribing performs no command submission, processing or target
  /// filesystem modification. The caller must cancel subscriptions before
  /// disposing the supplied persistence owner.
  ///
  /// Example:
  /// ```dart
  /// final subscription = application.observe_state().listen((state) {
  ///   final current = state.workflows.current_workflow;
  ///   print(current?.identity.workflow_id);
  /// });
  ///
  /// await subscription.cancel();
  /// ```
  Stream<RudraState> observe_state() => _observer.observe();

  /// Reads the latest verified, coherent SDK application state.
  ///
  /// Returns a non-null [RudraState]; a null current-workflow selector means
  /// verified absence. Invalid journal or ownership evidence propagates as a
  /// restoration failure. Reading never submits or processes a command.
  Future<RudraState> read_state() async {
    final restored = await _reader.current();
    return RudraState(
      workflows: WorkflowsState(current_workflow: restored?.state),
    );
  }

  /// Durably accepts an explicit typed [command] for processing.
  ///
  /// [idempotency_key] identifies a retry in the persistence-owned scope.
  /// Returns an acceptance receipt, never a claim of domain success.
  /// Submission failures propagate and no workflow transition is inferred.
  Future<EventSubmissionReceipt> submit_command(
    WorkflowCommandEvent command, {
    String? idempotency_key,
  }) => _events.trigger(command, idempotency_key: idempotency_key);

  /// Returns the durable resolution of an accepted [receipt], when accessible.
  ///
  /// A completed resolution identifies its last causally linked journal
  /// outcome. Null means the receipt is unknown in the trusted scope.
  /// Persistence and integrity failures propagate to the caller.
  Future<WorkflowSubmissionResolution?> status_for(
    EventSubmissionReceipt receipt,
  ) => _statuses.status_for(receipt);

  /// Processes at most one previously accepted command in trusted scope.
  ///
  /// Returns a typed committed, rejected, quarantined or idle result.
  /// This is an explicit host processing operation and may commit history.
  /// Domain validation and persistence failures propagate without success.
  Future<WorkflowProcessingResult> process_next() => _processor.process_next();

  /// Starts a workflow at the requested [target_id] and [root].
  ///
  /// The host is responsible for target-specific path validation and
  /// provision of writable persistence before invoking this operation.
  /// Returns a committed, owner-verified [WorkflowSnapshot] whose identity
  /// matches the exact accepted submission's causally linked journal outcome.
  ///
  /// An existing unfinished workflow throws [WorkflowAlreadyActiveException]
  /// without submitting another Start. Processing rejection, quarantine,
  /// inconsistent confirmation and infrastructure errors propagate.
  ///
  /// Example:
  /// ```dart
  /// final started = await application.start(
  ///   target_id: 'local-macos',
  ///   root: TargetPath('/workspace'),
  /// );
  /// print(started.identity.workflow_id);
  /// ```
  Future<WorkflowSnapshot> start({
    required String target_id,
    required TargetPath root,
  }) async {
    final existing = (await read_state()).workflows.current_workflow;
    if (existing != null) {
      throw WorkflowAlreadyActiveException(
        workflow_id: existing.identity.workflow_id,
      );
    }

    final receipt = await submit_command(
      WorkflowStartEvent(target_id: target_id, root: root),
    );
    final resolution = await _await_resolution(receipt);

    switch (resolution.state) {
      case WorkflowSubmissionState.completed:
        final committed = resolution.committed_outcome;
        if (committed == null ||
            committed.event_type != WorkflowStartedEvent.type_id ||
            committed.version != 1) {
          throw StateError('Completed Start lacks its establishment outcome.');
        }

        final active = (await read_state()).workflows.current_workflow;
        if (active == null ||
            active.identity.workflow_id != committed.workflow_id ||
            active.identity.target_id != target_id ||
            active.identity.root.value != root.value ||
            active.version < committed.version) {
          throw StateError(
            'Committed Start cannot be consistently restored as current.',
          );
        }
        return active;

      case WorkflowSubmissionState.rejected:
        if (resolution.rejection_code ==
            WorkflowRejectionCode.ownership_conflict) {
          final current = (await read_state()).workflows.current_workflow;
          throw WorkflowAlreadyActiveException(
            workflow_id: current?.identity.workflow_id,
          );
        }
        throw StateError(
          'Workflow Start rejected: '
          '${resolution.rejection_code?.name ?? "unknown"}.',
        );

      case WorkflowSubmissionState.quarantined:
        throw StateError(
          'Workflow Start quarantined: '
          '${resolution.quarantine_code?.name ?? "unknown"}.',
        );

      case WorkflowSubmissionState.pending:
        throw StateError('Workflow Start has no confirmed resolution.');
    }
  }

  /// Stops the owner's unfinished workflow through an explicit command.
  ///
  /// [expected_workflow_id] optionally binds the request to a workflow
  /// previously displayed by a frontend. It is a concurrency guard, not an
  /// authorization credential. Blank values throw [ArgumentError].
  ///
  /// Returns the exact committed terminal workflow identifier. Missing or
  /// replaced workflows throw [WorkflowStopRejectedException]. Quarantine,
  /// inconsistent confirmation and infrastructure failures propagate.
  ///
  /// Example:
  /// ```dart
  /// final stopped_id = await application.stop(
  ///   expected_workflow_id: displayed.identity.workflow_id,
  /// );
  /// ```
  Future<String> stop({String? expected_workflow_id}) async {
    if (expected_workflow_id != null && expected_workflow_id.trim().isEmpty) {
      throw ArgumentError.value(
        expected_workflow_id,
        'expected_workflow_id',
        'Expected workflow identifier must not be blank.',
      );
    }

    final active = (await read_state()).workflows.current_workflow;
    if (active == null) {
      throw const WorkflowStopRejectedException(
        code: WorkflowRejectionCode.workflow_not_active,
      );
    }

    final workflow_id = active.identity.workflow_id;
    if (expected_workflow_id != null && workflow_id != expected_workflow_id) {
      throw const WorkflowStopRejectedException(
        code: WorkflowRejectionCode.workflow_id_mismatch,
      );
    }

    final receipt = await submit_command(
      WorkflowStopEvent(workflow_id: workflow_id),
    );
    final resolution = await _await_resolution(receipt);

    switch (resolution.state) {
      case WorkflowSubmissionState.completed:
        final committed = resolution.committed_outcome;
        if (committed == null ||
            committed.workflow_id != workflow_id ||
            committed.event_type != WorkflowEndedEvent.type_id) {
          throw StateError('Completed Stop lacks its terminal outcome.');
        }
        return workflow_id;

      case WorkflowSubmissionState.rejected:
        final code = resolution.rejection_code;
        if (code == WorkflowRejectionCode.workflow_not_active ||
            code == WorkflowRejectionCode.workflow_id_mismatch) {
          throw WorkflowStopRejectedException(code: code!);
        }
        throw StateError('Workflow Stop rejected: ${code?.name ?? "unknown"}.');

      case WorkflowSubmissionState.quarantined:
        throw StateError(
          'Workflow Stop quarantined: '
          '${resolution.quarantine_code?.name ?? "unknown"}.',
        );

      case WorkflowSubmissionState.pending:
        throw StateError('Workflow Stop has no confirmed resolution.');
    }
  }

  /// Resolves one exact [receipt] by querying durable processing status.
  ///
  /// Pending submissions may cause another accepted command to be processed
  /// first. An idle processor with no observable progress fails explicitly;
  /// a caller can subsequently recover using [status_for].
  Future<WorkflowSubmissionResolution> _await_resolution(
    EventSubmissionReceipt receipt,
  ) async {
    while (true) {
      final resolution = await status_for(receipt);
      if (resolution == null) {
        throw StateError('Accepted workflow submission is missing.');
      }

      if (resolution.state != WorkflowSubmissionState.pending) {
        return resolution;
      }

      final processed = await process_next();
      if (processed is WorkflowProcessingIdle) {
        // Another process may commit between the status and inbox reads.
        // Recheck persistence before declaring processing unavailable.
        final latest = await status_for(receipt);
        if (latest == null || latest.state == WorkflowSubmissionState.pending) {
          throw StateError(
            'Workflow submission remains pending without '
            'an available processor.',
          );
        }
      }
    }
  }

  /// Validates the trusted owner identifier without changing its spelling.
  ///
  /// [os_user_id] must be nonblank. Returns its original value or throws
  /// [ArgumentError] before any application services are constructed.
  static String _require_os_user_id(String os_user_id) {
    if (os_user_id.trim().isEmpty) {
      throw ArgumentError.value(os_user_id, 'os_user_id');
    }
    return os_user_id;
  }
}
