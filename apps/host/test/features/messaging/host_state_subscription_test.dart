import 'dart:async';
import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../../support/loopback_host_transport.dart';
import '../../support/unused_target_inspector.dart';

/// Verifies authenticated state subscription delivery through
/// an authoritative host and real SQLite persistence.
void main() {
  test('independent sessions observe committed Start and Stop', () async {
    final fixture = await _HostFixture.create();

    final first_probe = _DeliveryProbe();
    final second_probe = _DeliveryProbe();

    final first = await fixture.connect(deliver: first_probe.deliver);
    final second = await fixture.connect(deliver: second_probe.deliver);

    const subscription_id = 'state-subscription';

    final first_accepted = await first.request(
      StateSubscribeRequest(subscription_id: subscription_id),
    );

    final second_accepted = await second.request(
      StateSubscribeRequest(subscription_id: subscription_id),
    );

    final first_initial = await first_probe.at(0);
    final second_initial = await second_probe.at(0);

    expect(first_accepted.generation, second_accepted.generation);
    expect(first_initial.subscription_id, subscription_id);
    expect(second_initial.subscription_id, subscription_id);

    expect(first_initial.publication.generation, first_accepted.generation);

    expect(second_initial.publication.generation, second_accepted.generation);

    expect(first_initial.publication.revision, 1);
    expect(second_initial.publication.revision, 1);

    expect(first_initial.publication.state.workflows.current_workflow, isNull);

    expect(second_initial.publication.state.workflows.current_workflow, isNull);

    // Read-only subscriptions must not initialize absent persistence.
    expect(await fixture.database_file.exists(), isFalse);

    final started = await fixture.start_workflow(first);

    final first_active = await first_probe.at(1);
    final second_active = await second_probe.at(1);

    for (final delivery in [first_active, second_active]) {
      expect(delivery.publication.revision, 2);
      expect(
        delivery
            .publication
            .state
            .workflows
            .current_workflow
            ?.identity
            .workflow_id,
        started.workflow_id,
      );
      expect(delivery.publication.state.workflows.current_workflow?.version, 1);
    }

    final cancelled = await second.request(
      StateUnsubscribeRequest(subscription_id: subscription_id),
    );

    expect(cancelled.subscription_id, subscription_id);

    await fixture.stop_workflow(first, workflow_id: started.workflow_id);

    final first_ended = await first_probe.at(2);

    expect(first_ended.publication.revision, 3);
    expect(first_ended.publication.state.workflows.current_workflow, isNull);

    // Unsubscription preserves ordinary application requests.
    final read = await second.request(const StateReadRequest());

    expect(read.state.workflows.current_workflow, isNull);
    expect(second_probe.values, hasLength(2));

    final replacement = await second.request(
      StateSubscribeRequest(subscription_id: 'replacement-subscription'),
    );

    final replacement_initial = await second_probe.at(2);

    expect(replacement.generation, second_accepted.generation);
    expect(replacement_initial.subscription_id, 'replacement-subscription');
    expect(replacement_initial.publication.revision, 3);
    expect(
      replacement_initial.publication.state.workflows.current_workflow,
      isNull,
    );
  });

  test('slow delivery does not block another subscriber or commands', () async {
    final fixture = await _HostFixture.create();

    final release_slow = Completer<void>();

    final slow_probe = _DeliveryProbe(
      first_acknowledgment: release_slow.future,
    );

    final fast_probe = _DeliveryProbe();

    final slow = await fixture.connect(deliver: slow_probe.deliver);
    final fast = await fixture.connect(deliver: fast_probe.deliver);

    try {
      final acceptance = slow.request(
        StateSubscribeRequest(subscription_id: 'slow'),
      );

      final initial = await slow_probe.at(0);

      // Subscription acceptance must not wait for acknowledgment
      // of the independently executing initial delivery.
      final accepted = await acceptance.timeout(_HostFixture.timeout);

      expect(accepted.subscription_id, 'slow');
      expect(initial.publication.revision, 1);
      expect(release_slow.isCompleted, isFalse);

      await fast.request(StateSubscribeRequest(subscription_id: 'fast'));

      expect((await fast_probe.at(0)).publication.revision, 1);

      final started = await fixture.start_workflow(fast);

      final active = await fast_probe.at(1);

      expect(active.publication.revision, 2);
      expect(
        active
            .publication
            .state
            .workflows
            .current_workflow
            ?.identity
            .workflow_id,
        started.workflow_id,
      );

      await fixture.stop_workflow(fast, workflow_id: started.workflow_id);

      final ended = await fast_probe.at(2);

      expect(ended.publication.revision, 3);
      expect(ended.publication.state.workflows.current_workflow, isNull);

      expect(slow_probe.values, hasLength(1));

      release_slow.complete();

      final reconciled = await slow_probe.at(1);

      expect(reconciled.publication.revision, 3);
      expect(reconciled.publication.state.workflows.current_workflow, isNull);

      expect(slow_probe.values.map((value) => value.publication.revision), [
        1,
        3,
      ]);
    } finally {
      if (!release_slow.isCompleted) {
        release_slow.complete();
      }
    }
  });

  test('rejects subscription access from an unauthorized peer', () async {
    final fixture = await _HostFixture.create(
      server_peer_override: 'untrusted-owner',
    );

    final probe = _DeliveryProbe();
    final session = await fixture.connect(deliver: probe.deliver);

    await expectLater(
      session.request(StateSubscribeRequest(subscription_id: 'unauthorized')),
      throwsA(
        isA<MessageSessionException>().having(
          (error) => error.code,
          'code',
          MessageSessionErrorCode.handler_failed,
        ),
      ),
    );

    expect(probe.values, isEmpty);
    expect(await fixture.database_file.exists(), isFalse);
  });

  test('invalid acknowledgment terminates only its own session', () async {
    final fixture = await _HostFixture.create();

    final healthy_probe = _DeliveryProbe();

    final healthy = await fixture.connect(deliver: healthy_probe.deliver);

    await healthy.request(StateSubscribeRequest(subscription_id: 'healthy'));

    await healthy_probe.at(0);

    final invalid = await fixture.connect(
      deliver: (request) async {
        return StateDeliveryResponse(
          subscription_id: request.subscription_id,
          generation: request.publication.generation,
          revision: request.publication.revision + 1,
        );
      },
    );

    // Delivery failure may terminate communication before the
    // independently executing acceptance response reaches the client.
    final acceptance = invalid.request(
      StateSubscribeRequest(subscription_id: 'invalid'),
    );

    acceptance.ignore();

    await invalid.done.timeout(_HostFixture.timeout);

    await expectLater(
      invalid.request(const StateReadRequest()),
      throwsA(isA<MessageSessionException>()),
    );

    final started = await fixture.start_workflow(healthy);

    final updated = await healthy_probe.at(1);

    expect(updated.publication.revision, 2);
    expect(
      updated
          .publication
          .state
          .workflows
          .current_workflow
          ?.identity
          .workflow_id,
      started.workflow_id,
    );
  });

  test('host shutdown drains an outstanding delivery', () async {
    final fixture = await _HostFixture.create();

    final release = Completer<void>();

    final probe = _DeliveryProbe(first_acknowledgment: release.future);

    final session = await fixture.connect(deliver: probe.deliver);

    try {
      await session.request(StateSubscribeRequest(subscription_id: 'shutdown'));

      await probe.at(0);

      expect(release.isCompleted, isFalse);

      // Closing host sessions must settle the host-side delivery
      // without waiting for the remote application handler.
      await fixture.stop();

      expect(fixture.host.resources_released, isTrue);
      expect(release.isCompleted, isFalse);

      await session.done.timeout(_HostFixture.timeout);

      expect(await fixture.database_file.exists(), isFalse);
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
    }
  });

  test('authoritative observation failure terminates the host', () async {
    final fixture = await _HostFixture.create();

    final probe = _DeliveryProbe();
    final session = await fixture.connect(deliver: probe.deliver);

    await session.request(
      StateSubscribeRequest(subscription_id: 'source-failure'),
    );

    await probe.at(0);

    fixture.expect_observation_failure = true;

    final failure = expectLater(
      fixture.running.timeout(_HostFixture.timeout),
      throwsStateError,
    );

    // The production persistence context owns this notification
    // channel. Closing it invalidates authoritative observation.
    final channel =
        fixture.persistence.workflow_commit_subscriber
            as LocalWorkflowCommitChannel;

    await channel.close();

    await failure;
    await session.done.timeout(_HostFixture.timeout);

    expect(fixture.host.resources_released, isTrue);

    // Source failure remains distinct from verified workflow absence.
    expect(probe.values, hasLength(1));
    expect(await fixture.database_file.exists(), isFalse);
  });
}

