import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:rudra_persistence_sqlite/src/database/rudra_database.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'fixtures/shared_database_worker.dart';

void main() {
  late File file;

  setUpAll(() {
    // we're disabling the warning because we're deliberately testing independent
    // connections. That's precisely what our multi-user host architecture requires.
    final previous_value = driftRuntimeOptions.dontWarnAboutMultipleDatabases;

    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    addTearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous_value;
    });
  });

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('rudra-shared-db-');
    addTearDown(() => directory.delete(recursive: true));
    file = File('${directory.path}/rudra.sqlite');
  });

  WorkflowApplication application_for(String owner) {
    final (persistence, application) = shared_context(file, owner);
    addTearDown(persistence.close);
    return application;
  }

  test('independent processes initialize and commit to one database', () async {
    const owners = ['synthetic-first', 'synthetic-second'];
    final workers = await Future.wait(
      owners.map((owner) async {
        final worker = await Process.start(Platform.resolvedExecutable, [
          'run',
          'test/integration/fixtures/shared_database_worker.dart',
          file.path,
          owner,
        ]);
        final errors = worker.stderr.transform(utf8.decoder).join();
        final lines = StreamIterator(
          worker.stdout.transform(utf8.decoder).transform(const LineSplitter()),
        );
        addTearDown(() async {
          worker.kill(ProcessSignal.sigkill);
          await worker.exitCode;
          await lines.cancel();
        });
        expect(
          await lines.moveNext(),
          isTrue,
          reason: 'Worker $owner did not reach the barrier.',
        );
        expect(lines.current, 'ready');
        return (process: worker, lines: lines, errors: errors, owner: owner);
      }),
    );

    expect(await file.exists(), isFalse);
    for (final worker in workers) {
      worker.process.stdin.writeln('start');
    }

    final identities = await Future.wait(
      workers.map((worker) async {
        await worker.process.stdin.close();
        final status = await worker.process.exitCode;
        expect(status, 0, reason: await worker.errors);
        expect(await worker.lines.moveNext(), isTrue);
        final id = worker.lines.current;
        final app = application_for(worker.owner);
        final state = await app.read_state();
        expect(state.workflows.current_workflow!.identity.workflow_id, id);
        expect(
          state.workflows.current_workflow!.identity.os_user_id,
          worker.owner,
        );
        return id;
      }),
    );
    expect(identities.toSet(), hasLength(2));

    final database = RudraDatabase.file(file);
    addTearDown(database.close);
    expect(
      (await database.customSelect('PRAGMA integrity_check').getSingle())
          .data
          .values
          .single,
      'ok',
    );
    expect(await database.select(database.workflowEvents).get(), hasLength(2));
  }, timeout: Timeout(Duration(minutes: 2)));

  test(
    'acceptance, inbox, processing, rejection, and quarantine are owner scoped',
    () async {
      final first = application_for('first');
      final second = application_for('second');
      expect((await first.read_state()).workflows.current_workflow, isNull);
      expect((await second.read_state()).workflows.current_workflow, isNull);
      expect(await file.exists(), isFalse);

      final command = WorkflowStartEvent(
        target_id: 'fixture-filesystem',
        root: TargetPath('/fixture'),
      );
      final accepted = await first.submit_command(
        command,
        idempotency_key: 'matching-key',
      );
      expect(await second.process_next(), isA<WorkflowProcessingIdle>());
      expect(await second.status_for(accepted), isNull);

      final independent = await second.submit_command(
        command,
        idempotency_key: 'matching-key',
      );
      expect(independent.event_id, isNot(accepted.event_id));
      expect(await first.status_for(independent), isNull);

      final results = await Future.wait([
        first.process_next(),
        second.process_next(),
      ]);
      expect(results, everyElement(isA<WorkflowProcessingCommitted>()));
      final first_id = (await first.read_state())
          .workflows
          .current_workflow!
          .identity
          .workflow_id;
      final second_id = (await second.read_state())
          .workflows
          .current_workflow!
          .identity
          .workflow_id;
      expect(first_id, isNot(second_id));

      final conflict = await first.submit_command(
        command,
        idempotency_key: 'second-start',
      );
      final foreign_stop = await second.submit_command(
        WorkflowStopEvent(workflow_id: first_id),
        idempotency_key: 'foreign-stop',
      );
      final rejected = await Future.wait([
        first.process_next(),
        second.process_next(),
      ]);
      expect(
        rejected[0],
        isA<WorkflowProcessingRejected>().having(
          (value) => value.code,
          'code',
          WorkflowRejectionCode.ownership_conflict,
        ),
      );
      expect(
        rejected[1],
        isA<WorkflowProcessingRejected>().having(
          (value) => value.code,
          'code',
          WorkflowRejectionCode.workflow_id_mismatch,
        ),
      );
      expect(await first.status_for(foreign_stop), isNull);
      expect(await second.status_for(conflict), isNull);
      expect(
        (await first.read_state())
            .workflows
            .current_workflow!
            .identity
            .workflow_id,
        first_id,
      );
      expect(
        (await second.read_state())
            .workflows
            .current_workflow!
            .identity
            .workflow_id,
        second_id,
      );

      // Simulate a durable submission encoded by an unsupported codec using
      // the test connection. This exercises existing application quarantine.
      final unreadable = await second.submit_command(
        command,
        idempotency_key: 'unreadable',
      );
      final database = RudraDatabase.file(file);
      addTearDown(database.close);
      await database.customStatement(
        'UPDATE workflow_submissions SET payload_json = ? WHERE event_id = ?',
        ['not-json', unreadable.event_id],
      );
      expect(await first.process_next(), isA<WorkflowProcessingIdle>());
      expect(
        (await second.status_for(unreadable))!.state,
        WorkflowSubmissionState.pending,
      );
      expect(await second.process_next(), isA<WorkflowProcessingQuarantined>());
      expect(
        (await second.status_for(unreadable))!.state,
        WorkflowSubmissionState.quarantined,
      );
      expect(await first.status_for(unreadable), isNull);
    },
  );

  test(
    'write contention times out without accepting or repeating a command',
    () async {
      final app = application_for('first');
      final command = WorkflowStartEvent(
        target_id: 'fixture-filesystem',
        root: TargetPath('/fixture'),
      );
      final initial = await app.submit_command(
        command,
        idempotency_key: 'initial',
      );
      expect(await app.process_next(), isA<WorkflowProcessingCommitted>());
      final blocker = sqlite3.open(file.path);
      try {
        blocker.execute('BEGIN IMMEDIATE');
        await expectLater(
          app.submit_command(command, idempotency_key: 'contended'),
          throwsA(
            isA<EventSubmissionException>()
                .having(
                  (error) => error.code,
                  'code',
                  EventSubmissionErrorCode.persistence_failed,
                )
                .having(
                  (error) => error.message,
                  'SQLite failure',
                  contains('database is locked (code 5)'),
                ),
          ),
        );
        expect(
          blocker
              .select('SELECT count(*) FROM workflow_submissions')
              .single
              .values
              .single,
          1,
        );
      } finally {
        blocker.execute('ROLLBACK');
        blocker.close();
      }
      expect(
        (await app.status_for(initial))!.state,
        WorkflowSubmissionState.completed,
      );
      final retry = await app.submit_command(
        command,
        idempotency_key: 'contended',
      );
      expect(
        (await app.status_for(retry))!.state,
        WorkflowSubmissionState.pending,
      );
    },
  );

  test(
    'shared connections retain and can recreate group-writable WAL and SHM',
    () async {
      final provisioning = sqlite3.open(file.path);
      try {
        expect(
          provisioning.select('PRAGMA journal_mode = WAL').single.values.single,
          'wal',
        );
      } finally {
        provisioning.close();
      }
      expect(
        (await Process.run('/bin/chmod', ['0660', file.path])).exitCode,
        0,
      );
      final auxiliary_files = [
        File('${file.path}-wal'),
        File('${file.path}-shm'),
      ];

      Future<void> expect_shared_auxiliary_modes() async {
        final database = RudraDatabase.file(file, require_existing_wal: true);
        try {
          await database.select(database.workflowEvents).get();
        } finally {
          await database.close();
        }

        for (final auxiliary in auxiliary_files) {
          expect(await auxiliary.exists(), isTrue);
          expect((await auxiliary.stat()).mode & 0x1ff, 0x1b0);
        }
      }

      await expect_shared_auxiliary_modes();

      // Simulate offline maintenance only after checkpointing with all contexts
      // closed. A subsequent host recreates backing files with the shared mode.
      final maintenance = sqlite3.open(file.path);
      try {
        expect(
          maintenance.select('PRAGMA wal_checkpoint(TRUNCATE)').single['busy'],
          0,
        );
      } finally {
        maintenance.close();
      }
      for (final auxiliary in auxiliary_files) {
        if (await auxiliary.exists()) await auxiliary.delete();
      }

      await expect_shared_auxiliary_modes();
    },
    skip: !Platform.isMacOS,
  );

  test(
    'provisioned mode rejects a non-WAL database without changing its schema',
    () async {
      sqlite3.open(file.path).close();
      final database = RudraDatabase.file(file, require_existing_wal: true);
      addTearDown(database.close);
      await expectLater(
        database.select(database.workflowEvents).get(),
        throwsA(
          isA<DriftRemoteException>().having(
            (error) => error.remoteCause.toString(),
            'cause',
            contains('requires SQLite WAL mode'),
          ),
        ),
      );
      final inspection = sqlite3.open(file.path);
      try {
        expect(
          inspection.select('PRAGMA journal_mode').single.values.single,
          'delete',
        );
        expect(
          inspection.select('PRAGMA user_version').single.values.single,
          0,
        );
      } finally {
        inspection.close();
      }
    },
  );
}
