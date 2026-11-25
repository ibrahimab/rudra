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
import '../event_submission_exception.dart';
import 'outcomes/workflow_operation_outcome.dart';
import '../processing/workflow_identity_provider.dart';
import '../processing/workflow_processing_result.dart';
import '../processing/workflow_processor.dart';
import '../processing/workflow_submission_resolution.dart';
import '../reading/workflow_state_reader.dart';
import '../states/workflows_state.dart';
import '../workflow_runtime.dart';
import '../observation/workflow_commit_channel.dart';
import '../observation/workflow_state_observer.dart';

import 'workflow_application_persistence.dart';

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
      statuses: persistence.workflow_status_reader_for(
        os_user_id: trusted_os_user_id,
      ),
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

  /// Completion boundary of the last scheduled processing operation.
  ///
  /// Every processing operation acquires this lane before accessing the
  /// processor. The lane completes independently of operation success,
  /// allowing subsequent operations to proceed after a failure.
  Future<void> _processing_tail = Future<void>.value();

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

  /// Processes at most one accepted command within trusted ownership.
  ///
  /// Returns a committed, rejected, quarantined or idle processing result.
  /// Execution is serialized with other application processing operations.
  ///
  /// Domain integrity and persistence failures propagate. A failed operation
  /// releases the processing lane without reporting successful commitment.
  Future<WorkflowProcessingResult> process_next() {
    return _serialize_processing(_processor.process_next);
  }

  /// Starts a workflow at the requested [target_id] and [root].
  ///
  /// [idempotency_key] identifies the logical Start operation within the
  /// trusted submission scope. Retries must preserve the original key,
  /// target and root.
  ///
  /// The caller supplies target-specific validation and writable persistence.
  ///
  /// Returns the durable application outcome of the original operation.
  /// A completed outcome identifies its historical establishment rather than
  /// the currently active workflow.
  ///
  /// Expected business rejections and quarantine remain durable resolutions.
  /// Conflicting key reuse returns [WorkflowOperationIdempotencyConflict].
  ///
  /// Throws [ArgumentError] for invalid command arguments or a blank key.
  /// Persistence, processing and integrity failures propagate.
  ///
  /// Example:
  /// ```dart
  /// final outcome = await application.start(
  ///   target_id: 'local-macos',
  ///   root: TargetPath('/workspace'),
  ///   idempotency_key: operation_id,
  /// );
  ///
  /// if (outcome is WorkflowOperationResolved) {
  ///   print(outcome.resolution.state);
  /// }
  /// ```
  Future<WorkflowOperationOutcome> start({
    required String target_id,
    required TargetPath root,
    required String idempotency_key,
  }) {
    return _execute(
      WorkflowStartEvent(target_id: target_id, root: root),
      idempotency_key: idempotency_key,
    );
  }

  /// Stops the explicitly requested [workflow_id].
  ///
  /// [workflow_id] identifies the intended workflow and cannot be replaced
  /// by a subsequently established workflow.
  ///
  /// [idempotency_key] identifies the logical Stop operation. Retries must
  /// preserve both the original key and workflow identifier.
  ///
  /// Returns the original durable operation outcome, independently of the
  /// current workflow lifecycle.
  ///
  /// Expected business rejections and quarantine remain durable resolutions.
  /// Conflicting key reuse returns [WorkflowOperationIdempotencyConflict].
  ///
  /// Throws [ArgumentError] for blank identifiers. Persistence, processing
  /// and integrity failures propagate.
  ///
  /// Example:
  /// ```dart
  /// final outcome = await application.stop(
  ///   workflow_id: displayed.identity.workflow_id,
  ///   idempotency_key: operation_id,
  /// );
  /// ```
  Future<WorkflowOperationOutcome> stop({
    required String workflow_id,
    required String idempotency_key,
  }) {
    return _execute(
      WorkflowStopEvent(workflow_id: workflow_id),
      idempotency_key: idempotency_key,
    );
  }

  /// Durably accepts and resolves one explicit [command].
  ///
  /// [idempotency_key] binds retries to the original logical operation.
  ///
  /// Acceptance may occur concurrently. Resolution is performed within the
  /// application's processing lane so that terminal submissions cannot
  /// trigger another processing attempt.
  ///
  /// Returns a durable resolution or an explicit idempotency conflict.
  /// All other submission and processing failures propagate.
  Future<WorkflowOperationOutcome> _execute(
    WorkflowCommandEvent command, {
    required String idempotency_key,
  }) async {
    if (idempotency_key.trim().isEmpty) {
      throw ArgumentError.value(
        idempotency_key,
        'idempotency_key',
        'Idempotency key must not be blank.',
      );
    }

    final EventSubmissionReceipt receipt;

    try {
      receipt = await submit_command(command, idempotency_key: idempotency_key);
    } on EventSubmissionException catch (error) {
      if (error.code == EventSubmissionErrorCode.idempotency_conflict) {
        return const WorkflowOperationIdempotencyConflict();
      }

      rethrow;
    }

    return _serialize_processing(() async {
      final resolution = await _await_resolution(receipt);

      _validate_completed_operation(command, resolution);

      return WorkflowOperationResolved(resolution: resolution);
    });
  }

  /// Executes [operation] exclusively within this application's processing
  /// lane.
  ///
  /// Returns the operation's result after all earlier scheduled processing
  /// operations have released the lane.
  ///
  /// Operation failures propagate to their respective callers without
  /// preventing subsequent operations from acquiring the lane.
  Future<T> _serialize_processing<T>(Future<T> Function() operation) async {
    final previous = _processing_tail;
    final release = Completer<void>();

    // Reserve the next position before yielding to another caller.
    _processing_tail = release.future;

    try {
      await previous;
      return await operation();
    } finally {
      release.complete();
    }
  }

  /// Resolves the exact accepted [receipt] while owning the processing lane.
  ///
  /// Returns its durable terminal resolution. Pending submissions may
  /// require earlier accepted commands to be processed first.
  ///
  /// Throws [StateError] if the accepted submission disappears or remains
  /// pending without observable processing progress.
  Future<WorkflowSubmissionResolution> _await_resolution(
    EventSubmissionReceipt receipt,
  ) async {
    while (true) {
      final resolution = await _require_resolution(receipt);

      if (resolution.state != WorkflowSubmissionState.pending) {
        return resolution;
      }

      // This method already owns the processing lane. Calling the public
      // process_next() here would attempt to acquire the same lane again.
      final processed = await _processor.process_next();

      if (processed is WorkflowProcessingIdle) {
        final latest = await _require_resolution(receipt);

        if (latest.state == WorkflowSubmissionState.pending) {
          throw StateError(
            'Workflow submission remains pending without '
            'an available processor.',
          );
        }

        return latest;
      }
    }
  }

  /// Retrieves the durable resolution of the exact accepted [receipt].
  ///
  /// Returns the matching resolution or throws [StateError] if the
  /// persistence adapter cannot establish the original submission identity.
  ///
  /// Persistence and journal-integrity failures propagate.
  Future<WorkflowSubmissionResolution> _require_resolution(
    EventSubmissionReceipt receipt,
  ) async {
    final resolution = await status_for(receipt);

    if (resolution == null) {
      throw StateError('Accepted workflow submission is missing.');
    }

    if (resolution.receipt.event_id != receipt.event_id ||
        resolution.receipt.correlation_id != receipt.correlation_id) {
      throw StateError(
        'Submission resolution disagrees with the accepted receipt.',
      );
    }

    return resolution;
  }

  /// Validates that a completed [resolution] describes the supplied [command].
  ///
  /// Historical journal validation belongs to the persistence reader.
  /// This boundary verifies the operation-specific committed reference
  /// before returning it to the application consumer.
  ///
  /// Throws [StateError] when the reference contradicts the accepted
  /// operation. Non-completed resolutions require no committed outcome.
  static void _validate_completed_operation(
    WorkflowCommandEvent command,
    WorkflowSubmissionResolution resolution,
  ) {
    if (resolution.state != WorkflowSubmissionState.completed) {
      return;
    }

    final committed = resolution.committed_outcome!;

    if (command is WorkflowStartEvent) {
      if (committed.event_type != WorkflowStartedEvent.type_id ||
          committed.version != 1) {
        throw StateError('Completed Start lacks its establishment outcome.');
      }
    } else if (command is WorkflowStopEvent) {
      if (committed.event_type != WorkflowEndedEvent.type_id ||
          committed.workflow_id != command.workflow_id) {
        throw StateError(
          'Completed Stop lacks its requested terminal outcome.',
        );
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
