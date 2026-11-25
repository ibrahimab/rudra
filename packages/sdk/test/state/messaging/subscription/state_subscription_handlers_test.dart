import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/state/messaging/subscription/state_subscription_handlers.dart';
import 'package:test/test.dart';

/// Verifies session-bound subscription ownership independently
/// of transport implementation.
void main() {
  final absent = RudraState(workflows: WorkflowsState(current_workflow: null));

  late StreamController<RudraState> source;
  late StatePublication publication;
  late StateSubscriptionHandlers handlers;

  setUp(() {
    source = StreamController<RudraState>.broadcast(sync: true);

    publication = StatePublication(
      generation: 'generation-1',
      observe_state: () => source.stream,
      maximum_subscriptions: 2,
    );

    handlers = StateSubscriptionHandlers(publication: publication);
  });

  tearDown(() async {
    await publication.close();
    await source.close();
  });

  /// Starts publication with an available verified state.
  Future<void> start() async {
    final ready = publication.start();
    source.add(absent);
    await ready;
  }

  test('scopes subscription identifiers to individual sessions', () async {
    await start();

    final first = _TestSession();
    final second = _TestSession();

    addTearDown(first.close);
    addTearDown(second.close);

    final request = StateSubscribeRequest(subscription_id: 'subscription-1');

    final first_response = handlers.subscribe(request, first);
    final second_response = handlers.subscribe(request, second);

    expect(first_response.subscription_id, 'subscription-1');
    expect(second_response.subscription_id, 'subscription-1');
    expect(first_response.generation, second_response.generation);
    expect(publication.subscription_count, 2);

    expect(() => handlers.subscribe(request, first), throwsStateError);

    await handlers.unsubscribe(
      StateUnsubscribeRequest(subscription_id: 'subscription-1'),
      first,
    );

    expect(publication.subscription_count, 1);
    expect(first.is_closed, isFalse);
    expect(second.is_closed, isFalse);

    await handlers.unsubscribe(
      StateUnsubscribeRequest(subscription_id: 'subscription-1'),
      second,
    );

    expect(publication.subscription_count, 0);
  });

  test('another session cannot cancel a retained subscription', () async {
    await start();

    final owner = _TestSession();
    final other = _TestSession();

    addTearDown(owner.close);
    addTearDown(other.close);

    handlers.subscribe(
      StateSubscribeRequest(subscription_id: 'subscription-1'),
      owner,
    );

    await expectLater(
      handlers.unsubscribe(
        StateUnsubscribeRequest(subscription_id: 'subscription-1'),
        other,
      ),
      throwsStateError,
    );

    expect(publication.subscription_count, 1);

    await handlers.unsubscribe(
      StateUnsubscribeRequest(subscription_id: 'subscription-1'),
      owner,
    );

    expect(publication.subscription_count, 0);
  });

  test('cancellation drains delivery before permitting replacement', () async {
    await start();

    final entered = Completer<void>();
    final release = Completer<void>();

    final session = _TestSession(
      deliver: (request) async {
        if (!entered.isCompleted) {
          entered.complete();
        }

        await release.future;

        return _acknowledge(request);
      },
    );

    addTearDown(session.close);

    try {
      handlers.subscribe(
        StateSubscribeRequest(subscription_id: 'subscription-1'),
        session,
      );

      await entered.future;

      final cancellation = handlers.unsubscribe(
        StateUnsubscribeRequest(subscription_id: 'subscription-1'),
        session,
      );

      expect(
        () => handlers.subscribe(
          StateSubscribeRequest(subscription_id: 'subscription-2'),
          session,
        ),
        throwsStateError,
      );

      expect(publication.subscription_count, 1);
      expect(session.is_closed, isFalse);

      // This publication must not be admitted to the cancelled subscriber.
      source.add(absent);

      release.complete();

      final response = await cancellation;

      expect(response.subscription_id, 'subscription-1');
      expect(publication.subscription_count, 0);
      expect(session.deliveries, hasLength(1));

      final replacement = handlers.subscribe(
        StateSubscribeRequest(subscription_id: 'subscription-2'),
        session,
      );

      expect(replacement.subscription_id, 'subscription-2');
      expect(publication.subscription_count, 1);
      expect(session.is_closed, isFalse);

      await handlers.unsubscribe(
        StateUnsubscribeRequest(subscription_id: 'subscription-2'),
        session,
      );
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
    }
  });

  test(
    'disconnection releases a subscription awaiting initial state',
    () async {
      final ready = publication.start();

      final session = _TestSession();

      handlers.subscribe(
        StateSubscribeRequest(subscription_id: 'subscription-1'),
        session,
      );

      expect(publication.subscription_count, 1);

      // No delivery is outstanding; the termination observer can release
      // the registration as soon as the session completes.
      await session.close();

      expect(publication.subscription_count, 0);

      source.add(absent);
      await ready;

      expect(session.deliveries, isEmpty);
    },
  );

  test('invalid acknowledgment closes only the affected session', () async {
    await start();

    final invalid = _TestSession(
      deliver: (request) async {
        return StateDeliveryResponse(
          subscription_id: request.subscription_id,
          generation: request.publication.generation,
          revision: request.publication.revision + 1,
        );
      },
    );

    final healthy = _TestSession();

    addTearDown(invalid.close);
    addTearDown(healthy.close);

    handlers.subscribe(
      StateSubscribeRequest(subscription_id: 'subscription-1'),
      invalid,
    );

    handlers.subscribe(
      StateSubscribeRequest(subscription_id: 'subscription-2'),
      healthy,
    );

    await invalid.done;

    expect(invalid.is_closed, isTrue);
    expect(healthy.is_closed, isFalse);
    expect(publication.subscription_count, 1);
    expect(publication.latest?.revision, 1);

    await handlers.unsubscribe(
      StateUnsubscribeRequest(subscription_id: 'subscription-2'),
      healthy,
    );

    expect(publication.subscription_count, 0);
  });

  test(
    'invalid acknowledgment during cancellation closes the session',
    () async {
      await start();

      final entered = Completer<void>();
      final release = Completer<void>();

      final session = _TestSession(
        deliver: (request) async {
          entered.complete();

          await release.future;

          return StateDeliveryResponse(
            subscription_id: request.subscription_id,
            generation: request.publication.generation,
            revision: request.publication.revision + 1,
          );
        },
      );

      addTearDown(session.close);

      try {
        handlers.subscribe(
          StateSubscribeRequest(subscription_id: 'subscription-1'),
          session,
        );

        await entered.future;

        final cancellation = handlers.unsubscribe(
          StateUnsubscribeRequest(subscription_id: 'subscription-1'),
          session,
        );

        release.complete();

        await session.done;
        await cancellation;

        expect(session.is_closed, isTrue);
        expect(publication.subscription_count, 0);
      } finally {
        if (!release.isCompleted) {
          release.complete();
        }
      }
    },
  );
}

