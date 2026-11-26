import 'dart:async';
import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_host/rudra_host.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../../support/loopback_host_transport.dart';
import '../../support/test_host_ownership_provider.dart';
import '../../support/unused_target_inspector.dart';

/// Verifies public SDK workflow capabilities through one real host.
///
/// Application operations and state queries use only the public SDK
/// facade. The controlled transport establishes deterministic
/// communication interruption without replacing application execution.
void main() {
  late _HostFixture fixture;

  setUp(() async {
    fixture = await _HostFixture.create();

    addTearDown(fixture.dispose);

    await fixture.start_host();
  });

  test('read-only state and resolution queries leave storage absent', () async {
    final sdk = await fixture.connect();

    final state = await sdk.read_state();

    expect(state.workflows.current_workflow, isNull);

    final resolution = await sdk.workflows.status_for(
      EventSubmissionReceipt(
        event_id: 'unknown-event',
        correlation_id: 'unknown-correlation',
      ),
    );

    expect(resolution, isNull);
    expect(await fixture.database_file.exists(), isFalse);

    await sdk.close();

    expect(sdk.resources_released, isTrue);
    expect(await fixture.database_file.exists(), isFalse);
  });

  test('independent SDKs execute Start and Stop through one host', () async {
    final first = await fixture.connect();
    final second = await fixture.connect();

    expect((await first.read_state()).workflows.current_workflow, isNull);

    final started = _completed(
      await first.workflows.start(
        root: fixture.root,
        idempotency_key: 'start-001',
      ),
    );

    final committed = started.committed_outcome!;

    expect(committed.event_type, WorkflowStartedEvent.type_id);
    expect(committed.version, 1);

    for (final sdk in [first, second]) {
      final state = await sdk.read_state();
      final current = state.workflows.current_workflow!;

      expect(current.identity.workflow_id, committed.workflow_id);
      expect(current.identity.target_id, sdk.target_id);
      expect(current.identity.root.value, fixture.root.value);
      expect(current.identity.os_user_id, _HostFixture.owner);
      expect(current.version, 1);

      final queried = await sdk.workflows.status_for(started.receipt);

      expect(queried, isNotNull);
      _expect_same_resolution(started, queried!);
    }

    final stopped = _completed(
      await second.workflows.stop(
        workflow_id: committed.workflow_id,
        idempotency_key: 'stop-001',
      ),
    );

    final terminal = stopped.committed_outcome!;

    expect(terminal.workflow_id, committed.workflow_id);
    expect(terminal.event_type, WorkflowEndedEvent.type_id);
    expect(terminal.version, 2);

    for (final sdk in [first, second]) {
      final state = await sdk.read_state();

      expect(state.workflows.current_workflow, isNull);

      final queried = await sdk.workflows.status_for(stopped.receipt);

      expect(queried, isNotNull);
      _expect_same_resolution(stopped, queried!);
    }

    expect(await fixture.database_file.exists(), isTrue);
  });

  test('preserves durable rejections and idempotency conflicts', () async {
    final first = await fixture.connect();
    final second = await fixture.connect();

    final started = _completed(
      await first.workflows.start(
        root: fixture.root,
        idempotency_key: 'start-001',
      ),
    );

    final rejected = _resolved(
      await second.workflows.start(
        root: fixture.replacement_root,
        idempotency_key: 'start-002',
      ),
    );

    expect(rejected.state, WorkflowSubmissionState.rejected);
    expect(rejected.rejection_code, WorkflowRejectionCode.ownership_conflict);

    final queried = await first.workflows.status_for(rejected.receipt);

    expect(queried, isNotNull);
    _expect_same_resolution(rejected, queried!);

    final conflict = await second.workflows.start(
      root: fixture.replacement_root,
      idempotency_key: 'start-001',
    );

    expect(conflict, isA<WorkflowOperationIdempotencyConflict>());

    final current = (await second.read_state()).workflows.current_workflow!;

    expect(
      current.identity.workflow_id,
      started.committed_outcome!.workflow_id,
    );

    expect(current.identity.root.value, fixture.root.value);
    expect(current.version, 1);
  });

  test(
    'historical operation outcomes remain independent of current state',
    () async {
      final sdk = await fixture.connect();

      final original = _completed(
        await sdk.workflows.start(
          root: fixture.root,
          idempotency_key: 'original-start',
        ),
      );

      final original_id = original.committed_outcome!.workflow_id;

      final ended = _completed(
        await sdk.workflows.stop(
          workflow_id: original_id,
          idempotency_key: 'original-stop',
        ),
      );

      final replacement = _completed(
        await sdk.workflows.start(
          root: fixture.replacement_root,
          idempotency_key: 'replacement-start',
        ),
      );

      final replacement_id = replacement.committed_outcome!.workflow_id;

      expect(replacement_id, isNot(original_id));

      final historical_start = _completed(
        await sdk.workflows.start(
          root: fixture.root,
          idempotency_key: 'original-start',
        ),
      );

      final historical_stop = _completed(
        await sdk.workflows.stop(
          workflow_id: original_id,
          idempotency_key: 'original-stop',
        ),
      );

      _expect_same_resolution(original, historical_start);
      _expect_same_resolution(ended, historical_stop);

      final current = (await sdk.read_state()).workflows.current_workflow!;

      expect(current.identity.workflow_id, replacement_id);
      expect(current.identity.root.value, fixture.replacement_root.value);
      expect(current.version, 1);
    },
  );

  test('Stop cannot terminate a replacement workflow', () async {
    final first = await fixture.connect();
    final second = await fixture.connect();

    final original = _completed(
      await first.workflows.start(
        root: fixture.root,
        idempotency_key: 'original-start',
      ),
    );

    final displayed_id = (await second.read_state())
        .workflows
        .current_workflow!
        .identity
        .workflow_id;

    expect(displayed_id, original.committed_outcome!.workflow_id);

    _completed(
      await first.workflows.stop(
        workflow_id: displayed_id,
        idempotency_key: 'original-stop',
      ),
    );

    final replacement = _completed(
      await first.workflows.start(
        root: fixture.replacement_root,
        idempotency_key: 'replacement-start',
      ),
    );

    final rejected = _resolved(
      await second.workflows.stop(
        workflow_id: displayed_id,
        idempotency_key: 'stale-stop',
      ),
    );

    expect(rejected.state, WorkflowSubmissionState.rejected);
    expect(rejected.rejection_code, WorkflowRejectionCode.workflow_id_mismatch);

    final current = (await second.read_state()).workflows.current_workflow!;

    expect(
      current.identity.workflow_id,
      replacement.committed_outcome!.workflow_id,
    );

    expect(current.version, 1);
  });

  test('retained workflow service survives connection replacement', () async {
    final sdk = await fixture.connect();
    final workflows = sdk.workflows;

    final started = _completed(
      await workflows.start(root: fixture.root, idempotency_key: 'start-001'),
    );

    await sdk.reconnect();

    expect(sdk.workflows, same(workflows));

    final resolution = await workflows.status_for(started.receipt);

    expect(resolution, isNotNull);
    _expect_same_resolution(started, resolution!);

    final current = (await sdk.read_state()).workflows.current_workflow!;

    expect(
      current.identity.workflow_id,
      started.committed_outcome!.workflow_id,
    );

    final stopped = _completed(
      await workflows.stop(
        workflow_id: current.identity.workflow_id,
        idempotency_key: 'stop-001',
      ),
    );

    expect(stopped.committed_outcome!.version, 2);

    expect((await sdk.read_state()).workflows.current_workflow, isNull);
  });

  test('lost Start response remains recoverable after host restart', () async {
    final observer = await fixture.connect();

    final barrier = LoopbackResponseBarrier();

    // Suspend transmission of the next client's first host response.
    fixture.transport.next_response_barrier = barrier;

    final requester = await fixture.connect();
    final workflows = requester.workflows;

    final interrupted = workflows.start(
      root: fixture.root,
      idempotency_key: 'interrupted-start',
    );

    interrupted.ignore();

    late String committed_workflow_id;

    try {
      await barrier.entered.timeout(_HostFixture.timeout);

      // Start has completed authoritatively, but its response has
      // not reached the requester.
      final committed =
          (await observer.read_state()).workflows.current_workflow!;

      committed_workflow_id = committed.identity.workflow_id;

      expect(committed.version, 1);

      final failure = expectLater(
        interrupted,
        throwsA(isA<MessageSessionException>()),
      );

      await fixture.stop_host();

      await failure;

      // An explicit connection attempt against the stopped host
      // drains the previous lifecycle before reporting unavailability.
      await expectLater(requester.reconnect(), throwsStateError);

      expect(requester.is_connected, isFalse);
      expect(requester.resources_released, isTrue);
    } finally {
      barrier.release();
    }

    await expectLater(requester.read_state(), throwsStateError);

    await fixture.start_host();

    await requester.reconnect(ConnectionParams(transport: fixture.transport));

    expect(requester.workflows, same(workflows));

    final restored = (await requester.read_state()).workflows.current_workflow!;

    expect(restored.identity.workflow_id, committed_workflow_id);
    expect(restored.version, 1);

    // Recovery is an explicit retry of the original logical
    // operation, not a new Start or an automatic reconnect action.
    final recovered = _completed(
      await workflows.start(
        root: fixture.root,
        idempotency_key: 'interrupted-start',
      ),
    );

    expect(recovered.committed_outcome!.workflow_id, committed_workflow_id);

    expect(recovered.committed_outcome!.version, 1);

    final resolution = await workflows.status_for(recovered.receipt);

    expect(resolution, isNotNull);
    _expect_same_resolution(recovered, resolution!);

    final current = (await requester.read_state()).workflows.current_workflow!;

    expect(current.identity.workflow_id, committed_workflow_id);
    expect(current.version, 1);
  });

  test('known submission resolution survives host recreation', () async {
    final sdk = await fixture.connect();

    final started = _completed(
      await sdk.workflows.start(
        root: fixture.root,
        idempotency_key: 'durable-start',
      ),
    );

    await fixture.stop_host();
    await fixture.start_host();

    await sdk.reconnect(ConnectionParams(transport: fixture.transport));

    final recovered = await sdk.workflows.status_for(started.receipt);

    expect(recovered, isNotNull);
    _expect_same_resolution(started, recovered!);

    final restored = (await sdk.read_state()).workflows.current_workflow!;

    expect(
      restored.identity.workflow_id,
      started.committed_outcome!.workflow_id,
    );

    expect(restored.version, 1);
  });
}

