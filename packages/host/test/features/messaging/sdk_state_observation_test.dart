import 'dart:async';
import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_host/rudra_host.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../../support/loopback_host_transport.dart';
import '../../support/test_host_ownership_provider.dart';
import '../../support/unused_target_inspector.dart';
import '../../support/host_test_transport_registry.dart';

/// Verifies public SDK observation against an authoritative host.
///
/// All application operations and observations use RudraSdk.
/// Controlled transport is supplied only through trusted composition.
void main() {
  late _HostFixture fixture;

  setUp(() async {
    fixture = await _HostFixture.create();

    addTearDown(fixture.dispose);

    await fixture.start_host();
  });

  test('independent SDKs observe committed Start and Stop', () async {
    final first = await fixture.connect();
    final second = await fixture.connect();

    final first_state = fixture.observe(first);
    final second_state = fixture.observe(second);

    expect(await first_state.moveNext(), isTrue);
    expect(await second_state.moveNext(), isTrue);

    expect(first_state.current.workflows.current_workflow, isNull);
    expect(second_state.current.workflows.current_workflow, isNull);

    expect(
      first.synchronization_status,
      StateSynchronizationStatus.synchronized,
    );

    expect(
      second.synchronization_status,
      StateSynchronizationStatus.synchronized,
    );

    // Observation and verified absence must not initialize storage.
    expect(await fixture.database_file.exists(), isFalse);

    final first_update = first_state.moveNext();
    final second_update = second_state.moveNext();

    final started = _completed(
      await first.workflows.start(
        root: fixture.root,
        idempotency_key: 'start-001',
      ),
    );

    final workflow_id = started.committed_outcome!.workflow_id;

    expect(await first_update, isTrue);
    expect(await second_update, isTrue);

    for (final listener in [first_state, second_state]) {
      final current = listener.current.workflows.current_workflow!;

      expect(current.identity.workflow_id, workflow_id);
      expect(current.version, 1);
    }

    final first_terminal = first_state.moveNext();
    final second_terminal = second_state.moveNext();

    final stopped = _completed(
      await second.workflows.stop(
        workflow_id: workflow_id,
        idempotency_key: 'stop-001',
      ),
    );

    expect(stopped.committed_outcome!.version, 2);

    expect(await first_terminal, isTrue);
    expect(await second_terminal, isTrue);

    expect(first_state.current.workflows.current_workflow, isNull);
    expect(second_state.current.workflows.current_workflow, isNull);

    await first_state.cancel();
    await second_state.cancel();

    expect(first.synchronization_status, StateSynchronizationStatus.idle);

    expect(second.synchronization_status, StateSynchronizationStatus.idle);

    expect(first.is_connected, isTrue);
    expect(second.is_connected, isTrue);
  });

  test(
    'one SDK shares observation across independent local listeners',
    () async {
      final sdk = await fixture.connect();
      final producer = await fixture.connect();

      final paused = fixture.observe(sdk);
      final live = fixture.observe(sdk);

      expect(await paused.moveNext(), isTrue);
      expect(await live.moveNext(), isTrue);

      expect(paused.current.workflows.current_workflow, isNull);
      expect(live.current.workflows.current_workflow, isNull);

      // Leave the first iterator paused while the second receives
      // committed changes through the shared remote subscription.
      for (var index = 1; index <= 3; index++) {
        final active_update = live.moveNext();

        final started = _completed(
          await producer.workflows.start(
            root: fixture.root,
            idempotency_key: 'start-$index',
          ),
        );

        expect(await active_update, isTrue);

        final workflow_id = started.committed_outcome!.workflow_id;

        expect(
          live.current.workflows.current_workflow!.identity.workflow_id,
          workflow_id,
        );

        final inactive_update = live.moveNext();

        _completed(
          await producer.workflows.stop(
            workflow_id: workflow_id,
            idempotency_key: 'stop-$index',
          ),
        );

        expect(await inactive_update, isTrue);
        expect(live.current.workflows.current_workflow, isNull);
      }

      final active_update = live.moveNext();

      final latest = _completed(
        await producer.workflows.start(
          root: fixture.root,
          idempotency_key: 'latest-start',
        ),
      );

      expect(await active_update, isTrue);

      // The paused listener resumes directly at the latest state.
      expect(await paused.moveNext(), isTrue);

      expect(
        paused.current.workflows.current_workflow!.identity.workflow_id,
        latest.committed_outcome!.workflow_id,
      );

      await paused.cancel();

      expect(
        sdk.synchronization_status,
        StateSynchronizationStatus.synchronized,
      );

      final terminal_update = live.moveNext();

      _completed(
        await producer.workflows.stop(
          workflow_id: latest.committed_outcome!.workflow_id,
          idempotency_key: 'latest-stop',
        ),
      );

      expect(await terminal_update, isTrue);
      expect(live.current.workflows.current_workflow, isNull);

      await live.cancel();

      expect(sdk.synchronization_status, StateSynchronizationStatus.idle);

      // The same authenticated connection supports a new subscription
      // after the previous subscription has completely drained.
      final replacement = fixture.observe(sdk);

      expect(await replacement.moveNext(), isTrue);
      expect(replacement.current.workflows.current_workflow, isNull);

      await replacement.cancel();

      expect(sdk.is_connected, isTrue);
    },
  );

  test('explicit reconnect invalidates old observation', () async {
    final sdk = await fixture.connect();

    final original = fixture.observe(sdk);

    expect(await original.moveNext(), isTrue);

    final interruption = expectLater(original.moveNext(), throwsStateError);

    await sdk.reconnect();

    await interruption;

    expect(sdk.synchronization_status, StateSynchronizationStatus.idle);

    expect(sdk.is_connected, isTrue);

    final replacement = fixture.observe(sdk);

    expect(await replacement.moveNext(), isTrue);
    expect(replacement.current.workflows.current_workflow, isNull);

    expect(sdk.synchronization_status, StateSynchronizationStatus.synchronized);

    await replacement.cancel();

    expect(await fixture.database_file.exists(), isFalse);
  });

  test(
    'host recreation restores committed state through fresh observation',
    () async {
      final sdk = await fixture.connect();

      final workflows = sdk.workflows;
      final original = fixture.observe(sdk);

      expect(await original.moveNext(), isTrue);

      final active_update = original.moveNext();

      final started = _completed(
        await workflows.start(
          root: fixture.root,
          idempotency_key: 'durable-start',
        ),
      );

      expect(await active_update, isTrue);

      final workflow_id = started.committed_outcome!.workflow_id;

      expect(
        original.current.workflows.current_workflow!.identity.workflow_id,
        workflow_id,
      );

      final interruption = expectLater(
        original.moveNext(),
        throwsA(anyOf(isA<StateError>(), isA<MessageSessionException>())),
      );

      await fixture.stop_host();
      await interruption;

      // Failed establishment drains the old lifecycle and explicitly
      // reports that the host is unavailable.
      await expectLater(sdk.reconnect(), throwsStateError);

      expect(sdk.resources_released, isTrue);

      await expectLater(sdk.observe_state(), emitsError(isA<StateError>()));

      await fixture.start_host();

      await sdk.reconnect(ConnectionParams(transport: fixture._transport));

      expect(sdk.workflows, same(workflows));

      final restored = fixture.observe(sdk);

      expect(await restored.moveNext(), isTrue);

      final current = restored.current.workflows.current_workflow!;

      expect(current.identity.workflow_id, workflow_id);
      expect(current.version, 1);

      // Durable operation resolution remains available without
      // resubmitting the original Start.
      final resolution = await workflows.status_for(started.receipt);

      expect(resolution, isNotNull);
      expect(resolution!.state, WorkflowSubmissionState.completed);

      expect(resolution.receipt.event_id, started.receipt.event_id);

      expect(
        resolution.committed_outcome!.sequence,
        started.committed_outcome!.sequence,
      );

      final terminal_update = restored.moveNext();

      final stopped = _completed(
        await workflows.stop(
          workflow_id: workflow_id,
          idempotency_key: 'durable-stop',
        ),
      );

      expect(stopped.committed_outcome!.version, 2);

      expect(await terminal_update, isTrue);
      expect(restored.current.workflows.current_workflow, isNull);

      await restored.cancel();
    },
  );

  test(
    'status observation survives connection replacement and closes',
    () async {
      final sdk = await fixture.connect();

      final statuses = StreamIterator<StateSynchronizationStatus>(
        sdk.observe_synchronization_status(),
      );

      addTearDown(statuses.cancel);

      expect(await statuses.moveNext(), isTrue);
      expect(statuses.current, StateSynchronizationStatus.idle);

      final states = fixture.observe(sdk);

      expect(await states.moveNext(), isTrue);

      expect(await statuses.moveNext(), isTrue);

      expect(statuses.current, StateSynchronizationStatus.synchronized);

      await states.cancel();

      expect(await statuses.moveNext(), isTrue);
      expect(statuses.current, StateSynchronizationStatus.idle);

      await sdk.reconnect();

      expect(sdk.synchronization_status, StateSynchronizationStatus.idle);

      final replacement = fixture.observe(sdk);

      expect(await replacement.moveNext(), isTrue);

      expect(await statuses.moveNext(), isTrue);

      expect(statuses.current, StateSynchronizationStatus.synchronized);

      // Close while the state iterator and status iterator are paused.
      // Frontend delivery must not delay SDK resource disposal.
      await sdk.close().timeout(_HostFixture.timeout);

      expect(sdk.resources_released, isTrue);

      expect(sdk.synchronization_status, StateSynchronizationStatus.closed);

      expect(await statuses.moveNext(), isTrue);
      expect(statuses.current, StateSynchronizationStatus.closed);

      expect(await statuses.moveNext(), isFalse);

      await expectLater(replacement.moveNext(), throwsStateError);
    },
  );
}

