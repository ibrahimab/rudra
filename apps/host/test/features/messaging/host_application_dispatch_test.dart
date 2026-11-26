import 'dart:async';
import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_host/rudra_host.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../../support/loopback_host_transport.dart';
import '../../support/test_host_ownership_provider.dart';
import '../../support/unused_target_inspector.dart';

/// Verifies authoritative application dispatch through the public
/// communication API and real host-owned SQLite persistence.
void main() {
  const owner = 'test-owner';
  const target_id = 'test-target';
  const operation_timeout = Duration(seconds: 10);

  /// Starts an isolated host and establishes an independent client session.
  ///
  /// [server_peer_override] optionally supplies deliberately inconsistent
  /// authentication evidence to the application handler boundary.
  ///
  /// Returns the executing host composition, authenticated session and
  /// target-native root. All resources are retained for ordered cleanup.
  Future<
    ({HostComposition composition, MessageSession session, TargetPath root})
  >
  create_session({String? server_peer_override}) async {
    final directory = await Directory.systemTemp.createTemp(
      'rudra-host-dispatch-',
    );

    addTearDown(() async {
      await directory.delete(recursive: true);
    });

    final scope = await directory.resolveSymbolicLinks();
    final ownership = TestHostOwnershipProvider();

    final transport = LoopbackHostTransport(
      os_user_id: owner,
      server_peer_override: server_peer_override,
    );

    final shutdown = Completer<void>();
    final ready = Completer<void>();

    final composition = HostComposition(
      identity_provider: const _IdentityProvider(owner),
      ownership_provider: ownership,
      data_directory: directory,
      target_id: target_id,
      inspector: const UnusedTargetInspector(),
      transport_factory: ({required scope_directory, required os_user_id}) {
        expect(scope_directory, scope);
        expect(os_user_id, owner);

        return transport;
      },
      communication_factory:
          ({required transport, required codecs, required handlers}) {
            expect(codecs.is_frozen, isTrue);
            expect(handlers.is_frozen, isTrue);

            return Communication(
              transport: transport,
              codecs: codecs,
              handlers: handlers,
            );
          },
    );

    final running = composition.run(
      shutdown: shutdown.future,
      on_ready: (os_user_id, workflow) {
        expect(os_user_id, owner);
        expect(workflow, isNull);
        expect(ownership.is_owned, isTrue);

        ready.complete();
      },
    );

    running.ignore();

    addTearDown(() async {
      if (!shutdown.isCompleted) {
        shutdown.complete();
      }

      await running.timeout(operation_timeout);

      expect(ownership.is_owned, isFalse);
      expect(ownership.release_count, 1);
    });

    await Future.any<void>([
      ready.future,
      running.then<void>((_) {
        throw StateError('Host terminated before reporting readiness.');
      }),
    ]).timeout(operation_timeout);

    // The client assembles its own codec configuration independently.
    // It receives no access to the host's application or persistence.
    final communication = Communication(
      transport: transport,
      codecs: create_application_message_codecs(),
      options: const MessageSessionOptions(request_timeout: operation_timeout),
    );

    final session = await communication.connect();

    addTearDown(() async {
      try {
        await session.close();
      } finally {
        await communication.done.timeout(operation_timeout);
      }
    });

    return (
      composition: composition,
      session: session,
      root: TargetPath(directory.path),
    );
  }

  group('read-only application dispatch', () {
    test('State Read restores absence without initializing SQLite', () async {
      final fixture = await create_session();

      expect(await fixture.composition.database_file.exists(), isFalse);

      final response = await fixture.session.request(const StateReadRequest());

      expect(response.state.workflows.current_workflow, isNull);

      expect(await fixture.composition.database_file.exists(), isFalse);
    });

    test('unknown submission query does not initialize SQLite', () async {
      final fixture = await create_session();

      final response = await fixture.session.request(
        WorkflowSubmissionRequest(
          receipt: EventSubmissionReceipt(
            event_id: 'unknown-event',
            correlation_id: 'unknown-correlation',
          ),
        ),
      );

      expect(response.resolution, isNull);

      expect(await fixture.composition.database_file.exists(), isFalse);
    });
  });

  group('authoritative workflow dispatch', () {
    test(
      'Start, Submission, State Read and Stop share authoritative state',
      () async {
        final fixture = await create_session();
        final session = fixture.session;

        final started = await session.request(
          WorkflowStartRequest(
            target_id: target_id,
            root: fixture.root,
            idempotency_key: 'start-001',
          ),
        );

        final start_resolution = _completed(started.outcome);
        final established = start_resolution.committed_outcome!;

        expect(established.event_type, WorkflowStartedEvent.type_id);
        expect(established.version, 1);

        final read = await session.request(const StateReadRequest());
        final active = read.state.workflows.current_workflow!;

        expect(active.identity.workflow_id, established.workflow_id);
        expect(active.identity.os_user_id, owner);
        expect(active.identity.target_id, target_id);
        expect(active.identity.root.value, fixture.root.value);
        expect(active.version, 1);

        final submission = await session.request(
          WorkflowSubmissionRequest(receipt: start_resolution.receipt),
        );

        _expect_same_resolution(start_resolution, submission.resolution!);

        final stopped = await session.request(
          WorkflowStopRequest(
            workflow_id: established.workflow_id,
            idempotency_key: 'stop-001',
          ),
        );

        final stop_resolution = _completed(stopped.outcome);
        final terminal = stop_resolution.committed_outcome!;

        expect(terminal.workflow_id, established.workflow_id);
        expect(terminal.event_type, WorkflowEndedEvent.type_id);
        expect(terminal.version, 2);

        final ended = await session.request(const StateReadRequest());

        expect(ended.state.workflows.current_workflow, isNull);

        // The original Start remains historically completed.
        final historical = await session.request(
          WorkflowSubmissionRequest(receipt: start_resolution.receipt),
        );

        _expect_same_resolution(start_resolution, historical.resolution!);

        final historical_stop = await session.request(
          WorkflowSubmissionRequest(receipt: stop_resolution.receipt),
        );

        _expect_same_resolution(stop_resolution, historical_stop.resolution!);
      },
    );

    test(
      'identical Start and Stop retries preserve durable identities',
      () async {
        final fixture = await create_session();
        final session = fixture.session;

        final start_request = WorkflowStartRequest(
          target_id: target_id,
          root: fixture.root,
          idempotency_key: 'start-001',
        );

        final started = _completed(
          (await session.request(start_request)).outcome,
        );

        final retried_start = _completed(
          (await session.request(start_request)).outcome,
        );

        _expect_same_resolution(started, retried_start);

        final stop_request = WorkflowStopRequest(
          workflow_id: started.committed_outcome!.workflow_id,
          idempotency_key: 'stop-001',
        );

        final stopped = _completed(
          (await session.request(stop_request)).outcome,
        );

        final retried_stop = _completed(
          (await session.request(stop_request)).outcome,
        );

        _expect_same_resolution(stopped, retried_stop);

        final historical_start = _completed(
          (await session.request(start_request)).outcome,
        );

        _expect_same_resolution(started, historical_start);

        final state = await session.request(const StateReadRequest());

        expect(state.state.workflows.current_workflow, isNull);
      },
    );

    test('business rejections remain typed application responses', () async {
      final fixture = await create_session();
      final session = fixture.session;

      final started = _completed(
        (await session.request(
          WorkflowStartRequest(
            target_id: target_id,
            root: fixture.root,
            idempotency_key: 'start-001',
          ),
        )).outcome,
      );

      final competing_start = WorkflowStartRequest(
        target_id: target_id,
        root: fixture.root,
        idempotency_key: 'start-002',
      );

      final conflict = _rejected(
        (await session.request(competing_start)).outcome,
        WorkflowRejectionCode.ownership_conflict,
      );

      _rejected(
        (await session.request(
          WorkflowStopRequest(
            workflow_id: 'different-workflow',
            idempotency_key: 'stale-stop',
          ),
        )).outcome,
        WorkflowRejectionCode.workflow_id_mismatch,
      );

      final queried = await session.request(
        WorkflowSubmissionRequest(receipt: conflict.receipt),
      );

      _expect_same_resolution(conflict, queried.resolution!);

      final workflow_id = started.committed_outcome!.workflow_id;

      _completed(
        (await session.request(
          WorkflowStopRequest(
            workflow_id: workflow_id,
            idempotency_key: 'stop-001',
          ),
        )).outcome,
      );

      final retried = _rejected(
        (await session.request(competing_start)).outcome,
        WorkflowRejectionCode.ownership_conflict,
      );

      _expect_same_resolution(conflict, retried);

      final state = await session.request(const StateReadRequest());

      expect(state.state.workflows.current_workflow, isNull);
    });

    test(
      'explicit Stop without an active workflow is durably rejected',
      () async {
        final fixture = await create_session();

        final response = await fixture.session.request(
          WorkflowStopRequest(
            workflow_id: 'missing-workflow',
            idempotency_key: 'stop-001',
          ),
        );

        final rejected = _rejected(
          response.outcome,
          WorkflowRejectionCode.workflow_not_active,
        );

        expect(await fixture.composition.database_file.exists(), isTrue);

        final queried = await fixture.session.request(
          WorkflowSubmissionRequest(receipt: rejected.receipt),
        );

        _expect_same_resolution(rejected, queried.resolution!);
      },
    );

    test(
      'conflicting operation-key reuse remains an application outcome',
      () async {
        final fixture = await create_session();
        final session = fixture.session;

        final original = _completed(
          (await session.request(
            WorkflowStartRequest(
              target_id: target_id,
              root: fixture.root,
              idempotency_key: 'shared-key',
            ),
          )).outcome,
        );

        final response = await session.request(
          WorkflowStartRequest(
            target_id: target_id,
            root: TargetPath(
              '${fixture.root.value}${Platform.pathSeparator}different',
            ),
            idempotency_key: 'shared-key',
          ),
        );

        expect(response.outcome, isA<WorkflowOperationIdempotencyConflict>());

        final different_command = await session.request(
          WorkflowStopRequest(
            workflow_id: original.committed_outcome!.workflow_id,
            idempotency_key: 'shared-key',
          ),
        );

        expect(
          different_command.outcome,
          isA<WorkflowOperationIdempotencyConflict>(),
        );

        final state = await session.request(const StateReadRequest());

        expect(
          state.state.workflows.current_workflow!.identity.workflow_id,
          original.committed_outcome!.workflow_id,
        );
      },
    );

    test(
      'submission lookup requires the original correlation identity',
      () async {
        final fixture = await create_session();

        final started = _completed(
          (await fixture.session.request(
            WorkflowStartRequest(
              target_id: target_id,
              root: fixture.root,
              idempotency_key: 'start-001',
            ),
          )).outcome,
        );

        final response = await fixture.session.request(
          WorkflowSubmissionRequest(
            receipt: EventSubmissionReceipt(
              event_id: started.receipt.event_id,
              correlation_id: 'incorrect-correlation',
            ),
          ),
        );

        expect(response.resolution, isNull);

        final authorized = await fixture.session.request(
          WorkflowSubmissionRequest(receipt: started.receipt),
        );

        _expect_same_resolution(started, authorized.resolution!);
      },
    );
  });

  group('trusted request boundaries', () {
    test('rejects an unsupported target before durable acceptance', () async {
      final fixture = await create_session();

      await expectLater(
        fixture.session.request(
          WorkflowStartRequest(
            target_id: 'unsupported-target',
            root: fixture.root,
            idempotency_key: 'start-001',
          ),
        ),
        throwsA(_handler_failure()),
      );

      expect(await fixture.composition.database_file.exists(), isFalse);

      // The invalid request must not reserve its operation key
      // or terminate the authenticated communication session.
      final valid = await fixture.session.request(
        WorkflowStartRequest(
          target_id: target_id,
          root: fixture.root,
          idempotency_key: 'start-001',
        ),
      );

      _completed(valid.outcome);
    });

    test('rejects a relative root before durable acceptance', () async {
      final fixture = await create_session();

      await expectLater(
        fixture.session.request(
          WorkflowStartRequest(
            target_id: target_id,
            root: TargetPath('relative-directory'),
            idempotency_key: 'start-001',
          ),
        ),
        throwsA(_handler_failure()),
      );

      expect(await fixture.composition.database_file.exists(), isFalse);

      final state = await fixture.session.request(const StateReadRequest());

      expect(state.state.workflows.current_workflow, isNull);
    });

    test('all handlers reject inconsistent authenticated ownership', () async {
      final fixture = await create_session(
        server_peer_override: 'different-owner',
      );

      final requests = <Request<Response>>[
        const StateReadRequest(),
        WorkflowStartRequest(
          target_id: target_id,
          root: fixture.root,
          idempotency_key: 'start-001',
        ),
        WorkflowStopRequest(
          workflow_id: 'workflow-001',
          idempotency_key: 'stop-001',
        ),
        WorkflowSubmissionRequest(
          receipt: EventSubmissionReceipt(
            event_id: 'event-001',
            correlation_id: 'correlation-001',
          ),
        ),
      ];

      for (final request in requests) {
        await expectLater(
          fixture.session.request(request),
          throwsA(_handler_failure()),
        );
      }

      expect(await fixture.composition.database_file.exists(), isFalse);
    });
  });
}

