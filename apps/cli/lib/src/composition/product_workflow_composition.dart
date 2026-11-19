import 'dart:io';

import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:uuid/uuid.dart';

import '../features/workflow/application/workflow_start_exception.dart';
import '../features/workflow/application/workflow_stop_exception.dart';

/// Composes persistent workflow services for the product CLI.
///
/// One workflow operation owns one SQLite persistence instance.
/// Connections are closed before the operation returns.
///
/// Workflow creation requires an explicit call to [start].
/// [current] only restores committed workflow state.
///
/// The configured OS-user identity must originate from a
/// trusted platform boundary. Submission scope remains a
/// separate concept from authenticated workflow ownership.
final class ProductWorkflowComposition {
  /// Creates composition with injectable platform dependencies.
  ///
  /// Tests may inject a disposable database and deterministic
  /// OS-user identity without using native identity discovery.
  ///
  /// Construction performs no database or filesystem I/O.
  ProductWorkflowComposition({
    required this.database_file,
    required Future<String> Function() os_user_id_provider,
  }) : _os_user_id_provider = os_user_id_provider;

  /// Creates the production composition for local macOS.
  ///
  /// The OS identity is obtained from the process's effective
  /// host context using the absolute system id executable.
  ///
  /// HOME selects the storage location, never the OS identity.
  /// It must be an absolute path.
  ///
  /// No database is opened or created by this factory.
  factory ProductWorkflowComposition.for_current_host() {
    if (!Platform.isMacOS) {
      throw UnsupportedError(
        'Persistent workflow composition currently requires macOS.',
      );
    }

    final home = Platform.environment['HOME'];

    if (home == null || !home.startsWith('/')) {
      throw StateError('An absolute HOME directory is required.');
    }

    return ProductWorkflowComposition(
      database_file: File(
        '$home/Library/Application Support/Rudra/rudra.sqlite',
      ),
      os_user_id_provider: () async {
        final result = await Process.run('/usr/bin/id', ['-u']);

        if (result.exitCode != 0) {
          throw StateError('Unable to resolve the operating-system UID.');
        }

        final uid = int.tryParse((result.stdout as String).trim());

        if (uid == null || uid < 0) {
          throw StateError('Invalid operating-system UID.');
        }

        return 'macos-uid:$uid';
      },
    );
  }

  /// Stable database location supplied by application composition.
  final File database_file;

  /// Trusted platform identity provider.
  final Future<String> Function() _os_user_id_provider;

  /// Restores an established workflow without creating one.
  ///
  /// If no database exists, returns null without creating a
  /// database, directory, submission, or workflow event.
  ///
  /// Invalid persisted state propagates as an SDK integrity
  /// failure rather than being silently repaired.
  Future<WorkflowActiveState?> current() async {
    if (!await database_file.exists()) {
      return null;
    }

    final os_user_id = await _trusted_os_user_id();
    final runtime = WorkflowRuntime.standard();

    final persistence = _open_persistence(
      runtime: runtime,
      os_user_id: os_user_id,
    );

    try {
      final history = await WorkflowStateReader(
        runtime: runtime,
        history_store: persistence.workflow_history_store,
        os_user_id: os_user_id,
      ).current();

      return history?.state;
    } finally {
      await persistence.close();
    }
  }

