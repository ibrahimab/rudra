import 'dart:io';

import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/non_initializing_workflow_submission_status_reader.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies storage-presence policy independently of SQLite execution.
void main() {
  final receipt = EventSubmissionReceipt(
    event_id: 'fixture-event',
    correlation_id: 'fixture-correlation',
  );

  late Directory directory;
  late File database_file;
  late _StatusReader delegate;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'rudra-non-initializing-status-',
    );

    database_file = File('${directory.path}/rudra.db');

    delegate = _StatusReader();
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  /// Creates a storage-presence guard using the controlled delegate.
  NonInitializingWorkflowSubmissionStatusReader create_reader() {
    return NonInitializingWorkflowSubmissionStatusReader(
      database_file: database_file,
      delegate: delegate,
    );
  }

  test('missing storage returns absence without delegation', () async {
    final reader = create_reader();

    expect(await reader.status_for(receipt), isNull);
    expect(await reader.status_for(receipt), isNull);

    expect(delegate.receipts, isEmpty);
    expect(await database_file.exists(), isFalse);
  });

  test('delegates when storage becomes available', () async {
    final reader = create_reader();

    expect(await reader.status_for(receipt), isNull);

    // The file represents storage presence only. This fixture
    // never opens a SQLite database.
    await database_file.create();

    final resolution = await reader.status_for(receipt);

    expect(resolution!.receipt, same(receipt));
    expect(resolution.state, WorkflowSubmissionState.pending);
    expect(delegate.receipts, [receipt]);
  });

  test('rejects disappearance of initially available storage', () async {
    await database_file.create();

    final reader = create_reader();

    await database_file.delete();

    await expectLater(reader.status_for(receipt), throwsStateError);

    expect(delegate.receipts, isEmpty);
  });

  test('rejects disappearance after observing storage', () async {
    final reader = create_reader();

    await database_file.create();

    expect(await reader.status_for(receipt), isNotNull);

    await database_file.delete();

    await expectLater(reader.status_for(receipt), throwsStateError);

    expect(delegate.receipts, [receipt]);
  });

  test('preserves delegate integrity failures', () async {
    await database_file.create();

    final failure = FormatException('Invalid durable resolution.');

    delegate.failure = failure;

    final reader = create_reader();

    await expectLater(reader.status_for(receipt), throwsA(same(failure)));

    expect(delegate.receipts, [receipt]);
  });
}

/// Records authoritative resolution-reader invocations.
final class _StatusReader implements WorkflowSubmissionStatusReader {
  /// Receipts supplied to the delegate.
  final List<EventSubmissionReceipt> receipts = [];

  /// Optional injected resolution failure.
  Object? failure;

  /// Returns a pending resolution for [receipt] or propagates
  /// the configured failure.
  @override
  Future<WorkflowSubmissionResolution?> status_for(
    EventSubmissionReceipt receipt,
  ) async {
    receipts.add(receipt);

    final error = failure;

    if (error != null) {
      throw error;
    }

    return WorkflowSubmissionResolution(
      receipt: receipt,
      state: WorkflowSubmissionState.pending,
    );
  }
}