/// Produces the exact acknowledgment of an admitted [request].
StateDeliveryResponse _acknowledge(StateDeliveryRequest request) {
  return StateDeliveryResponse(
    subscription_id: request.subscription_id,
    generation: request.publication.generation,
    revision: request.publication.revision,
  );
}

/// Receives state deliveries over a real communication session.
final class _DeliveryProbe {
  /// Creates a probe with an optional initial acknowledgment barrier.
  ///
  /// [first_acknowledgment] delays only the first delivery response.
  _DeliveryProbe({this.first_acknowledgment});

  /// Optional barrier retaining the first admitted delivery.
  final Future<void>? first_acknowledgment;

  /// Admitted state deliveries in receiving order.
  final List<StateDeliveryRequest> values = [];

  /// Notification of the next admitted delivery.
  Completer<void> _changed = Completer<void>();

  /// Records [request] and returns its exact acknowledgment.
  ///
  /// The first acknowledgment may be suspended by the supplied barrier.
  Future<StateDeliveryResponse> deliver(StateDeliveryRequest request) async {
    values.add(request);

    final changed = _changed;
    _changed = Completer<void>();
    changed.complete();

    if (values.length == 1) {
      await first_acknowledgment;
    }

    return _acknowledge(request);
  }

  /// Returns the admitted delivery at zero-based [index].
  ///
  /// Throws [TimeoutException] when the delivery does not arrive
  /// within the integration test deadline.
  Future<StateDeliveryRequest> at(int index) async {
    while (values.length <= index) {
      await _changed.future.timeout(_HostFixture.timeout);
    }

    return values[index];
  }
}