/// Extracts a successfully committed application [outcome].
WorkflowSubmissionResolution _completed(WorkflowOperationOutcome outcome) {
  expect(outcome, isA<WorkflowOperationResolved>());

  final resolution = (outcome as WorkflowOperationResolved).resolution;

  expect(resolution.state, WorkflowSubmissionState.completed);
  expect(resolution.committed_outcome, isNotNull);

  return resolution;
}

/// Extracts a durable rejection matching the expected [code].
WorkflowSubmissionResolution _rejected(
  WorkflowOperationOutcome outcome,
  WorkflowRejectionCode code,
) {
  expect(outcome, isA<WorkflowOperationResolved>());

  final resolution = (outcome as WorkflowOperationResolved).resolution;

  expect(resolution.state, WorkflowSubmissionState.rejected);
  expect(resolution.rejection_code, code);
  expect(resolution.rejected_at_unix_ms, isNotNull);

  return resolution;
}

/// Verifies that [actual] preserves the durable [expected] resolution.
///
/// Compares application identities independently of communication
/// request identifiers or response object identity.
void _expect_same_resolution(
  WorkflowSubmissionResolution expected,
  WorkflowSubmissionResolution actual,
) {
  expect(actual.receipt.event_id, expected.receipt.event_id);

  expect(actual.receipt.correlation_id, expected.receipt.correlation_id);

  expect(actual.state, expected.state);

  expect(
    actual.committed_outcome?.workflow_id,
    expected.committed_outcome?.workflow_id,
  );

  expect(
    actual.committed_outcome?.event_type,
    expected.committed_outcome?.event_type,
  );

  expect(
    actual.committed_outcome?.version,
    expected.committed_outcome?.version,
  );

  expect(
    actual.committed_outcome?.sequence,
    expected.committed_outcome?.sequence,
  );

  expect(actual.rejection_code, expected.rejection_code);
  expect(actual.rejected_at_unix_ms, expected.rejected_at_unix_ms);
  expect(actual.quarantine_code, expected.quarantine_code);
  expect(actual.quarantined_at_unix_ms, expected.quarantined_at_unix_ms);
}

/// Matches sanitized remote handler failures.
Matcher _handler_failure() {
  return isA<MessageSessionException>().having(
    (error) => error.code,
    'code',
    MessageSessionErrorCode.handler_failed,
  );
}

/// Supplies deterministic authenticated host ownership.
final class _IdentityProvider implements HostIdentityProvider {
  /// Binds the fixture to [os_user_id].
  const _IdentityProvider(this.os_user_id);

  /// Trusted operating-system owner.
  final String os_user_id;

  /// Returns the configured authenticated identity.
  @override
  Future<String> resolve() async => os_user_id;
}
