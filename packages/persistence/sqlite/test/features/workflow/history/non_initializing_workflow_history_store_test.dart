import 'dart:io';

import 'package:rudra_persistence_sqlite/src/features/workflow/history/non_initializing_workflow_history_store.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests missing-storage behavior independently of SQLite query execution.
void main() {
  const os_user_id = 'trusted-owner';

  late Directory directory;
  late File database_file;
  late _RecordingHistoryStore delegate;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'rudra-history-presence-',
    );

    database_file = File('${directory.path}/rudra.db');
    delegate = _RecordingHistoryStore();
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('returns empty evidence without creating the database', () async {
    final store = NonInitializingWorkflowHistoryStore(
      database_file: database_file,
      delegate: delegate,
    );

    final evidence = await store.load_restoration_evidence(
      os_user_id: os_user_id,
    );

    expect(evidence.projected, isNull);
    expect(evidence.other_histories, isEmpty);
    expect(delegate.read_count, 0);
    expect(await database_file.exists(), isFalse);
  });

  test('delegates restoration when storage exists', () async {
    await database_file.create();

    final store = NonInitializingWorkflowHistoryStore(
      database_file: database_file,
      delegate: delegate,
    );

    await store.load_restoration_evidence(os_user_id: os_user_id);

    expect(delegate.read_count, 1);
    expect(delegate.last_owner, os_user_id);
  });

  test('fails when previously observed storage disappears', () async {
    await database_file.create();

    final store = NonInitializingWorkflowHistoryStore(
      database_file: database_file,
      delegate: delegate,
    );

    await store.load_restoration_evidence(os_user_id: os_user_id);
    await database_file.delete();

    await expectLater(
      store.load_restoration_evidence(os_user_id: os_user_id),
      throwsStateError,
    );

    expect(delegate.read_count, 1);
  });

  test('rejects blank owner before attempting restoration', () async {
    final store = NonInitializingWorkflowHistoryStore(
      database_file: database_file,
      delegate: delegate,
    );

    await expectLater(
      store.load_restoration_evidence(os_user_id: ' '),
      throwsArgumentError,
    );

    expect(delegate.read_count, 0);
  });
}

/// Records calls to an authoritative workflow-history reader.
final class _RecordingHistoryStore implements WorkflowHistoryStore {
  /// Number of delegated restoration reads.
  int read_count = 0;

  /// Authenticated owner from the most recent delegated read.
  String? last_owner;

  /// Returns empty evidence while recording the requested [os_user_id].
  ///
  /// No database or filesystem operations are performed.
  @override
  Future<WorkflowRestorationEvidence> load_restoration_evidence({
    required String os_user_id,
  }) async {
    read_count++;
    last_owner = os_user_id;

    return WorkflowRestorationEvidence(
      projected: null,
      other_histories: const [],
    );
  }
}