  /// Explicitly submits and processes a workflow-start request.
  ///
  /// The accepted request is durably stored through EventManager.
  /// WorkflowProcessor then performs registered SDK behavior
  /// and guarded commitment.
  ///
  /// Processing is performed only for this explicit CLI action.
  /// Opening Explorer never invokes this method.
  ///
  /// Previously pending submissions in the same trusted scope
  /// may be processed before the newly accepted request.
  ///
  /// Returns only after the requested submission is committed
  /// and its resulting workflow is restored from the journal.
  ///
  /// Business rejections, quarantines, and infrastructure
  /// failures never produce a successful active result.
  Future<WorkflowActiveState> start({
    required String target_id,
    required TargetPath root,
  }) async {
    if (!root.value.startsWith('/')) {
      throw ArgumentError.value(
        root.value,
        'root',
        'A local macOS workflow requires an absolute root.',
      );
    }

    final os_user_id = await _trusted_os_user_id();

    // Only an explicit start action may initialize storage.
    await database_file.parent.create(recursive: true);

    // Keep the database directory private before opening SQLite.
    final permissions = await Process.run('/bin/chmod', [
      '700',
      database_file.parent.path,
    ]);

    if (permissions.exitCode != 0) {
      throw StateError('Unable to secure Rudra persistence directory.');
    }

    final runtime = WorkflowRuntime.standard();

    final persistence = _open_persistence(
      runtime: runtime,
      os_user_id: os_user_id,
    );

    try {
      final reader = WorkflowStateReader(
        runtime: runtime,
        history_store: persistence.workflow_history_store,
        os_user_id: os_user_id,
      );

      // Avoid submitting a redundant start request when the
      // user already has an established unfinished workflow.
      final existing = await reader.current();

      if (existing != null) {
        throw WorkflowAlreadyActiveException(
          workflow_id: existing.state.identity.workflow_id,
        );
      }

      final manager = EventManager(store: persistence.event_submission_store);

      final receipt = await manager.trigger(
        WorkflowStartEvent(target_id: target_id, root: root),
      );

      // All domain behavior remains in the SDK processor.
      final processor = WorkflowProcessor(
        runtime: runtime,
        inbox: persistence.workflow_inbox_for(os_user_id: os_user_id),
        identity_provider: _CliWorkflowIdentityProvider(os_user_id),
        committer: persistence.workflow_committer_for(os_user_id: os_user_id),
        rejector: persistence.workflow_rejector,
        quarantiner: persistence.workflow_quarantiner,
      );

      // Observe the specific submission rather than assuming
      // process_next() handles our request first.
      while (true) {
        final resolution = await persistence.workflow_status_reader.status_for(
          receipt,
        );

        if (resolution == null) {
          throw StateError('Accepted workflow submission is missing.');
        }

        switch (resolution.state) {
          case WorkflowSubmissionState.completed:
            final restored = await reader.current();
            final active = restored?.state;

            if (active == null ||
                active.identity.target_id != target_id ||
                active.identity.root.value != root.value) {
              throw StateError(
                'Committed workflow cannot be consistently restored.',
              );
            }

            return active;

          case WorkflowSubmissionState.rejected:
            if (resolution.rejection_code ==
                WorkflowRejectionCode.ownership_conflict) {
              // Another process may have established a workflow
              // after our initial ownership check.
              final current_workflow = await reader.current();

              throw WorkflowAlreadyActiveException(
                workflow_id: current_workflow?.state.identity.workflow_id,
              );
            }

            throw StateError(
              'Workflow start rejected: '
              '${resolution.rejection_code?.name ?? "unknown"}.',
            );

          case WorkflowSubmissionState.quarantined:
            throw StateError(
              'Workflow start quarantined: '
              '${resolution.quarantine_code?.name ?? "unknown"}.',
            );

          case WorkflowSubmissionState.pending:
            final processed = await processor.process_next();

            if (processed is WorkflowProcessingIdle) {
              // Another processor may have completed the request
              // between our status read and inbox inspection.
              final latest = await persistence.workflow_status_reader
                  .status_for(receipt);

              if (latest == null ||
                  latest.state == WorkflowSubmissionState.pending) {
                throw StateError(
                  'Workflow submission remains pending without '
                  'an available processor.',
                );
              }
            }

            continue;
        }
      }
    } finally {
      await persistence.close();
    }
  }