/// Extracts the durable resolution from [outcome].
///
/// Requires an operation associated with an accepted submission.
WorkflowSubmissionResolution _resolved(WorkflowOperationOutcome outcome) {
  expect(outcome, isA<WorkflowOperationResolved>());

  return (outcome as WorkflowOperationResolved).resolution;
}

/// Extracts the successfully committed resolution from [outcome].
///
/// Requires a completed submission with its committed reference.
WorkflowSubmissionResolution _completed(WorkflowOperationOutcome outcome) {
  final resolution = _resolved(outcome);

  expect(resolution.state, WorkflowSubmissionState.completed);
  expect(resolution.committed_outcome, isNotNull);

  return resolution;
}

/// Verifies that [actual] preserves the original [expected] resolution.
///
/// Compares durable receipt identity, processing classification and
/// committed journal evidence independently of object identity.
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

/// Owns an isolated restartable host integration environment.
///
/// Each host lifecycle uses production HostComposition and retains
/// its durable database across recreation.
///
/// SDK instances establish independent connections through the
/// currently executing host's controlled transport.
///
/// Example:
/// ```dart
/// final fixture = await _HostFixture.create();
///
/// try {
///   await fixture.start_host();
///
///   final sdk = await fixture.connect();
///   final state = await sdk.read_state();
/// } finally {
///   await fixture.dispose();
/// }
/// ```
final class _HostFixture {
  /// Retains an isolated [directory] and its canonical [scope].
  _HostFixture({required this.directory, required this.scope});

