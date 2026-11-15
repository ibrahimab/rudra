import 'dart:io';

import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies persistence through its public composition API.
void main() {
  test('recovers submissions through public SDK contracts', () async {
    final runtime = WorkflowRuntime.standard();

    final directory = await Directory.systemTemp.createTemp(
      'rudra-public-persistence-',
    );

    final database_file = File('${directory.path}/rudra.db');

    WorkflowStartEvent request() => WorkflowStartEvent(
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );

    try {
      final first = RudraSqlitePersistence(
        database_file: database_file,
        scope_id: 'test-user',
        runtime: runtime,
      );

      late final EventSubmissionReceipt original;

      try {
        final manager = EventManager(store: first.event_submission_store);

        original = await manager.trigger(
          request(),
          idempotency_key: 'request-1',
        );
      } finally {
        await first.close();
      }

      // Reconstruct the persistence context as a new
      // application invocation would.
      final reopened = RudraSqlitePersistence(
        database_file: database_file,
        scope_id: 'test-user',
        runtime: runtime,
      );

      try {
        final manager = EventManager(store: reopened.event_submission_store);

        final recovered = await manager.trigger(
          request(),
          idempotency_key: 'request-1',
        );

        expect(recovered.event_id, original.event_id);
        expect(recovered.correlation_id, original.correlation_id);
      } finally {
        await reopened.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('rejects an empty submission scope', () {
    expect(
      () => RudraSqlitePersistence(
        database_file: File('unused.db'),
        scope_id: ' ',
        runtime: WorkflowRuntime.standard(),
      ),
      throwsArgumentError,
    );
  });
}