/// Extracts the durable committed resolution from [outcome].
WorkflowSubmissionResolution _completed(WorkflowOperationOutcome outcome) {
  expect(outcome, isA<WorkflowOperationResolved>());

  final resolution = (outcome as WorkflowOperationResolved).resolution;

  expect(resolution.state, WorkflowSubmissionState.completed);
  expect(resolution.committed_outcome, isNotNull);

  return resolution;
}

/// Owns a restartable authoritative host observation environment.
///
/// Uses production host composition and retained SQLite storage.
/// Independent SDK clients resolve the current controlled transport
/// whenever they establish authenticated communication.
///
/// Example:
/// ```dart
/// final fixture = await _HostFixture.create();
///
/// try {
///   await fixture.start_host();
///
///   final sdk = await fixture.connect();
///   final states = fixture.observe(sdk);
/// } finally {
///   await fixture.dispose();
/// }
/// ```
final class _HostFixture {
  /// Retains isolated [directory] and its canonical [scope].
  _HostFixture({required this.directory, required this.scope});

  /// Deadline for controlled integration lifecycle operations.
  static const timeout = Duration(seconds: 10);

  /// Trusted host and frontend identity.
  static const owner = 'trusted-owner';

  /// Configured filesystem target.
  static const target_id = 'local-macos';