  /// [expected_workflow_id] optionally guards the identity
  /// previously displayed by an interactive frontend.
  ///
  /// The authenticated OS-user owner is still resolved through
  /// trusted composition. A supplied identifier never overrides
  /// that ownership.
  ///
  /// If the active workflow has changed, no Stop event is submitted.
  Future<String> stop({String? expected_workflow_id}) async {
    if (expected_workflow_id != null && expected_workflow_id.trim().isEmpty) {
      throw ArgumentError.value(
        expected_workflow_id,
        'expected_workflow_id',
        'Expected workflow identifier must not be blank.',
      );
    }

    if (!await database_file.exists()) {
      throw const WorkflowStopRejectedException(
        code: WorkflowRejectionCode.workflow_not_active,
      );
    }

    final os_user_id = await _trusted_os_user_id();
    final runtime = WorkflowRuntime.standard();

    final persistence = _open_persistence(
      runtime: runtime,
      os_user_id: os_user_id,
    );

    try {
      final reader = WorkflowStateReader(
        runtime: runtime,
        history_store: persistence.workflow_history_store,
        os_user_id: os_user_id,
      );

      final active = await reader.current();

      if (active == null) {
        throw const WorkflowStopRejectedException(
          code: WorkflowRejectionCode.workflow_not_active,
        );
      }

      final workflow_id = active.state.identity.workflow_id;

      // An interactive frontend may supply the identity it displayed.
      //
      // The expected ID is a concurrency guard, not authorization
      // to access or stop another workflow.
      //
      // A replacement workflow must never be stopped merely because
      // it became active between rendering and the user's keypress.
      if (expected_workflow_id != null && workflow_id != expected_workflow_id) {
        throw const WorkflowStopRejectedException(
          code: WorkflowRejectionCode.workflow_id_mismatch,
        );
      }

      // Only this explicit application action submits Stop.
      // Reading current state or opening Explorer never does.
      final manager = EventManager(store: persistence.event_submission_store);

      final receipt = await manager.trigger(
        WorkflowStopEvent(workflow_id: workflow_id),
      );

      final processor = WorkflowProcessor(
        runtime: runtime,
        inbox: persistence.workflow_inbox_for(os_user_id: os_user_id),
        identity_provider: _CliWorkflowIdentityProvider(os_user_id),
        committer: persistence.workflow_committer_for(os_user_id: os_user_id),
        rejector: persistence.workflow_rejector,
        quarantiner: persistence.workflow_quarantiner,
      );

      // Observe our exact durable submission, even if other
      // submissions must be processed before it.
      while (true) {
        final resolution = await persistence.workflow_status_reader.status_for(
          receipt,
        );

        if (resolution == null) {
          throw StateError('Accepted stop submission is missing.');
        }

        switch (resolution.state) {
          case WorkflowSubmissionState.completed:
            // Stop completion is transactionally coupled to
            // the terminal outcome and ownership release.
            return workflow_id;

          case WorkflowSubmissionState.rejected:
            final code = resolution.rejection_code;

            if (code == WorkflowRejectionCode.workflow_not_active ||
                code == WorkflowRejectionCode.workflow_id_mismatch) {
              throw WorkflowStopRejectedException(code: code!);
            }

            throw StateError(
              'Workflow stop rejected: '
              '${code?.name ?? "unknown"}.',
            );

          case WorkflowSubmissionState.quarantined:
            throw StateError(
              'Workflow stop quarantined: '
              '${resolution.quarantine_code?.name ?? "unknown"}.',
            );

          case WorkflowSubmissionState.pending:
            final processed = await processor.process_next();

            if (processed is WorkflowProcessingIdle) {
              // Another processor could have resolved the
              // submission between the two reads.
              final latest = await persistence.workflow_status_reader
                  .status_for(receipt);

              if (latest == null ||
                  latest.state == WorkflowSubmissionState.pending) {
                throw StateError(
                  'Workflow stop remains pending without '
                  'an available processor.',
                );
              }
            }

            continue;
        }
      }
    } finally {
      await persistence.close();
    }
  }

  /// Opens one persistence owner using a shared workflow runtime.
  RudraSqlitePersistence _open_persistence({
    required WorkflowRuntime runtime,
    required String os_user_id,
  }) {
    return RudraSqlitePersistence(
      database_file: database_file,
      scope_id: 'rudra-cli:$os_user_id',
      runtime: runtime,
    );
  }

  /// Validates the identity provided by trusted composition.
  Future<String> _trusted_os_user_id() async {
    final identity = await _os_user_id_provider();

    if (identity.trim().isEmpty) {
      throw StateError('Trusted OS-user identity must not be blank.');
    }

    return identity;
  }
}

/// Proposes identities for explicitly submitted workflow starts.
///
/// The OS-user owner is fixed by application composition.
/// Commands cannot choose or override that identity.
final class _CliWorkflowIdentityProvider implements WorkflowIdentityProvider {
  /// Creates a provider bound to the resolved OS user.
  const _CliWorkflowIdentityProvider(this.os_user_id);

  /// Trusted identity of the current OS user.
  final String os_user_id;

  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final command = submission.command;

    if (command is! WorkflowStartEvent) {
      throw StateError('Unsupported workflow identity request.');
    }

    return WorkflowIdentity(
      workflow_id: Uuid().v4(),
      os_user_id: os_user_id,
      target_id: command.target_id,
      root: command.root,
    );
  }
}
