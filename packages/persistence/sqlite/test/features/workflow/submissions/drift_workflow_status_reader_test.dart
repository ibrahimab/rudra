import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_persistence_sqlite/src/database/rudra_database.dart'
    hide WorkflowEvent;
import 'package:rudra_persistence_sqlite/src/features/workflow/history/drift_workflow_committer.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/history/drift_workflow_history_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_event_submission_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_inbox.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_quarantine_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_rejection_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_status_reader.dart';
import 'package:test/test.dart';

/// Verifies durable resolution integrity and trusted historical ownership
/// using real SQLite persistence.
void main() {
  const scope_id = 'trusted-scope';
  const os_user_id = 'trusted-owner';
  const workflow_id = 'workflow-001';
  const target_id = 'local-macos';
  const root_path = '/workspace';

  final runtime = WorkflowRuntime.standard();

  late Directory directory;
  late RudraDatabase database;
  late DriftEventSubmissionStore submissions;
  late DriftWorkflowStatusReader reader;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'rudra-status-reader-test-',
    );

    database = RudraDatabase.file(File('${directory.path}/rudra.db'));

    submissions = DriftEventSubmissionStore(
      database: database,
      scope_id: scope_id,
      codec: runtime.codec,
    );

    reader = DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  /// Accepts a Start command without processing it.
  Future<EventSubmissionReceipt> submit_start() {
    return submissions.accept(
      WorkflowStartEvent(target_id: target_id, root: TargetPath(root_path)),
    );
  }

  /// Processes one pending command using the configured [new_workflow_id]
  /// when workflow establishment requires a trusted identity.
  Future<WorkflowProcessingResult> process_next({
    String new_workflow_id = workflow_id,
  }) {
    final processor = WorkflowProcessor(
      runtime: runtime,
      inbox: DriftWorkflowInbox(
        database: database,
        scope_id: scope_id,
        codec: runtime.codec,
        state_reader: WorkflowStateReader(
          runtime: runtime,
          history_store: DriftWorkflowHistoryStore(database: database),
          os_user_id: os_user_id,
        ),
      ),
      identity_provider: _IdentityProvider(
        workflow_id: new_workflow_id,
        os_user_id: os_user_id,
      ),
      committer: DriftWorkflowCommitter(
        database: database,
        scope_id: scope_id,
        os_user_id: os_user_id,
        runtime: runtime,
      ),
      rejector: DriftWorkflowRejectionStore(
        database: database,
        scope_id: scope_id,
        codec: runtime.codec,
      ),
      quarantiner: DriftWorkflowQuarantineStore(
        database: database,
        scope_id: scope_id,
      ),
    );

    return processor.process_next();
  }

  /// Establishes one workflow and returns its original receipt.
  Future<EventSubmissionReceipt> commit_start() async {
    final receipt = await submit_start();

    expect(await process_next(), isA<WorkflowProcessingCommitted>());

    return receipt;
  }

  /// Commits termination of the established workflow.
  ///
  /// Returns the original accepted Stop receipt.
  Future<EventSubmissionReceipt> commit_stop() async {
    final receipt = await submissions.accept(
      WorkflowStopEvent(workflow_id: workflow_id),
    );

    expect(await process_next(), isA<WorkflowProcessingCommitted>());

    return receipt;
  }

  group('authorized resolution reading', () {
    test('returns pending acceptance without processing it', () async {
      final receipt = await submit_start();

      final resolution = await reader.status_for(receipt);

      expect(resolution!.state, WorkflowSubmissionState.pending);
      expect(resolution.receipt.event_id, receipt.event_id);
      expect(resolution.receipt.correlation_id, receipt.correlation_id);
      expect(await database.select(database.workflowEvents).get(), isEmpty);
    });

    test('returns null for an unknown submission', () async {
      final receipt = EventSubmissionReceipt(
        event_id: 'unknown-event',
        correlation_id: 'unknown-correlation',
      );

      expect(await reader.status_for(receipt), isNull);
    });

    test('requires the original correlation identifier', () async {
      final receipt = await commit_start();

      final incorrect_receipt = EventSubmissionReceipt(
        event_id: receipt.event_id,
        correlation_id: 'incorrect-correlation',
      );

      expect(await reader.status_for(incorrect_receipt), isNull);
    });

    test('does not disclose submissions outside the trusted scope', () async {
      final receipt = await commit_start();

      final foreign_reader = DriftWorkflowStatusReader(
        database: database,
        scope_id: 'foreign-scope',
        os_user_id: 'foreign-owner',
        runtime: runtime,
      );

      expect(await foreign_reader.status_for(receipt), isNull);
    });

    test('rejects inconsistent historical owner composition', () async {
      final receipt = await commit_start();

      final incorrectly_bound_reader = DriftWorkflowStatusReader(
        database: database,
        scope_id: scope_id,
        os_user_id: 'incorrect-owner',
        runtime: runtime,
      );

      await expectLater(
        incorrectly_bound_reader.status_for(receipt),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('historical committed resolutions', () {
    test(
      'retains Start and Stop outcomes after workflow replacement',
      () async {
        final start_receipt = await commit_start();
        final stop_receipt = await commit_stop();

        final replacement_receipt = await submit_start();

        expect(
          await process_next(new_workflow_id: 'workflow-002'),
          isA<WorkflowProcessingCommitted>(),
        );

        final start = await reader.status_for(start_receipt);
        final stop = await reader.status_for(stop_receipt);
        final replacement = await reader.status_for(replacement_receipt);

        expect(start!.state, WorkflowSubmissionState.completed);
        expect(start.committed_outcome!.workflow_id, workflow_id);
        expect(start.committed_outcome!.version, 1);
        expect(
          start.committed_outcome!.event_type,
          WorkflowStartedEvent.type_id,
        );

        expect(stop!.state, WorkflowSubmissionState.completed);
        expect(stop.committed_outcome!.workflow_id, workflow_id);
        expect(stop.committed_outcome!.version, 2);
        expect(stop.committed_outcome!.event_type, WorkflowEndedEvent.type_id);

        expect(replacement!.committed_outcome!.workflow_id, 'workflow-002');

        expect(
          start.committed_outcome!.sequence,
          lessThan(stop.committed_outcome!.sequence),
        );

        expect(
          stop.committed_outcome!.sequence,
          lessThan(replacement.committed_outcome!.sequence),
        );
      },
    );

    test('does not depend on the unfinished-workflow projection', () async {
      final receipt = await commit_start();

      // Historical resolution concerns the accepted command and journal,
      // not the derived projection used by current-state restoration.
      await database.delete(database.unfinishedWorkflows).go();

      final resolution = await reader.status_for(receipt);

      expect(resolution!.state, WorkflowSubmissionState.completed);
      expect(resolution.committed_outcome!.workflow_id, workflow_id);
      expect(resolution.committed_outcome!.version, 1);
    });
  });

  group('durable resolution integrity', () {
    test('rejects completion without committed journal evidence', () async {
      final receipt = await submit_start();

      await (database.update(
        database.workflowSubmissions,
      )..where((row) => row.event_id.equals(receipt.event_id))).write(
        const WorkflowSubmissionsCompanion(
          processing_state: Value('completed'),
        ),
      );

      await expectLater(
        reader.status_for(receipt),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-completed states with committed outcomes', () async {
      final receipt = await commit_start();

      const timestamp = 1795618800000;

      final contradictory_states = [
        const WorkflowSubmissionsCompanion(processing_state: Value('pending')),
        const WorkflowSubmissionsCompanion(
          processing_state: Value('rejected'),
          rejection_code: Value('ownership_conflict'),
          rejected_at_unix_ms: Value(timestamp),
        ),
        const WorkflowSubmissionsCompanion(
          processing_state: Value('quarantined'),
          rejection_code: Value(null),
          rejected_at_unix_ms: Value(null),
          quarantine_code: Value('undecodable_command'),
          quarantine_diagnostic: Value('Internal diagnostic.'),
          quarantined_at_unix_ms: Value(timestamp),
        ),
      ];

      for (final mutation in contradictory_states) {
        await (database.update(database.workflowSubmissions)
              ..where((row) => row.event_id.equals(receipt.event_id)))
            .write(mutation);

        await expectLater(
          reader.status_for(receipt),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects contradictory persisted resolution metadata', () async {
      final receipt = await submit_start();

      await (database.update(
        database.workflowSubmissions,
      )..where((row) => row.event_id.equals(receipt.event_id))).write(
        const WorkflowSubmissionsCompanion(
          rejection_code: Value('ownership_conflict'),
        ),
      );

      await expectLater(
        reader.status_for(receipt),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unknown persisted processing states', () async {
      final receipt = await submit_start();

      await (database.update(
        database.workflowSubmissions,
      )..where((row) => row.event_id.equals(receipt.event_id))).write(
        const WorkflowSubmissionsCompanion(
          processing_state: Value('unsupported'),
        ),
      );

      await expectLater(
        reader.status_for(receipt),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects inconsistent outcome causation', () async {
      final receipt = await commit_start();

      await (database.update(
        database.workflowEvents,
      )..where((row) => row.causation_id.equals(receipt.event_id))).write(
        const WorkflowEventsCompanion(
          causation_id: Value('incorrect-causation'),
        ),
      );

      await expectLater(
        reader.status_for(receipt),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects inconsistent outcome correlation', () async {
      final receipt = await commit_start();

      await (database.update(
        database.workflowEvents,
      )..where((row) => row.causation_id.equals(receipt.event_id))).write(
        const WorkflowEventsCompanion(
          correlation_id: Value('incorrect-correlation'),
        ),
      );

      await expectLater(
        reader.status_for(receipt),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects inconsistent journal ownership metadata', () async {
      final receipt = await commit_start();

      await (database.update(
        database.workflowEvents,
      )..where((row) => row.causation_id.equals(receipt.event_id))).write(
        const WorkflowEventsCompanion(os_user_id: Value('incorrect-owner')),
      );

      await expectLater(
        reader.status_for(receipt),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects Start outcomes for a different accepted root', () async {
      final receipt = await commit_start();

      final different_command = WorkflowStartEvent(
        target_id: target_id,
        root: TargetPath('/different-root'),
      );

      await (database.update(
        database.workflowSubmissions,
      )..where((row) => row.event_id.equals(receipt.event_id))).write(
        WorkflowSubmissionsCompanion(
          payload_json: Value(runtime.codec.encode(different_command)),
        ),
      );

      await expectLater(
        reader.status_for(receipt),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects Stop outcomes for a different accepted workflow', () async {
      await commit_start();

      final receipt = await commit_stop();

      final different_command = WorkflowStopEvent(
        workflow_id: 'different-workflow',
      );

      await (database.update(
        database.workflowSubmissions,
      )..where((row) => row.event_id.equals(receipt.event_id))).write(
        WorkflowSubmissionsCompanion(
          payload_json: Value(runtime.codec.encode(different_command)),
        ),
      );

      await expectLater(
        reader.status_for(receipt),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

/// Supplies deterministic trusted workflow identities for integration tests.
final class _IdentityProvider implements WorkflowIdentityProvider {
  /// Binds the proposed [workflow_id] to the trusted [os_user_id].
  const _IdentityProvider({
    required this.workflow_id,
    required this.os_user_id,
  });

  /// Deterministic identifier assigned during workflow establishment.
  final String workflow_id;

  /// Trusted owner of the proposed workflow identity.
  final String os_user_id;

  /// Proposes an identity preserving the accepted Start request bindings.
  ///
  /// Returns a workflow identity for [submission].
  /// Throws [StateError] for unsupported command types.
  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final command = submission.command;

    if (command is! WorkflowStartEvent) {
      throw StateError('Expected a workflow Start command.');
    }

    return WorkflowIdentity(
      workflow_id: workflow_id,
      os_user_id: os_user_id,
      target_id: command.target_id,
      root: command.root,
    );
  }
}