  /// Deadline for controlled integration operations.
  static const timeout = Duration(seconds: 10);

  /// Trusted operating-system identity used by host and clients.
  static const owner = 'trusted-owner';

  /// Configured filesystem target.
  static const target_id = 'local-macos';

  /// Isolated storage directory retained across host recreation.
  final Directory directory;

  /// Canonical communication scope associated with the directory.
  final String scope;

  /// Controlled exclusive ownership shared by successive hosts.
  final TestHostOwnershipProvider _ownership = TestHostOwnershipProvider();

  /// SDK instances retained for ordered fixture disposal.
  final List<RudraSdk> _clients = [];

  /// Transport belonging to the current host lifecycle.
  late LoopbackHostTransport transport;

  /// Completion of the currently executing host lifecycle.
  Future<void>? _running;

  /// Termination notification for the current host lifecycle.
  Completer<void>? _shutdown;

  /// Durable database retained across host recreation.
  File get database_file =>
      File.fromUri(Directory(scope).uri.resolve('rudra.sqlite'));

  /// Original absolute target-native workflow root.
  TargetPath get root => TargetPath(scope);

  /// Distinct target-native root used by conflicting operations.
  TargetPath get replacement_root =>
      TargetPath('$scope${Platform.pathSeparator}replacement');

  /// Creates an isolated fixture without starting a host.
  ///
  /// Returns a fixture owning temporary test storage.
  /// Directory creation and resolution failures propagate.
  static Future<_HostFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'rudra-sdk-workflow-service-',
    );

    return _HostFixture(
      directory: directory,
      scope: await directory.resolveSymbolicLinks(),
    );
  }

  /// Establishes a fresh host over the retained database.
  ///
  /// Returns after initial authoritative publication is ready.
  ///
  /// Throws [StateError] if a host lifecycle remains retained.
  /// Initialization and readiness failures propagate.
  Future<void> start_host() async {
    if (_running != null) {
      throw StateError('Fixture host is already running.');
    }

    transport = LoopbackHostTransport(os_user_id: owner);

    final composition = HostComposition(
      identity_provider: const _TestIdentityProvider(owner),
      ownership_provider: _ownership,
      resolve_database: () => File('$scope/rudra.sqlite'),
      target_id: target_id,
      inspector: const UnusedTargetInspector(),
      communication_factory: ({required codecs, required handlers}) {
        return Communication(
          listening_transports: [transport],
          codecs: codecs,
          handlers: handlers,
          options: const MessageSessionOptions(request_timeout: timeout),
        );
      },
    );

    final shutdown = Completer<void>();
    final ready = Completer<void>();

    _shutdown = shutdown;

    final running = composition.run(
      shutdown: shutdown.future,
      on_ready: (os_user_id, workflow) {
        expect(os_user_id, owner);

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
    ]).timeout(timeout);
  }

  /// Constructs and connects an independently owned public SDK.
  ///
  /// Its communication factory resolves the current fixture transport
  /// on each connection attempt, permitting host recreation.
  ///
  /// Returns the connected SDK retained for fixture disposal.
  /// Connection establishment failures propagate.
  Future<RudraSdk> connect() async {
    final sdk = RudraSdk(
      target_id: target_id,

      communication_factory: ({required codecs, required handlers}) {
        return Communication(
          codecs: codecs,
          handlers: handlers,
          options: const MessageSessionOptions(request_timeout: timeout),
        );
      },
    );

    _clients.add(sdk);

    await sdk.connect(ConnectionParams(transport: transport)).timeout(timeout);

    return sdk;
  }

  /// Terminates the current host and awaits complete disposal.
  ///
  /// Retains the durable database and SDK instances for subsequent
  /// explicit reconnection.
  ///
  /// Repeated invocation after successful termination is permitted.
  Future<void> stop_host() async {
    final running = _running;

    if (running == null) return;

    final shutdown = _shutdown!;

    if (!shutdown.isCompleted) {
      shutdown.complete();
    }

    await running.timeout(timeout);

    _running = null;
    _shutdown = null;
  }

  /// Releases owned SDK connections, host and isolated test storage.
  ///
  /// SDK disposal precedes host termination. The database is removed
  /// only after the fixture has attempted all lifecycle cleanup.
  Future<void> dispose() async {
    try {
      await Future.wait<void>(
        _clients.map((sdk) => sdk.close().timeout(timeout)),
      );
    } finally {
      try {
        await stop_host();
      } finally {
        await directory.delete(recursive: true);
      }
    }
  }
}

/// Supplies deterministic trusted host identity.
///
/// Example:
/// ```dart
/// const identity = _TestIdentityProvider('trusted-owner');
///
/// print(await identity.resolve());
/// ```
final class _TestIdentityProvider implements HostIdentityProvider {
  /// Retains the trusted fixture [os_user_id].
  const _TestIdentityProvider(this.os_user_id);

  /// Trusted operating-system owner of the test host.
  final String os_user_id;

  /// Returns the configured trusted identity.
  @override
  Future<String> resolve() async => os_user_id;
}
