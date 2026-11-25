import 'dart:async';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies transport-independent authoritative state publication.
void main() {
  const generation = 'generation-a';

  final absent = RudraState(workflows: WorkflowsState(current_workflow: null));

  final active = RudraState(
    workflows: WorkflowsState(
      current_workflow:
          WorkflowStateMachine(runtime: WorkflowRuntime.standard()).transition(
            state: null,
            event: WorkflowStartedEvent(
              identity: WorkflowIdentity(
                workflow_id: 'workflow-1',
                os_user_id: 'trusted-owner',
                target_id: 'local-macos',
                root: TargetPath('/workspace'),
              ),
            ),
          ),
    ),
  );

  late StreamController<RudraState> source;
  late StatePublication publication;
  late int observation_count;

  setUp(() {
    source = StreamController<RudraState>.broadcast(sync: true);
    observation_count = 0;

    publication = StatePublication(
      generation: generation,
      maximum_subscriptions: 2,
      observe_state: () {
        observation_count++;
        return source.stream;
      },
    );
  });

  tearDown(() async {
    await publication.close();
    await source.close();
  });

  /// Starts observation and supplies [state] as the initial publication.
  Future<void> start(RudraState state) async {
    final ready = publication.start();
    source.add(state);
    await ready;
  }

  test('construction does not initiate authoritative observation', () {
    expect(observation_count, 0);
    expect(publication.latest, isNull);
    expect(publication.subscription_count, 0);

    expect(
      () => publication.subscribe(deliver: (_) async {}),
      throwsStateError,
    );
  });

  test('rejects invalid publication configuration', () {
    expect(
      () =>
          StatePublication(generation: '', observe_state: () => source.stream),
      throwsArgumentError,
    );

    expect(
      () => StatePublication(
        generation: generation,
        maximum_subscriptions: 0,
        observe_state: () => source.stream,
      ),
      throwsArgumentError,
    );

    expect(observation_count, 0);
  });

  test('shares initial observation across independent subscribers', () async {
    final first = _DeliveryProbe();
    final second = _DeliveryProbe();

    final ready = publication.start();

    publication.subscribe(deliver: first.deliver);
    publication.subscribe(deliver: second.deliver);

    expect(observation_count, 1);
    expect(publication.latest, isNull);
    expect(first.values, isEmpty);
    expect(second.values, isEmpty);

    source.add(absent);
    await ready;

    final first_initial = await first.at(0);
    final second_initial = await second.at(0);

    expect(first_initial, same(second_initial));
    expect(first_initial.generation, generation);
    expect(first_initial.revision, 1);
    expect(first_initial.state, same(absent));
    expect(publication.latest, same(first_initial));

    source.add(active);

    final first_update = await first.at(1);
    final second_update = await second.at(1);

    expect(first_update, same(second_update));
    expect(first_update.revision, 2);
    expect(first_update.state, same(active));
    expect(observation_count, 1);
  });

  test('late subscription captures the latest verified publication', () async {
    await start(absent);

    source.add(active);

    final probe = _DeliveryProbe();

    publication.subscribe(deliver: probe.deliver);

    final initial = await probe.at(0);

    expect(initial.revision, 2);
    expect(initial.state, same(active));
    expect(observation_count, 1);
  });

  test('preserves initial admission across overlapping publication', () async {
    await start(absent);

    final probe = _DeliveryProbe();

    publication.subscribe(deliver: probe.deliver);

    // Both publications arrive before the delivery worker executes.
    source.add(active);
    source.add(absent);

    expect((await probe.at(0)).revision, 1);

    final latest = await probe.at(1);

    expect(latest.revision, 3);
    expect(latest.state, same(absent));
    expect(probe.values.map((value) => value.revision), [1, 3]);
  });

  test('coalesces pending state without blocking another consumer', () async {
    final release_slow = Completer<void>();

    final slow = _DeliveryProbe(first_ack: release_slow.future);
    final fast = _DeliveryProbe();

    await start(absent);

    publication.subscribe(deliver: slow.deliver);
    publication.subscribe(deliver: fast.deliver);

    try {
      await slow.at(0);
      await fast.at(0);

      source.add(active);
      expect((await fast.at(1)).revision, 2);

      source.add(absent);
      expect((await fast.at(2)).revision, 3);

      source.add(active);
      expect((await fast.at(3)).revision, 4);

      expect(slow.values.map((value) => value.revision), [1]);

      release_slow.complete();

      final latest = await slow.at(1);

      expect(latest.revision, 4);
      expect(latest.state, same(active));
      expect(slow.values.map((value) => value.revision), [1, 4]);
      expect(fast.values.map((value) => value.revision), [1, 2, 3, 4]);
    } finally {
      if (!release_slow.isCompleted) {
        release_slow.complete();
      }
    }
  });

  test('retains cancelled subscriber capacity until delivery drains', () async {
    final release_delivery = Completer<void>();

    final blocked = _DeliveryProbe(first_ack: release_delivery.future);
    final healthy = _DeliveryProbe();

    await start(absent);

    final subscription = publication.subscribe(deliver: blocked.deliver);

    publication.subscribe(deliver: healthy.deliver);

    try {
      await blocked.at(0);
      await healthy.at(0);

      expect(publication.subscription_count, 2);

      source.add(active);

      final cancellation = subscription.cancel();

      await subscription.done;

      expect(publication.subscription_count, 2);

      expect(
        () => publication.subscribe(deliver: (_) async {}),
        throwsStateError,
      );

      release_delivery.complete();
      await cancellation;

      expect(publication.subscription_count, 1);
      expect(blocked.values, hasLength(1));

      final replacement = _DeliveryProbe();

      publication.subscribe(deliver: replacement.deliver);

      expect((await replacement.at(0)).revision, 2);
      expect((await healthy.at(1)).revision, 2);
      expect(publication.subscription_count, 2);
    } finally {
      if (!release_delivery.isCompleted) {
        release_delivery.complete();
      }
    }
  });

  test(
    'cancellation before delivery suppresses the initial publication',
    () async {
      await start(absent);

      final probe = _DeliveryProbe();

      final subscription = publication.subscribe(deliver: probe.deliver);

      await subscription.cancel();

      expect(probe.values, isEmpty);
      expect(publication.subscription_count, 0);

      source.add(active);

      expect(probe.values, isEmpty);
      expect(publication.latest?.revision, 2);
    },
  );

  test('isolates delivery failure from healthy subscribers', () async {
    await start(absent);

    final failure = StateError('Consumer delivery failed.');
    final healthy = _DeliveryProbe();

    final failed = publication.subscribe(deliver: (_) async => throw failure);

    publication.subscribe(deliver: healthy.deliver);

    await expectLater(failed.done, throwsA(same(failure)));
    await failed.cancel();

    expect(publication.subscription_count, 1);
    expect((await healthy.at(0)).revision, 1);

    source.add(active);

    expect((await healthy.at(1)).revision, 2);
    expect(publication.latest?.state, same(active));
  });

  test('source failure immediately invalidates the generation', () async {
    await start(absent);

    final release_delivery = Completer<void>();
    final probe = _DeliveryProbe(first_ack: release_delivery.future);

    final subscription = publication.subscribe(deliver: probe.deliver);

    try {
      await probe.at(0);

      final failure = StateError('Authoritative restoration failed.');

      final publication_failure = expectLater(
        publication.done,
        throwsA(same(failure)),
      );

      final subscriber_failure = expectLater(
        subscription.done,
        throwsA(same(failure)),
      );

      source.addError(failure);

      await publication_failure;
      await subscriber_failure;

      expect(publication.latest, isNull);

      expect(
        () => publication.subscribe(deliver: (_) async {}),
        throwsStateError,
      );

      var closed = false;

      final closing = publication.close().then<void>((_) {
        closed = true;
      });

      await Future<void>.value();

      // The generation is invalid, but the admitted delivery remains
      // owned until its underlying operation has settled.
      expect(closed, isFalse);
      expect(publication.subscription_count, 1);

      release_delivery.complete();
      await closing;

      expect(closed, isTrue);
      expect(publication.subscription_count, 0);
    } finally {
      if (!release_delivery.isCompleted) {
        release_delivery.complete();
      }
    }
  });

  test('failure before initial restoration rejects readiness', () async {
    final failure = StateError('Initial restoration failed.');

    final ready = publication.start();

    final readiness_failure = expectLater(ready, throwsA(same(failure)));

    final termination_failure = expectLater(
      publication.done,
      throwsA(same(failure)),
    );

    source.addError(failure);

    await readiness_failure;
    await termination_failure;

    expect(publication.latest, isNull);

    await publication.close();
  });

  test('unexpected source closure invalidates available state', () async {
    await start(absent);

    final terminated = expectLater(publication.done, throwsStateError);

    await source.close();
    await terminated;

    expect(publication.latest, isNull);

    await publication.close();
  });

  test(
    'explicit closure terminates subscribers and prevents restart',
    () async {
      await start(absent);

      final probe = _DeliveryProbe();

      final subscription = publication.subscribe(deliver: probe.deliver);

      await probe.at(0);

      final closing = publication.close();

      expect(publication.close(), same(closing));

      await publication.done;
      await subscription.done;
      await closing;

      expect(publication.latest, isNull);
      expect(publication.subscription_count, 0);

      expect(publication.start, throwsStateError);

      expect(
        () => publication.subscribe(deliver: (_) async {}),
        throwsStateError,
      );
    },
  );

  test('closure before initial restoration rejects readiness', () async {
    final ready = publication.start();

    final readiness_failure = expectLater(ready, throwsStateError);

    await publication.close();
    await publication.done;
    await readiness_failure;

    expect(publication.latest, isNull);
  });
}

/// Records admitted deliveries and optionally suspends acknowledgment
/// of the first publication.
final class _DeliveryProbe {
  /// Creates a probe with an optional first-delivery [first_ack] barrier.
  _DeliveryProbe({this.first_ack});

  /// Optional barrier controlling the initial acknowledgment.
  final Future<void>? first_ack;

  /// Publications admitted to this test consumer.
  final List<StatePublicationSnapshot> values = [];

  /// Notification of the next admitted publication.
  Completer<void> _changed = Completer<void>();

  /// Records [publication] and completes its acknowledgment.
  ///
  /// The first delivery awaits [first_ack] when supplied.
  Future<void> deliver(StatePublicationSnapshot publication) async {
    values.add(publication);

    final changed = _changed;
    _changed = Completer<void>();
    changed.complete();

    if (values.length == 1) {
      await first_ack;
    }
  }

  /// Returns the publication admitted at zero-based [index].
  ///
  /// Waits for the corresponding delivery when it has not yet arrived.
  Future<StatePublicationSnapshot> at(int index) async {
    while (values.length <= index) {
      await _changed.future;
    }

    return values[index];
  }
}