/// Produces the acknowledgment corresponding to [request].
StateDeliveryResponse _acknowledge(StateDeliveryRequest request) {
  return StateDeliveryResponse(
    subscription_id: request.subscription_id,
    generation: request.publication.generation,
    revision: request.publication.revision,
  );
}

/// Supplies a controlled authenticated session for adapter tests.
///
/// Tests explicitly release suspended delivery operations before
/// disposal. Real communication termination is exercised separately
/// by host integration tests.
final class _TestSession implements MessageSession {
  /// Creates a session with an optional controlled delivery callback.
  _TestSession({this.deliver});

  /// Optional custom acknowledgment behavior.
  final Future<StateDeliveryResponse> Function(StateDeliveryRequest)? deliver;

  /// Deliveries admitted through this test session.
  final List<StateDeliveryRequest> deliveries = [];

  /// Session termination notification.
  final Completer<void> _completion = Completer<void>();

  /// Whether the session has been terminated.
  bool get is_closed => _completion.isCompleted;

  /// Trusted peer identity used by the test.
  @override
  String get os_user_id => 'trusted-owner';

  /// Session lifecycle completion.
  @override
  Future<void> get done => _completion.future;

  /// Accepts an outbound state delivery [request].
  ///
  /// Returns its configured typed acknowledgment.
  @override
  Future<R> request<R extends Response>(Request<R> request) async {
    if (is_closed) {
      throw StateError('Test session is closed.');
    }

    final delivery = request as StateDeliveryRequest;

    deliveries.add(delivery);

    final callback = deliver;

    final response = callback == null
        ? _acknowledge(delivery)
        : await callback(delivery);

    return response as R;
  }

  /// Completes the test session's lifecycle.
  ///
  /// Repeated closure is permitted.
  @override
  Future<void> close() async {
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }
}