/// Owns one isolated host integration-test lifecycle.
///
/// Uses real application execution, publication, communication
/// sessions and SQLite persistence.
final class _HostFixture {
  /// Retains the resources established by [create].
  _HostFixture({
    required this.directory,
    required this.database_file,
    required this.persistence,
    required this.transport,
    required this.host,
    required this.running,
    required Completer<void> shutdown,
  }) : _shutdown = shutdown;

  /// Deadline for controlled integration operations.
  static const timeout = Duration(seconds: 10);

  /// Trusted host and client identity.
  static const owner = 'trusted-owner';

  /// Isolated directory containing host persistence.
  final Directory directory;

  /// SQLite database owned by the test host.
  final File database_file;

  /// Authoritative host persistence context.
  final RudraSqlitePersistence persistence;

  /// Transport shared by independent host and client connections.
  final LoopbackHostTransport transport;

  /// Authoritative portable host runtime.
  final RudraHost host;

  /// Host execution and disposal result.
  final Future<void> running;

  /// External host termination notification.
  final Completer<void> _shutdown;

  /// Whether the test expects authoritative observation to fail.
  bool expect_observation_failure = false;

  /// Creates an executing host with isolated persistence.
  ///
  /// [server_peer_override] optionally supplies intentionally
  /// inconsistent authentication evidence for handler tests.
  ///
  /// Returns after authoritative initial publication is available.
  /// Startup and readiness failures propagate.
  static Future<_HostFixture> create({String? server_peer_override}) async {
    final directory = await Directory.systemTemp.createTemp(
      'rudra-host-state-subscription-',
    );

    final database_file = File('${directory.path}/rudra.db');
    final runtime = WorkflowRuntime.standard();

    final persistence = RudraSqlitePersistence(
      database_file: database_file,
      scope_id: 'test-scope',
      runtime: runtime,
    );

    final application = WorkflowApplication(
      runtime: runtime,
      persistence: persistence,
      identity_provider: _IdentityProvider(),
      os_user_id: owner,
    );

    final transport = LoopbackHostTransport(
      server_peer_override: server_peer_override,
    );

    final host = RudraHost(
      application: application,
      validate_start: (target_id, root) {},
      filesystem_application: FilesystemApplication(
        target_id: 'local-macos',
        inspector: const UnusedTargetInspector(),
      ),
      communication_factory: ({required codecs, required handlers}) {
        return Communication(
          transport: transport,
          codecs: codecs,
          handlers: handlers,
          options: const MessageSessionOptions(request_timeout: timeout),
        );
      },
    );

    final shutdown = Completer<void>();
    final ready = Completer<void>();

    final running = host.run(
      scope_directory: directory.path,
      shutdown: shutdown.future,
      on_ready: (_) {
        ready.complete();
      },
    );

    running.ignore();

    final fixture = _HostFixture(
      directory: directory,
      database_file: database_file,
      persistence: persistence,
      transport: transport,
      host: host,
      running: running,
      shutdown: shutdown,
    );

    addTearDown(fixture.dispose);

    await Future.any<void>([
      ready.future,
      running.then<void>((_) {
        throw StateError('Host terminated before readiness.');
      }),
    ]).timeout(timeout);

    return fixture;
  }

