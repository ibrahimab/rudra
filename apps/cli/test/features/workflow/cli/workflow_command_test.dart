import 'dart:io';

import 'package:rudra_cli/rudra_cli.dart';
import 'package:rudra_cli/rudra_product_cli.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../../../support/cli_host_fixture.dart';

/// Verifies explicit workflow lifecycle actions through the CLI.
///
/// Tests use real SQLite persistence and SDK workflow processing,
/// but never inspect or modify an actual filesystem target.
///
/// Each fixture owns its temporary database. Persistence
/// connections are opened and closed by application composition.
void main() {
  late Directory directory;
  late File database_file;
  late CliHostFixture host;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'rudra-workflow-cli-test-',
    );

    database_file = File('${directory.path}/rudra.sqlite');

    addTearDown(() => directory.delete(recursive: true));
    host = CliHostFixture(
      inspector: _UnusedInspector(),
      target_id: 'fixture-filesystem',
      database_file: database_file,
    );
  });

  /// Creates a fresh CLI invocation using the same persistence
  /// location and trusted test identity.
  RudraCli create_cli(StringBuffer output, {StringBuffer? error_output}) {
    return compose_product_cli(
      sdk_composition: host.composition(),
      output: output,
      error_output: error_output ?? StringBuffer(),
    );
  }

  test('registration does not create a workflow database', () {
    final cli = create_cli(StringBuffer());

    expect(cli.command_names, contains('workflow'));
    expect(cli.module_ids, contains('rudra.product.workflow'));
    expect(database_file.existsSync(), isFalse);
  });

  test('explicit start creates and commits a workflow', () async {
    final output = StringBuffer();

    final status = await create_cli(output)
        .run(['workflow', 'start', '/fixture']);

    expect(status, RudraExitCode.success.value);
    expect(output.toString(), contains('Workflow: STARTED'));
    expect(output.toString(), contains('Version: 1'));
    expect(database_file.existsSync(), isTrue);

    final restored = await host.current();

    expect(restored, isNotNull);
    expect(restored!.version, 1);
    expect(restored.identity.os_user_id, 'test-os-user');
    expect(restored.identity.target_id, host.target_id);
    expect(restored.identity.root.value, '/fixture');
  });

  test('fresh CLI invocation preserves the existing workflow', () async {
    final first_cli = create_cli(StringBuffer());

    expect(
      await first_cli.run(['workflow', 'start']),
      RudraExitCode.success.value,
    );

    final first = await host.current();

    expect(first, isNotNull);

    // A new CLI invocation must not create a second workflow.
    final errors = StringBuffer();

    final second_cli = create_cli(StringBuffer(), error_output: errors);

    final second_status = await second_cli.run(['workflow', 'start']);

    expect(second_status, RudraExitCode.workflow_conflict.value);
    expect(errors.toString(), contains('Workflow already active.'));

    final restored = await host.current();

    expect(restored, isNotNull);
    expect(restored!.identity.workflow_id, first!.identity.workflow_id);
    expect(restored.version, first.version);
    expect(restored.identity.root.value, first.identity.root.value);
  });

  test('explicit stop commits and allows a new workflow', () async {
    expect(
      await create_cli(StringBuffer()).run(['workflow', 'start', '/fixture']),
      RudraExitCode.success.value,
    );

    final original = await host.current();

    expect(original, isNotNull);

    final output = StringBuffer();

    final status = await create_cli(output).run(['workflow', 'stop']);

    expect(status, RudraExitCode.success.value);
    expect(output.toString(), contains('Workflow: ENDED'));
    expect(
      output.toString(),
      contains('ID: ${original!.identity.workflow_id}'),
    );

    // Stop preserves persistent storage but releases the
    // user's unfinished-workflow reservation.
    expect(database_file.existsSync(), isTrue);
    expect(await host.current(), isNull);

    // A new explicit Start may establish another workflow.
    expect(
      await create_cli(StringBuffer()).run(['workflow', 'start', '/fixture']),
      RudraExitCode.success.value,
    );

    final next = await host.current();

    expect(next, isNotNull);
    expect(next!.version, 1);
    expect(next.identity.workflow_id, isNot(original.identity.workflow_id));
  });

  test('stop without a workflow does not create persistence', () async {
    final output = StringBuffer();
    final errors = StringBuffer();

    final status = await create_cli(
      output,
      error_output: errors,
    ).run(['workflow', 'stop']);

    expect(status, RudraExitCode.workflow_conflict.value);
    expect(errors.toString(), contains('No active workflow to stop.'));
    expect(output.toString(), isEmpty);
    expect(database_file.existsSync(), isFalse);
  });

  test('explicit identified Stop durably records workflow absence', () async {
    expect(database_file.existsSync(), isFalse);

    final outcome = await host.using_client(
      (sdk) => sdk.workflows.stop(
        workflow_id: 'previous-workflow',
        idempotency_key: 'stop-previous',
      ),
    );

    expect(outcome, isA<WorkflowOperationResolved>());

    final resolution = (outcome as WorkflowOperationResolved).resolution;

    expect(resolution.state, WorkflowSubmissionState.rejected);
    expect(
      resolution.rejection_code,
      WorkflowRejectionCode.workflow_not_active,
    );

    expect(database_file.existsSync(), isTrue);
    expect(await host.current(), isNull);

    final retried = await host.using_client(
      (sdk) => sdk.workflows.stop(
        workflow_id: 'previous-workflow',
        idempotency_key: 'stop-previous',
      ),
    );

    final retried_resolution =
        (retried as WorkflowOperationResolved).resolution;

    expect(retried_resolution.receipt.event_id, resolution.receipt.event_id);

    expect(
      retried_resolution.receipt.correlation_id,
      resolution.receipt.correlation_id,
    );

    expect(
      retried_resolution.rejected_at_unix_ms,
      resolution.rejected_at_unix_ms,
    );
  });

  test('repeated stop reports an expected workflow conflict', () async {
    expect(
      await create_cli(StringBuffer()).run(['workflow', 'start']),
      RudraExitCode.success.value,
    );

    expect(
      await create_cli(StringBuffer()).run(['workflow', 'stop']),
      RudraExitCode.success.value,
    );

    final errors = StringBuffer();

    final status = await create_cli(
      StringBuffer(),
      error_output: errors,
    ).run(['workflow', 'stop']);

    expect(status, RudraExitCode.workflow_conflict.value);
    expect(errors.toString(), contains('No active workflow to stop.'));

    expect(await host.current(), isNull);
    expect(database_file.existsSync(), isTrue);
  });

  test('stop rejects unexpected arguments without persistence', () async {
    final errors = StringBuffer();

    final status = await create_cli(
      StringBuffer(),
      error_output: errors,
    ).run(['workflow', 'stop', '/fixture']);

    expect(status, RudraExitCode.invalid_usage.value);
    expect(
      errors.toString(),
      contains('Workflow stop does not accept arguments.'),
    );
    expect(database_file.existsSync(), isFalse);
  });

  test('invalid root never initializes persistence', () async {
    final cli = create_cli(StringBuffer());

    final status = await cli.run(['workflow', 'start', 'relative-directory']);

    expect(status, RudraExitCode.invalid_usage.value);
    expect(database_file.existsSync(), isFalse);
  });

  test(
    'CLI Stop cannot terminate a replacement after selecting the old workflow',
    () async {
      expect(
        await create_cli(StringBuffer()).run(['workflow', 'start']),
        RudraExitCode.success.value,
      );
      final original = (await host.current())!;
      final stale_read = host.hold_next_response();
      final errors = StringBuffer();
      final stopping = create_cli(
        StringBuffer(),
        error_output: errors,
      ).run(['workflow', 'stop']);
      stopping.ignore();

      try {
        // The selected state is already built, but the first client has not
        // received it. Replace the workflow from independent connections.
        await stale_read.entered;
        expect(
          await create_cli(StringBuffer()).run(['workflow', 'stop']),
          RudraExitCode.success.value,
        );
        expect(
          await create_cli(StringBuffer()).run(['workflow', 'start']),
          RudraExitCode.success.value,
        );
        final replacement = (await host.current())!;
        expect(
          replacement.identity.workflow_id,
          isNot(original.identity.workflow_id),
        );

        stale_read.release();
        expect(await stopping, RudraExitCode.workflow_conflict.value);
        expect(errors.toString(), contains('Active workflow changed'));
        expect(
          (await host.current())!.identity.workflow_id,
          replacement.identity.workflow_id,
        );
      } finally {
        stale_read.release();
        await stopping;
      }
    },
  );

  test('expected workflow ID cannot stop a replacement workflow', () async {
    expect(
      await create_cli(StringBuffer()).run(['workflow', 'start']),
      RudraExitCode.success.value,
    );

    final original = (await host.current())!;

    // Simulate another frontend ending the explicitly selected workflow.
    final original_stop = await host.using_client(
      (sdk) => sdk.workflows.stop(
        workflow_id: original.identity.workflow_id,
        idempotency_key: 'stop-original',
      ),
    );

    expect(
      (original_stop as WorkflowOperationResolved).resolution.state,
      WorkflowSubmissionState.completed,
    );

    // Another explicit action establishes a replacement workflow.
    expect(
      await create_cli(StringBuffer()).run(['workflow', 'start']),
      RudraExitCode.success.value,
    );

    final replacement = await host.current();

    expect(replacement, isNotNull);
    expect(
      replacement!.identity.workflow_id,
      isNot(original.identity.workflow_id),
    );

    // Explorer still displays the original workflow ID.
    // It must not silently stop the replacement.
    final stale_stop = await host.using_client(
      (sdk) => sdk.workflows.stop(
        workflow_id: original.identity.workflow_id,
        idempotency_key: 'stale-stop',
      ),
    );

    expect(stale_stop, isA<WorkflowOperationResolved>());

    final stale_resolution =
        (stale_stop as WorkflowOperationResolved).resolution;

    expect(stale_resolution.state, WorkflowSubmissionState.rejected);

    expect(
      stale_resolution.rejection_code,
      WorkflowRejectionCode.workflow_id_mismatch,
    );

    final restored = await host.current();

    expect(restored, isNotNull);
    expect(restored!.identity.workflow_id, replacement.identity.workflow_id);
    expect(restored.version, 1);
  });
}

/// Rejects unexpected filesystem inspection.
///
/// Workflow establishment persists intent and domain events.
/// It must not inspect filesystem entries as a side effect.
final class _UnusedInspector implements TargetInspector {
  @override
  Future<TargetCapabilities> capabilities_for(TargetPath path) async {
    throw StateError('Unexpected capability inspection.');
  }

  @override
  Future<FilesystemEntry> inspect(TargetPath path) async {
    throw StateError('Unexpected filesystem inspection.');
  }

  @override
  Stream<TargetPath> list_directory(TargetPath path) {
    return Stream.error(StateError('Unexpected directory enumeration.'));
  }

  @override
  Future<TargetPath> read_symbolic_link(TargetPath path) async {
    throw StateError('Unexpected symbolic-link inspection.');
  }
}
