import 'dart:async';
import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../../support/controlled_workflow_persistence.dart';
import '../../support/loopback_host_transport.dart';
import '../../support/unused_target_inspector.dart';

/// Verifies independent clients competing for one authoritative host.
///
/// Uses real communication sessions, application handlers, workflow
/// processing and SQLite persistence. Test-only barriers control
/// execution timing without replacing authoritative operations.
void main() {
  late _HostFixture fixture;

  setUp(() async {
    fixture = await _HostFixture.create();

    addTearDown(fixture.dispose);

    await fixture.start_host();
  });

  group('competing Start requests', () {
    test(
      'distinct Starts produce one establishment and one rejection',
      () async {
        final first = await fixture.connect();
        final second = await fixture.connect();

        final results = await fixture.overlap(
          first: () => fixture.start(first, 'start-001'),
          second: (_) => fixture.start(
            second,
            'start-002',
            root: fixture.replacement_root,
          ),
          second_key: 'start-002',
          observer: second,
        );

        final established = _completed(results.first);

        final rejected = _rejected(
          results.last,
          WorkflowRejectionCode.ownership_conflict,
        );

        expect(rejected.receipt.event_id, isNot(established.receipt.event_id));

        final workflow_id = established.committed_outcome!.workflow_id;

        final first_state = await fixture.current(first);
        final second_state = await fixture.current(second);

        expect(first_state!.identity.workflow_id, workflow_id);
        expect(second_state!.identity.workflow_id, workflow_id);

        expect(first_state.identity.root.value, fixture.root.value);
        expect(second_state.identity.root.value, fixture.root.value);

        expect(first_state.version, 1);
        expect(second_state.version, 1);

        await fixture.verify_evidence(
          resolutions: [established, rejected],
          active_workflow_id: workflow_id,
        );
      },
    );

    test('identical Starts recover one durable establishment', () async {
      final first = await fixture.connect();
      final second = await fixture.connect();

      final results = await fixture.overlap(
        first: () => fixture.start(first, 'shared-start'),
        second: (_) => fixture.start(second, 'shared-start'),
        second_key: 'shared-start',
        second_occurrence: 2,
        observer: second,
      );

      final established = _completed(results.first);
      final retried = _completed(results.last);

      _expect_same_resolution(established, retried);

      final workflow_id = established.committed_outcome!.workflow_id;

      expect(
        (await fixture.current(second))!.identity.workflow_id,
        workflow_id,
      );

      await fixture.verify_evidence(
        resolutions: [established],
        active_workflow_id: workflow_id,
      );
    });

    test('conflicting key reuse cannot replace a pending Start', () async {
      final first = await fixture.connect();
      final second = await fixture.connect();

      final barrier = fixture.control.hold_next_commit();

      final original = fixture.start(first, 'shared-start');

      original.ignore();

      try {
        final plan = await barrier.entered.timeout(
          _HostFixture.operation_timeout,
        );

        final conflict = await fixture.start(
          second,
          'shared-start',
          root: fixture.replacement_root,
        );

        expect(conflict, isA<WorkflowOperationIdempotencyConflict>());

        final pending = await fixture.status(second, plan.submission.receipt);

        expect(pending!.state, WorkflowSubmissionState.pending);
        expect(await fixture.current(second), isNull);
      } finally {
        barrier.release();
      }

      final established = _completed(await original);

      final current = await fixture.current(second);

      expect(current!.identity.root.value, fixture.root.value);

      await fixture.verify_evidence(
        resolutions: [established],
        active_workflow_id: established.committed_outcome!.workflow_id,
      );
    });
  });

  group('competing Stop requests', () {
    test('distinct Stops produce one terminal commitment', () async {
      final first = await fixture.connect();
      final second = await fixture.connect();

      final established = _completed(await fixture.start(first, 'start-001'));

      final workflow_id = established.committed_outcome!.workflow_id;

      final results = await fixture.overlap(
        first: () => fixture.stop(first, 'stop-001', workflow_id),
        second: (_) => fixture.stop(second, 'stop-002', workflow_id),
        second_key: 'stop-002',
        observer: second,
      );

      final ended = _completed(results.first);

      final rejected = _rejected(
        results.last,
        WorkflowRejectionCode.workflow_not_active,
      );

      expect(ended.committed_outcome!.workflow_id, workflow_id);
      expect(ended.committed_outcome!.version, 2);

      expect(rejected.receipt.event_id, isNot(ended.receipt.event_id));

      expect(await fixture.current(first), isNull);
      expect(await fixture.current(second), isNull);

      await fixture.verify_evidence(
        resolutions: [established, ended, rejected],
      );
    });

    test('identical Stops recover one durable terminal outcome', () async {
      final first = await fixture.connect();
      final second = await fixture.connect();

      final established = _completed(await fixture.start(first, 'start-001'));

      final workflow_id = established.committed_outcome!.workflow_id;

      final results = await fixture.overlap(
        first: () => fixture.stop(first, 'shared-stop', workflow_id),
        second: (_) => fixture.stop(second, 'shared-stop', workflow_id),
        second_key: 'shared-stop',
        second_occurrence: 2,
        observer: second,
      );

      final ended = _completed(results.first);
      final retried = _completed(results.last);

      _expect_same_resolution(ended, retried);

      expect(await fixture.current(first), isNull);
      expect(await fixture.current(second), isNull);

      await fixture.verify_evidence(resolutions: [established, ended]);
    });
  });

  group('mixed workflow requests', () {
    test('an accepted Stop follows an outstanding Start', () async {
      final first = await fixture.connect();
      final second = await fixture.connect();

      final results = await fixture.overlap(
        first: () => fixture.start(first, 'start-001'),
        second: (plan) => fixture.stop(
          second,
          'stop-001',
          plan.resulting_state.identity.workflow_id,
        ),
        second_key: 'stop-001',
        observer: second,
      );

      final established = _completed(results.first);
      final ended = _completed(results.last);

      expect(
        ended.committed_outcome!.workflow_id,
        established.committed_outcome!.workflow_id,
      );

      expect(established.committed_outcome!.version, 1);
      expect(ended.committed_outcome!.version, 2);

      expect(await fixture.current(first), isNull);
      expect(await fixture.current(second), isNull);

      await fixture.verify_evidence(resolutions: [established, ended]);
    });

    test('a replacement Start follows an outstanding Stop', () async {
      final first = await fixture.connect();
      final second = await fixture.connect();

      final original = _completed(await fixture.start(first, 'start-001'));

      final original_id = original.committed_outcome!.workflow_id;

      final results = await fixture.overlap(
        first: () => fixture.stop(first, 'stop-001', original_id),
        second: (_) =>
            fixture.start(second, 'start-002', root: fixture.replacement_root),
        second_key: 'start-002',
        observer: second,
      );

      final ended = _completed(results.first);
      final replacement = _completed(results.last);

      final replacement_id = replacement.committed_outcome!.workflow_id;

      expect(replacement_id, isNot(original_id));
      expect(replacement.committed_outcome!.version, 1);

      final historical_retry = _completed(
        await fixture.stop(first, 'stop-001', original_id),
      );

      _expect_same_resolution(ended, historical_retry);

      final first_state = await fixture.current(first);
      final second_state = await fixture.current(second);

      expect(first_state!.identity.workflow_id, replacement_id);
      expect(second_state!.identity.workflow_id, replacement_id);

      expect(second_state.identity.root.value, fixture.replacement_root.value);

      await fixture.verify_evidence(
        resolutions: [original, ended, replacement],
        active_workflow_id: replacement_id,
      );
    });
  });

  group('interrupted communication', () {
    test('disconnecting a client does not cancel admitted execution', () async {
      final first = await fixture.connect();
      final second = await fixture.connect();

      final barrier = fixture.control.hold_next_commit();

      final interrupted = fixture.start(first, 'start-001');

      interrupted.ignore();

      late Future<WorkflowOperationOutcome> retry;
      late EventSubmissionReceipt receipt;

      try {
        final plan = await barrier.entered.timeout(
          _HostFixture.operation_timeout,
        );

        receipt = plan.submission.receipt;

        final failure = expectLater(interrupted, throwsA(_session_closed()));

        // The original client's connection disappears while the
        // admitted application handler is still awaiting commitment.
        await first.close();
        await failure;

        final pending = await fixture.status(second, receipt);

        expect(pending!.state, WorkflowSubmissionState.pending);

        retry = fixture.start(second, 'start-001');

        retry.ignore();

        final accepted = await fixture.control
            .accepted('start-001', occurrence: 2)
            .timeout(_HostFixture.operation_timeout);

        _expect_same_receipt(receipt, accepted);

        // The original operation remains pending until the barrier
        // releases its actual SQLite commitment.
        final outstanding = await fixture.status(second, receipt);

        expect(outstanding!.state, WorkflowSubmissionState.pending);
      } finally {
        barrier.release();
      }

      final recovered = _completed(await retry);

      _expect_same_receipt(receipt, recovered.receipt);

      await fixture.verify_evidence(
        resolutions: [recovered],
        active_workflow_id: recovered.committed_outcome!.workflow_id,
      );
    });

    test('lost response is recoverable after restarting the host', () async {
      final barrier = LoopbackResponseBarrier();

      final first = await fixture.connect(response_barrier: barrier);

      final observer = await fixture.connect();

      final interrupted = fixture.start(first, 'start-001');

      interrupted.ignore();

      late WorkflowSubmissionResolution original;

      try {
        // This boundary is reached only after the handler has returned
        // and communication has prepared its outbound response.
        await barrier.entered.timeout(_HostFixture.operation_timeout);

        final receipt = await fixture.control
            .accepted('start-001')
            .timeout(_HostFixture.operation_timeout);

        final committed = await fixture.status(observer, receipt);

        expect(committed!.state, WorkflowSubmissionState.completed);

        original = committed;

        final failure = expectLater(interrupted, throwsA(_session_closed()));

        // Lose the original response without undoing commitment.
        await first.close();
        await failure;
      } finally {
        barrier.release();
      }

      await fixture.stop_host();
      await fixture.start_host();

      final reconnected = await fixture.connect();

      final queried = await fixture.status(reconnected, original.receipt);

      _expect_same_resolution(original, queried!);

      final retry = _completed(await fixture.start(reconnected, 'start-001'));

      _expect_same_resolution(original, retry);

      final restored = await fixture.current(reconnected);

      expect(
        restored!.identity.workflow_id,
        original.committed_outcome!.workflow_id,
      );

      expect(restored.version, 1);

      await fixture.verify_evidence(
        resolutions: [original],
        active_workflow_id: original.committed_outcome!.workflow_id,
      );
    });
  });
}

