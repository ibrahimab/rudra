import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:test/test.dart';

/// Integration tests for the public SQLite persistence composition.
///
/// These tests exercise RudraSqlitePersistence through SDK
/// contracts rather than directly accessing Drift tables.
///
/// Each test owns its temporary database file and the
/// complete lifecycle of its persistence instances.
///
/// This avoids sharing the database fixture used by
/// individual persistence adapter tests.
void main() {
  test('frontend can recover submission results after restart', () async {
    const scope_id = 'trusted-scope';
    const os_user_id = 'trusted-os-user';

    // This test owns its temporary directory independently.
    final directory = await Directory.systemTemp.createTemp(
      'rudra-sqlite-persistence-test-',
    );

    final database_file = File('${directory.path}/rudra.db');

    final registry = WorkflowModuleRegistry()
      ..register(const LifecycleWorkflowModule());

    final codec = WorkflowEventCodec.from_registry(registry);

    late EventSubmissionReceipt first;
    late EventSubmissionReceipt second;

    try {
      // Only one persistence instance is active at a time.
      final persistence = RudraSqlitePersistence(
        database_file: database_file,
        scope_id: scope_id,
        codec: codec,
      );

      try {
        final events = EventManager(store: persistence.event_submission_store);

        first = await events.trigger(
          WorkflowStartEvent(
            target_id: 'local-macos',
            root: TargetPath('/first'),
          ),
        );

        second = await events.trigger(
          WorkflowStartEvent(
            target_id: 'local-macos',
            root: TargetPath('/second'),
          ),
        );

        // Acceptance must not imply completed processing.
        final initial_status = await persistence.workflow_status_reader
            .status_for(first);

        expect(initial_status!.state, WorkflowSubmissionState.pending);

        /// Creates a processor from public SDK contracts.
        WorkflowProcessor make_processor(String workflow_id) {
          return WorkflowProcessor(
            registry: registry,
            inbox: persistence.workflow_inbox,
            identity_provider: _TestIdentityProvider(
              workflow_id: workflow_id,
              os_user_id: os_user_id,
            ),
            committer: persistence.workflow_committer,
            rejector: persistence.workflow_rejector,
          );
        }

        final committed = await make_processor('frontend-workflow-1')
            .process_next();

        expect(committed, isA<WorkflowProcessingCommitted>());

        final rejected = await make_processor('frontend-workflow-2')
            .process_next();

        expect(rejected, isA<WorkflowProcessingRejected>());

        // Verify persisted status rather than relying on
        // the processor's immediate return values.
        final completed_status = await persistence.workflow_status_reader
            .status_for(first);

        final rejected_status = await persistence.workflow_status_reader
            .status_for(second);

        expect(completed_status!.state, WorkflowSubmissionState.completed);

        expect(rejected_status!.state, WorkflowSubmissionState.rejected);

        expect(
          rejected_status.rejection_code,
          WorkflowRejectionCode.ownership_conflict,
        );
      } finally {
        // Finish all operations and release the first
        // database connection before simulating restart.
        await persistence.close();
      }

      // Reopen the same database file with a fresh
      // persistence instance, simulating application restart.
      final reopened = RudraSqlitePersistence(
        database_file: database_file,
        scope_id: scope_id,
        codec: codec,
      );

      try {
        final first_status = await reopened.workflow_status_reader.status_for(
          first,
        );

        final second_status = await reopened.workflow_status_reader.status_for(
          second,
        );

        expect(first_status!.state, WorkflowSubmissionState.completed);

        expect(second_status!.state, WorkflowSubmissionState.rejected);

        expect(
          second_status.rejection_code,
          WorkflowRejectionCode.ownership_conflict,
        );
      } finally {
        await reopened.close();
      }
    } finally {
      // Clean up the filesystem after all connections
      // have been released, including on test failure.
      await directory.delete(recursive: true);
    }
  });
}

/// Deterministic identity provider for persistence tests.
///
/// Supplies trusted identities without relying on the
/// host operating system or randomly generated identifiers.
///
/// The submitted command determines the requested target
/// and inspection root. The workflow and OS-user IDs
/// are supplied independently by test composition.
final class _TestIdentityProvider implements WorkflowIdentityProvider {
  /// Creates a provider with predictable identity values.
  const _TestIdentityProvider({
    required this.workflow_id,
    required this.os_user_id,
  });

  /// Workflow ID to establish when processing succeeds.
  final String workflow_id;

  /// Trusted OS-user identity used for ownership enforcement.
  final String os_user_id;

  /// Proposes an identity consistent with the start request.
  ///
  /// Only workflow-start commands are supported by this
  /// fixture. Other command types indicate incorrect test
  /// configuration and produce [StateError].
  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final command = submission.command;

    if (command is! WorkflowStartEvent) {
      throw StateError('Test provider supports workflow start commands only.');
    }

    return WorkflowIdentity(
      workflow_id: workflow_id,
      os_user_id: os_user_id,
      target_id: command.target_id,
      root: command.root,
    );
  }
}