  /// Establishes an independent authenticated client connection.
  ///
  /// [deliver] supplies the client's registered state delivery handler.
  ///
  /// Returns the connected message session. The test framework closes
  /// its communication resources during cleanup.
  Future<MessageSession> connect({
    required Future<StateDeliveryResponse> Function(StateDeliveryRequest)
    deliver,
  }) async {
    final handlers = RequestHandlerRegistry();

    handlers.register<StateDeliveryResponse, StateDeliveryRequest>((
      request,
      session,
    ) {
      return deliver(request);
    });

    final communication = Communication(
      transport: transport,
      codecs: create_application_message_codecs(),
      handlers: handlers,
      options: const MessageSessionOptions(request_timeout: timeout),
    );

    final session = await communication.connect(
      scope_directory: directory.path,
      os_user_id: owner,
    );

    addTearDown(() async {
      try {
        await session.close();
      } finally {
        await communication.done.timeout(timeout);
      }
    });

    return session;
  }

  /// Establishes a workflow through authenticated [session].
  ///
  /// Returns the original committed establishment reference.
  /// Requires successful durable command completion.
  Future<WorkflowCommittedOutcome> start_workflow(
    MessageSession session,
  ) async {
    final response = await session.request(
      WorkflowStartRequest(
        target_id: 'local-macos',
        root: TargetPath(directory.path),
        idempotency_key: 'start-workflow',
      ),
    );

    return _require_committed(response.outcome);
  }

  /// Stops [workflow_id] through authenticated [session].
  ///
  /// Returns the original committed terminal outcome.
  Future<WorkflowCommittedOutcome> stop_workflow(
    MessageSession session, {
    required String workflow_id,
  }) async {
    final response = await session.request(
      WorkflowStopRequest(
        workflow_id: workflow_id,
        idempotency_key: 'stop-workflow',
      ),
    );

    return _require_committed(response.outcome);
  }

  /// Terminates the host and awaits its resource disposal.
  ///
  /// Repeated invocations retain the original execution result.
  Future<void> stop() async {
    if (!_shutdown.isCompleted) {
      _shutdown.complete();
    }

    await running.timeout(timeout);
  }

  /// Releases host resources, persistence and isolated test storage.
  ///
  /// Persistence remains available until host execution has drained.
  Future<void> dispose() async {
    try {
      if (!_shutdown.isCompleted) {
        _shutdown.complete();
      }

      if (expect_observation_failure) {
        await expectLater(running.timeout(timeout), throwsStateError);
      } else {
        await running.timeout(timeout);
      }
    } finally {
      try {
        await persistence.close();
      } finally {
        await directory.delete(recursive: true);
      }
    }
  }
}

/// Extracts the committed reference from a successful [outcome].
WorkflowCommittedOutcome _require_committed(WorkflowOperationOutcome outcome) {
  expect(outcome, isA<WorkflowOperationResolved>());

  final resolution = (outcome as WorkflowOperationResolved).resolution;

  expect(resolution.state, WorkflowSubmissionState.completed);

  return resolution.committed_outcome!;
}

/// Supplies deterministic workflow identities for host integration tests.
final class _IdentityProvider implements WorkflowIdentityProvider {
  /// Last allocated workflow ordinal.
  int _sequence = 0;

  /// Proposes a distinct owner-bound identity for [submission].
  ///
  /// Preserves the requested target and root.
  /// Throws [StateError] for unsupported command types.
  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final command = submission.command;

    if (command is! WorkflowStartEvent) {
      throw StateError('Only Start establishes workflow identity.');
    }

    return WorkflowIdentity(
      workflow_id: 'workflow-${++_sequence}',
      os_user_id: _HostFixture.owner,
      target_id: command.target_id,
      root: command.root,
    );
  }
}