/// Extracts the committed resolution from [outcome].
WorkflowSubmissionResolution _completed(WorkflowOperationOutcome outcome) {
  expect(outcome, isA<WorkflowOperationResolved>());

  final resolution = (outcome as WorkflowOperationResolved).resolution;

  expect(resolution.state, WorkflowSubmissionState.completed);
  expect(resolution.committed_outcome, isNotNull);

  return resolution;
}

/// Extracts a durable rejection matching [code] from [outcome].
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

/// Verifies that [actual] preserves the original [expected] receipt.
void _expect_same_receipt(
  EventSubmissionReceipt expected,
  EventSubmissionReceipt actual,
) {
  expect(actual.event_id, expected.event_id);
  expect(actual.correlation_id, expected.correlation_id);
}

/// Verifies that [actual] preserves the durable [expected] resolution.
void _expect_same_resolution(
  WorkflowSubmissionResolution expected,
  WorkflowSubmissionResolution actual,
) {
  _expect_same_receipt(expected.receipt, actual.receipt);

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
  expect(actual.quarantine_diagnostic, expected.quarantine_diagnostic);
  expect(actual.quarantined_at_unix_ms, expected.quarantined_at_unix_ms);
}

/// Matches termination of an outstanding client request.
Matcher _session_closed() {
  return isA<MessageSessionException>().having(
    (error) => error.code,
    'code',
    MessageSessionErrorCode.session_closed,
  );
}