  /// Isolated durable storage directory.
  final Directory directory;

  /// Canonical host communication scope.
  final String scope;

  /// Exclusive ownership shared by successive host lifecycles.
  final TestHostOwnershipProvider _ownership = TestHostOwnershipProvider();

  /// Owned independent SDK clients.
  final List<RudraSdk> _clients = [];

  /// Retained local observation iterators.
  final List<StreamIterator<RudraState>> _observations = [];

  /// Transport belonging to the currently executing host.
  late LoopbackHostTransport _transport;

  /// Retained host execution and disposal result.
  Future<void>? _running;

  /// External termination notification.
  Completer<void>? _shutdown;

  /// Durable database retained across host recreation.
  File get database_file =>
      File.fromUri(Directory(scope).uri.resolve('rudra.sqlite'));

  /// Target-native workflow root.
  TargetPath get root => TargetPath(scope);

  /// Creates isolated storage without starting the host.
  static Future<_HostFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'rudra-sdk-observation-',
    );

    return _HostFixture(
      directory: directory,
      scope: await directory.resolveSymbolicLinks(),
    );
  }

  /// Starts an independent host over the retained durable storage.
  ///
  /// Returns after authoritative initial publication is ready.
  /// Startup and readiness failures propagate.
  Future<void> start_host() async {
    if (_running != null) {
      throw StateError('Fixture host is already running.');
    }

    _transport = LoopbackHostTransport(os_user_id: owner);

    final composition = HostComposition(
      identity_provider: const _IdentityProvider(owner),
      ownership_provider: _ownership,
      resolve_database: () => File('$scope/rudra.sqlite'),
      target_id: target_id,
      inspector: const UnusedTargetInspector(),
      communication_factory: ({required codecs, required handlers}) {
        return Communication(
          transport_registry: host_test_transport_registry(_transport),
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

  /// Constructs and connects one independently owned SDK.
  ///
  /// Returns the authenticated client. The fixture retains its
  /// lifecycle for disposal and host recreation tests.
  Future<RudraSdk> connect() async {
    final sdk = RudraSdk(
      communication_factory: ({required codecs, required handlers}) {
        return Communication(
          codecs: codecs,
          handlers: handlers,
          options: const MessageSessionOptions(request_timeout: timeout),
        );
      },
    );

    _clients.add(sdk);

    await sdk.connect(ConnectionParams(transport: _transport)).timeout(timeout);

    return sdk;
  }

  /// Creates an independent local observation of [sdk].
  ///
  /// The returned iterator pauses between moveNext calls.
  StreamIterator<RudraState> observe(RudraSdk sdk) {
    final iterator = StreamIterator<RudraState>(sdk.observe_state());

    _observations.add(iterator);

    return iterator;
  }

  /// Terminates the current host without removing durable storage.
  ///
  /// Returns after the authoritative host has drained its resources.
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

  /// Releases SDK connections, observations, host and test storage.
  ///
  /// SDK closure invalidates pending observations before iterator
  /// cancellation, avoiding dependency on paused frontend delivery.
  Future<void> dispose() async {
    try {
      await Future.wait<void>(
        _clients.map((sdk) => sdk.close().timeout(timeout)),
      );
    } finally {
      try {
        for (final observation in _observations) {
          await observation.cancel();
        }
      } finally {
        try {
          await stop_host();
        } finally {
          await directory.delete(recursive: true);
        }
      }
    }
  }
}

/// Supplies the trusted operating-system identity for integration.
///
/// Example:
/// ```dart
/// const provider = _IdentityProvider('trusted-owner');
/// ```
final class _IdentityProvider implements HostIdentityProvider {
  /// Retains the trusted [os_user_id].
  const _IdentityProvider(this.os_user_id);

  /// Trusted identity represented by this fixture.
  final String os_user_id;

  /// Returns the retained trusted identity.
  @override
  Future<String> resolve() async => os_user_id;
}
