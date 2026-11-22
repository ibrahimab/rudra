// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:rudra_persistence_sqlite/src/database/rudra_database.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;

/// Verifies migration behavior through this file's focused tests.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = RudraDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // The following template shows how to write tests ensuring your migrations
  // preserve existing data.
  // Testing this can be useful for migrations that change existing columns
  // (e.g. by alterating their type or constraints). Migrations that only add
  // tables or columns typically don't need these advanced tests. For more
  // information, see https://drift.simonbinder.eu/migrations/tests/#verifying-data-integrity
  // TODO: This generated template shows how these tests could be written. Adopt
  // it to your own needs when testing migrations with data integrity.
  test('migration from v1 to v2 does not corrupt data', () async {
    // Add data to insert into the old database, and the expected rows after the
    // migration.
    // TODO: Fill these lists
    final oldWorkflowSubmissionsData = <v1.WorkflowSubmissionsData>[];
    final expectedNewWorkflowSubmissionsData = <v2.WorkflowSubmissionsData>[];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: RudraDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.workflowSubmissions, oldWorkflowSubmissionsData);
      },
      validateItems: (newDb) async {
        expect(
          expectedNewWorkflowSubmissionsData,
          await newDb.select(newDb.workflowSubmissions).get(),
        );
      },
    );
  });

  test('v4 committed owner history remains indexed after migration', () async {
    const legacy_workflow_id = 'legacy-workflow';
    const legacy_os_user_id = 'legacy-os-user';

    // These events have the schema-v4 committed journal shape.
    // No extra ownership table or backfill operation is needed.
    final legacy_events = <v4.WorkflowEventsData>[
      const v4.WorkflowEventsData(
        sequence: 1,
        eventId: 'legacy-start',
        workflowId: legacy_workflow_id,
        version: 1,
        correlationId: 'legacy-correlation',
        eventType: 'workflow.start',
        payloadJson:
            '{"schema_version":1,'
            '"target_id":"local-macos",'
            '"root":"/workspace"}',
        recordedAtUnixMs: 1,
      ),
      const v4.WorkflowEventsData(
        sequence: 2,
        eventId: 'legacy-started',
        workflowId: legacy_workflow_id,
        version: 2,
        correlationId: 'legacy-correlation',
        causationId: 'legacy-start',
        eventType: 'workflow.started',
        payloadJson:
            '{"schema_version":1,'
            '"workflow_id":"legacy-workflow",'
            '"os_user_id":"legacy-os-user",'
            '"target_id":"local-macos",'
            '"root":"/workspace"}',
        recordedAtUnixMs: 2,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 4,
      newVersion: 5,
      createOld: v4.DatabaseAtV4.new,
      createNew: v5.DatabaseAtV5.new,
      openTestedDatabase: RudraDatabase.new,
      createItems: (batch, old_db) {
        batch.insertAll(old_db.workflowEvents, legacy_events);
      },
      validateItems: (new_db) async {
        // The original journal must remain intact.
        final history = await new_db.select(new_db.workflowEvents).get();

        expect(history, hasLength(2));

        // The migrated index must discover the historical owner.
        final indexed = await new_db
            .customSelect(
              '''

          SELECT DISTINCT workflow_id
          FROM workflow_events
            INDEXED BY workflow_events_owner_idx
          WHERE os_user_id = ?

          ''',
              variables: [Variable.withString(legacy_os_user_id)],
            )
            .get();

        expect(indexed.map((row) => row.read<String>('workflow_id')), [
          legacy_workflow_id,
        ]);
      },
    );
  });
}