/// Owns an isolated host and its independent communication clients.
///
/// Reopening the host constructs a new application, communication
/// subsystem and persistence context over the original SQLite file.
final class _HostFixture {
  /// Creates a fixture owning [directory].
  _HostFixture(this.directory);

  /// Creates an isolated temporary host directory.
  ///
  /// The caller must eventually invoke [dispose].
  static Future<_HostFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'rudra-competing-clients-',
    );

    return _HostFixture(directory);
  }

  /// Deadline for controlled integration operations.
  static const operation_timeout = Duration(seconds: 10);

  /// Trusted authenticated operating-system owner.
  static const owner = 'test-owner';

  /// Configured filesystem target.
  static const target_id = 'test-target';

  /// Trusted durable submission namespace.
  static const scope_id = 'test-host-scope';

  /// Temporary directory exclusively owned by this fixture.
  final Directory directory;

  /// SQLite database retained across host lifetimes.
  late final File database_file = File('${directory.path}/rudra.db');

  /// Shared immutable workflow configuration.
  final WorkflowRuntime runtime = WorkflowRuntime.standard();

  /// Deterministic trusted identity provider.
  final _IdentityProvider identities = _IdentityProvider();

  /// Connected clients retained for ordered resource disposal.
  final List<_Client> _clients = [];

  /// Current authoritative SQLite persistence owner.
  RudraSqlitePersistence? _persistence;

  /// Current host execution result.
  Future<void>? _running;

  /// Termination notification for the current host.
  late Completer<void> _shutdown;

  /// Controlled persistence boundary for the current host.
  late ControlledWorkflowPersistence control;

  /// Independent transport belonging to the current host lifetime.
  late LoopbackHostTransport transport;

  /// Original target-native root used by Start requests.
  TargetPath get root => TargetPath(directory.absolute.path);

  /// Distinct target-native root used by competing requests.
  TargetPath get replacement_root => TargetPath(
    '${directory.absolute.path}${Platform.pathSeparator}replacement',
  );

  /// Constructs and starts a new authoritative host.
  ///
  /// Returns after application restoration and communication readiness.
  ///
  /// Throws [StateError] if another persistence lifetime remains open.
  Future<void> start_host() async {
    if (_persistence != null) {
      throw StateError('Fixture host is already running.');
    }

    final persistence = RudraSqlitePersistence(
      database_file: database_file,
      scope_id: scope_id,
      runtime: runtime,
    );

    _persistence = persistence;

    control = ControlledWorkflowPersistence(persistence);
    transport = LoopbackHostTransport();
    _shutdown = Completer<void>();

    final ready = Completer<void>();

    final application = WorkflowApplication(
      runtime: runtime,
      persistence: control,
      identity_provider: identities,
      os_user_id: owner,
    );

    final host = RudraHost(
      application: application,
      validate_start: (requested_target_id, requested_root) {
        if (requested_target_id != target_id ||
            !Directory(requested_root.value).isAbsolute) {
          throw ArgumentError('Invalid fixture target or root.');
        }
      },
      filesystem_application: FilesystemApplication(
        target_id: target_id,
        inspector: const UnusedTargetInspector(),
      ),
      communication_factory: ({required codecs, required handlers}) {
        return Communication(
          transport: transport,
          codecs: codecs,
          handlers: handlers,
        );
      },
    );

    final running = host.run(
      scope_directory: directory.absolute.path,
      shutdown: _shutdown.future,
      on_startup: (application) async {
        await application.read_state();

        ready.complete();
      },
    );

    _running = running;

    running.ignore();

    await Future.any<void>([
      ready.future,
      running.then<void>((_) {
        throw StateError('Host terminated before readiness.');
      }),
    ]).timeout(operation_timeout);
  }

  /// Establishes an independent communication client.
  ///
  /// [response_barrier] optionally suspends its first server response.
  ///
  /// Returns a client owning independently constructed message codecs
  /// and communication correlation state.
  Future<_Client> connect({LoopbackResponseBarrier? response_barrier}) async {
    transport.next_response_barrier = response_barrier;

    final communication = Communication(
      transport: transport,
      codecs: create_application_message_codecs(),
      options: const MessageSessionOptions(request_timeout: operation_timeout),
    );

    final session = await communication.connect(
      scope_directory: directory.absolute.path,
      os_user_id: owner,
    );

    final client = _Client(communication: communication, session: session);

    _clients.add(client);

    return client;
  }

  /// Sends an identified Start from [client].
  ///
  /// [key] identifies the logical operation. [root] optionally replaces
  /// the fixture's default requested filesystem root.
  ///
  /// Returns the application outcome received through communication.
  Future<WorkflowOperationOutcome> start(
    _Client client,
    String key, {
    TargetPath? root,
  }) async {
    final response = await client.session.request(
      WorkflowStartRequest(
        target_id: target_id,
        root: root ?? this.root,
        idempotency_key: key,
      ),
    );

    return response.outcome;
  }

  /// Sends an identified Stop from [client].
  ///
  /// [key] identifies the logical operation and [workflow_id] identifies
  /// the intended workflow.
  ///
  /// Returns the application outcome received through communication.
  Future<WorkflowOperationOutcome> stop(
    _Client client,
    String key,
    String workflow_id,
  ) async {
    final response = await client.session.request(
      WorkflowStopRequest(workflow_id: workflow_id, idempotency_key: key),
    );

    return response.outcome;
  }

  /// Reads authoritative application state through [client].
  ///
  /// Returns the current workflow or null for verified absence.
  Future<WorkflowSnapshot?> current(_Client client) async {
    final response = await client.session.request(const StateReadRequest());

    return response.state.workflows.current_workflow;
  }

  /// Queries the durable resolution of [receipt] through [client].
  ///
  /// Returns null when no matching submission is accessible.
  Future<WorkflowSubmissionResolution?> status(
    _Client client,
    EventSubmissionReceipt receipt,
  ) async {
    final response = await client.session.request(
      WorkflowSubmissionRequest(receipt: receipt),
    );

    return response.resolution;
  }

  /// Executes two operations with overlapping durable acceptance.
  ///
  /// [first] executes the initial client operation, whose validated
  /// commitment is suspended.
  ///
  /// [second] executes the competing operation after the first has
  /// reached the commitment boundary. It receives that validated plan.
  ///
  /// [second_key] and [second_occurrence] identify the acceptance
  /// invocation that must complete before commitment is released.
  ///
  /// [observer] independently queries pending submission status
  /// while both operations remain outstanding.
  ///
  /// Returns application outcomes in invocation order.
  Future<List<WorkflowOperationOutcome>> overlap({
    required Future<WorkflowOperationOutcome> Function() first,
    required Future<WorkflowOperationOutcome> Function(WorkflowProcessingPlan)
    second,
    required String second_key,
    required _Client observer,
    int second_occurrence = 1,
  }) async {
    final barrier = control.hold_next_commit();

    final first_result = first();

    first_result.ignore();

    late Future<WorkflowOperationOutcome> second_result;

    try {
      final plan = await barrier.entered.timeout(operation_timeout);

      second_result = second(plan);

      second_result.ignore();

      final receipt = await control
          .accepted(second_key, occurrence: second_occurrence)
          .timeout(operation_timeout);

      // Confirm both accepted obligations through a real client
      // session before allowing the first SQLite commitment.
      final first_pending = await status(observer, plan.submission.receipt);

      final second_pending = await status(observer, receipt);

      expect(first_pending!.state, WorkflowSubmissionState.pending);
      expect(second_pending!.state, WorkflowSubmissionState.pending);
    } finally {
      barrier.release();
    }

    return Future.wait([first_result, second_result]);
  }

  /// Terminates all clients and the current host.
  ///
  /// Releases controlled commitment barriers before disposal.
  /// Persistence remains available until host execution has drained.
  ///
  /// Repeated invocation is permitted.
  Future<void> stop_host() async {
    final persistence = _persistence;

    if (persistence == null) {
      return;
    }

    control.release_commit();

    try {
      await Future.wait<void>(_clients.map((client) => client.close()));
    } finally {
      _clients.clear();

      if (!_shutdown.isCompleted) {
        _shutdown.complete();
      }

      try {
        // Host execution owns the admitted-handler drain boundary.
        await _running;
      } finally {
        await persistence.close();

        _running = null;
        _persistence = null;
      }
    }
  }

  /// Verifies journal and resolution evidence after host termination.
  ///
  /// [resolutions] identifies the expected distinct durable submissions.
  /// Completed resolutions must correspond exactly to committed journal
  /// entries, including their sequence, workflow identity and version.
  ///
  /// [active_workflow_id] identifies the expected unfinished projection.
  /// Null requires verified absence of an unfinished workflow.
  ///
  /// Opens an independent read context only after host persistence
  /// has been closed. Leaves the host stopped.
  Future<void> verify_evidence({
    required List<WorkflowSubmissionResolution> resolutions,
    String? active_workflow_id,
  }) async {
    await stop_host();

    final inspection = RudraSqlitePersistence(
      database_file: database_file,
      scope_id: scope_id,
      runtime: runtime,
    );

    try {
      final reader = inspection.workflow_status_reader_for(os_user_id: owner);

      expect(
        resolutions.map((resolution) => resolution.receipt.event_id).toSet(),
        hasLength(resolutions.length),
      );

      for (final expected in resolutions) {
        final actual = await reader.status_for(expected.receipt);

        _expect_same_resolution(expected, actual!);
      }

      final evidence = await inspection.workflow_history_store
          .load_restoration_evidence(os_user_id: owner);

      expect(
        evidence.projected?.projected_identity.workflow_id,
        active_workflow_id,
      );

      final journal = <WorkflowJournalEntry>[
        ...?evidence.projected?.journal,
        ...evidence.other_histories.expand((history) => history.journal),
      ]..sort((a, b) => a.sequence.compareTo(b.sequence));

      final expected_outcomes =
          resolutions
              .where(
                (resolution) =>
                    resolution.state == WorkflowSubmissionState.completed,
              )
              .map((resolution) => resolution.committed_outcome!)
              .toList()
            ..sort((a, b) => a.sequence.compareTo(b.sequence));

      // Compare exact authoritative outcome references rather than
      // relying solely on the final projected workflow state.
      expect(
        journal.map(
          (event) => (
            event.sequence,
            event.workflow_id,
            event.version,
            event.event_type,
          ),
        ),
        orderedEquals(
          expected_outcomes.map(
            (outcome) => (
              outcome.sequence,
              outcome.workflow_id,
              outcome.version,
              outcome.event_type,
            ),
          ),
        ),
      );

      final restored = await WorkflowStateReader(
        runtime: runtime,
        history_store: inspection.workflow_history_store,
        os_user_id: owner,
      ).current();

      expect(restored?.state.identity.workflow_id, active_workflow_id);
    } finally {
      await inspection.close();
    }
  }

  /// Releases host resources and deletes the isolated test directory.
  Future<void> dispose() async {
    try {
      await stop_host();
    } finally {
      await directory.delete(recursive: true);
    }
  }
}

/// Owns one independent client communication lifecycle.
final class _Client {
  /// Creates a client retaining [communication] and its [session].
  const _Client({required this.communication, required this.session});

  /// Communication subsystem owned by this client.
  final Communication communication;

  /// Authenticated application message session.
  final MessageSession session;

  /// Terminates the client and awaits communication resource disposal.
  ///
  /// Repeated invocation preserves the existing lifecycle result.
  Future<void> close() async {
    try {
      await session.close();
    } finally {
      await communication.done;
    }
  }
}

/// Proposes deterministic trusted workflow identities.
///
/// Retains identity uniqueness across fixture host restarts.
final class _IdentityProvider implements WorkflowIdentityProvider {
  /// Number of identities proposed by this provider.
  int _sequence = 0;

  /// Proposes an owner-bound identity for the accepted [submission].
  ///
  /// Preserves the accepted Start target and root.
  ///
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
