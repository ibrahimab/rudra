import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/state/observation/remote_state_observer.dart';
import 'package:test/test.dart';

/// Verifies remote state acceptance, local fan-out and retirement.
///
/// Controlled sessions permit delivery and acceptance to arrive in
/// either order without timing-dependent test orchestration.
void main() {
  late _Fixture fixture;

  setUp(() {
    fixture = _Fixture();

    addTearDown(fixture.dispose);
  });

  test('unavailable observation terminates with an error', () async {
    final observer = RemoteStateObserver();

    expect(observer.status, StateSynchronizationStatus.disconnected);

    await expectLater(observer.observe(), emitsError(isA<StateError>()));

    observer.close();
  });

  test('initial delivery remains unavailable until acceptance', () async {
    final listener = fixture.listen();

    final initial = listener.moveNext();
    final call = await fixture.peer.next_subscribe();

    final first = _publication(revision: 1);
    final latest = _publication(revision: 2);

    final first_ack = await fixture.peer.deliver(
      call.request.subscription_id,
      first,
    );

    expect(first_ack.subscription_id, call.request.subscription_id);
    expect(first_ack.generation, first.generation);
    expect(first_ack.revision, first.revision);

    final latest_ack = await fixture.peer.deliver(
      call.request.subscription_id,
      latest,
    );

    expect(latest_ack.revision, latest.revision);

    expect(fixture.observer.status, StateSynchronizationStatus.synchronizing);

    call.response.complete(
      StateSubscribeResponse(
        subscription_id: call.request.subscription_id,
        generation: latest.generation,
      ),
    );

    expect(await initial, isTrue);
    expect(listener.current, same(latest.state));

    expect(fixture.observer.status, StateSynchronizationStatus.synchronized);

    await fixture.cancel_last(listener);
  });

  test('acceptance alone does not establish verified state', () async {
    final listener = fixture.listen();
    final initial = listener.moveNext();

    final call = await fixture.peer.next_subscribe();
    final publication = _publication(revision: 1);

    call.response.complete(
      StateSubscribeResponse(
        subscription_id: call.request.subscription_id,
        generation: publication.generation,
      ),
    );

    // Drain acceptance microtasks before initiating initial delivery.
    await Future<void>(() {});

    expect(fixture.observer.status, StateSynchronizationStatus.synchronizing);

    await fixture.peer.deliver(call.request.subscription_id, publication);

    expect(await initial, isTrue);
    expect(listener.current, same(publication.state));

    await fixture.cancel_last(listener);
  });

  test('independent listeners share one bounded remote subscription', () async {
    final first = fixture.listen();
    final first_initial = first.moveNext();

    final call = await fixture.peer.next_subscribe();
    final initial = _publication(revision: 1);

    call.response.complete(
      StateSubscribeResponse(
        subscription_id: call.request.subscription_id,
        generation: initial.generation,
      ),
    );

    await fixture.peer.deliver(call.request.subscription_id, initial);

    expect(await first_initial, isTrue);
    expect(first.current, same(initial.state));

    final second = fixture.listen();

    expect(await second.moveNext(), isTrue);
    expect(second.current, same(initial.state));

    expect(fixture.peer.subscribe_count, 1);

    late StatePublicationSnapshot latest;

    // StreamIterator pauses its underlying subscription between
    // moveNext calls. The first listener remains paused while
    // the second independently receives every controlled delivery.
    for (var revision = 2; revision <= 20; revision++) {
      latest = _publication(revision: revision);

      final next = second.moveNext();

      await fixture.peer.deliver(call.request.subscription_id, latest);

      expect(await next, isTrue);
      expect(second.current, same(latest.state));
    }

    // Resuming the first listener receives the latest state, not
    // the first accumulated intermediate publication.
    expect(await first.moveNext(), isTrue);
    expect(first.current, same(latest.state));

    await first.cancel();

    expect(fixture.peer.unsubscribe_count, 0);

    await fixture.cancel_last(second);

    expect(fixture.peer.unsubscribe_count, 1);
    expect(fixture.observer.status, StateSynchronizationStatus.idle);
  });

  test('replacement listener waits for outstanding cancellation', () async {
    final first = fixture.listen();
    final first_initial = first.moveNext();

    first_initial.ignore();

    final original = await fixture.peer.next_subscribe();

    final cancellation = first.cancel();

    cancellation.ignore();

    expect(fixture.observer.status, StateSynchronizationStatus.cancelling);

    final replacement = fixture.listen();
    final replacement_initial = replacement.moveNext();

    expect(fixture.peer.subscribe_count, 1);

    final early = _publication(revision: 1);

    // Initial delivery is valid even though the listener that
    // initiated establishment has already cancelled.
    final acknowledgment = await fixture.peer.deliver(
      original.request.subscription_id,
      early,
    );

    expect(acknowledgment.revision, early.revision);

    original.response.complete(
      StateSubscribeResponse(
        subscription_id: original.request.subscription_id,
        generation: early.generation,
      ),
    );

    final retiring = await fixture.peer.next_unsubscribe();

    expect(retiring.request.subscription_id, original.request.subscription_id);

    final latest = _publication(revision: 2);

    // An admitted delivery during cancellation still requires
    // acknowledgment, but must not reach the replacement listener.
    final final_ack = await fixture.peer.deliver(
      original.request.subscription_id,
      latest,
    );

    expect(final_ack.revision, latest.revision);
    expect(fixture.peer.subscribe_count, 1);

    retiring.response.complete(
      StateUnsubscribeResponse(
        subscription_id: retiring.request.subscription_id,
      ),
    );

    await cancellation;

    final next = await fixture.peer.next_subscribe();

    expect(
      next.request.subscription_id,
      isNot(original.request.subscription_id),
    );

    next.response.complete(
      StateSubscribeResponse(
        subscription_id: next.request.subscription_id,
        generation: latest.generation,
      ),
    );

    // A fresh subscription may begin at the same latest position.
    await fixture.peer.deliver(next.request.subscription_id, latest);

    expect(await replacement_initial, isTrue);
    expect(replacement.current, same(latest.state));

    await fixture.cancel_last(replacement);
  });

  for (final violation in [
    'duplicate revision',
    'changed generation',
    'incorrect subscription',
  ]) {
    test('rejects $violation and terminates observation', () async {
      final listener = fixture.listen();
      final initial = listener.moveNext();

      final call = await fixture.peer.next_subscribe();

      final publication = _publication(revision: 2);

      call.response.complete(
        StateSubscribeResponse(
          subscription_id: call.request.subscription_id,
          generation: publication.generation,
        ),
      );

      await fixture.peer.deliver(call.request.subscription_id, publication);

      expect(await initial, isTrue);

      final failure = expectLater(listener.moveNext(), throwsStateError);

      final invalid = switch (violation) {
        'duplicate revision' => _publication(revision: 2),
        'changed generation' => _publication(
          generation: 'unexpected-generation',
          revision: 3,
        ),
        _ => _publication(revision: 3),
      };

      await expectLater(
        fixture.peer.deliver(
          violation == 'incorrect subscription'
              ? 'unexpected-subscription'
              : call.request.subscription_id,
          invalid,
        ),
        throwsStateError,
      );

      await failure;
      await fixture.peer.done;

      expect(fixture.observer.status, StateSynchronizationStatus.failed);
    });
  }

  test(
    'accepted subscription requires initial state before deadline',
    () async {
      final observer = RemoteStateObserver(
        initial_state_timeout: const Duration(milliseconds: 20),
      );

      final peer = _Peer(observer);

      observer.attach_session(peer);

      final listener = StreamIterator<RudraState>(observer.observe());

      addTearDown(() async {
        observer.close();

        await listener.cancel();
        await peer.dispose();
      });

      final failure = expectLater(
        listener.moveNext(),
        throwsA(isA<TimeoutException>()),
      );

      final call = await peer.next_subscribe();

      call.response.complete(
        StateSubscribeResponse(
          subscription_id: call.request.subscription_id,
          generation: 'host-generation',
        ),
      );

      await failure;
      await peer.done;

      expect(observer.status, StateSynchronizationStatus.failed);
    },
  );

  test('rejects acceptance contradicting initial delivery', () async {
    final listener = fixture.listen();

    final failure = expectLater(listener.moveNext(), throwsStateError);

    final call = await fixture.peer.next_subscribe();

    await fixture.peer.deliver(
      call.request.subscription_id,
      _publication(revision: 1),
    );

    call.response.complete(
      StateSubscribeResponse(
        subscription_id: call.request.subscription_id,
        generation: 'contradictory-generation',
      ),
    );

    await failure;
    await fixture.peer.done;

    expect(fixture.observer.status, StateSynchronizationStatus.failed);
  });

  test(
    'rejects regression within the same generation after reconnect',
    () async {
      final first = fixture.listen();
      final initial = first.moveNext();

      final original = await fixture.peer.next_subscribe();
      final publication = _publication(revision: 5);

      original.response.complete(
        StateSubscribeResponse(
          subscription_id: original.request.subscription_id,
          generation: publication.generation,
        ),
      );

      await fixture.peer.deliver(original.request.subscription_id, publication);

      expect(await initial, isTrue);

      final disconnected = expectLater(first.moveNext(), throwsStateError);

      await fixture.replace_peer();
      await disconnected;

      final second = fixture.listen();

      final failure = expectLater(second.moveNext(), throwsStateError);

      final replacement = await fixture.peer.next_subscribe();

      replacement.response.complete(
        StateSubscribeResponse(
          subscription_id: replacement.request.subscription_id,
          generation: publication.generation,
        ),
      );

      await expectLater(
        fixture.peer.deliver(
          replacement.request.subscription_id,
          _publication(revision: 4),
        ),
        throwsStateError,
      );

      await failure;
    },
  );

  test('accepts a new generation after authenticated replacement', () async {
    final first = fixture.listen();
    final initial = first.moveNext();

    final original = await fixture.peer.next_subscribe();
    final publication = _publication(revision: 8);

    original.response.complete(
      StateSubscribeResponse(
        subscription_id: original.request.subscription_id,
        generation: publication.generation,
      ),
    );

    await fixture.peer.deliver(original.request.subscription_id, publication);

    expect(await initial, isTrue);

    final disconnected = expectLater(first.moveNext(), throwsStateError);

    final previous_peer = fixture.peer;

    await fixture.replace_peer();
    await disconnected;

    final second = fixture.listen();
    final next = second.moveNext();

    final replacement = await fixture.peer.next_subscribe();

    final restarted = _publication(generation: 'restarted-host', revision: 1);

    replacement.response.complete(
      StateSubscribeResponse(
        subscription_id: replacement.request.subscription_id,
        generation: restarted.generation,
      ),
    );

    await fixture.peer.deliver(replacement.request.subscription_id, restarted);

    expect(await next, isTrue);
    expect(second.current, same(restarted.state));

    // A stale originating session cannot overwrite the current
    // session's accepted state or invalidate its subscribers.
    await expectLater(
      previous_peer.deliver(
        original.request.subscription_id,
        _publication(revision: 9),
      ),
      throwsStateError,
    );

    expect(fixture.observer.status, StateSynchronizationStatus.synchronized);

    await fixture.cancel_last(second);
  });
}

/// Constructs a distinct immutable synthetic publication.
///
/// [generation] identifies the originating host.
/// [revision] supplies its positive publication position.
StatePublicationSnapshot _publication({
  String generation = 'host-generation',
  required int revision,
}) {
  return StatePublicationSnapshot(
    generation: generation,
    revision: revision,
    state: RudraState(workflows: WorkflowsState(current_workflow: null)),
  );
}

/// Retains a controlled subscription establishment request.
typedef _SubscribeCall = ({
  StateSubscribeRequest request,
  Completer<StateSubscribeResponse> response,
});

/// Retains a controlled subscription cancellation request.
typedef _UnsubscribeCall = ({
  StateUnsubscribeRequest request,
  Completer<StateUnsubscribeResponse> response,
});

/// Owns a remote observation test environment.
///
/// Example:
/// ```dart
/// final fixture = _Fixture();
///
/// try {
///   final listener = fixture.listen();
/// } finally {
///   await fixture.dispose();
/// }
/// ```
final class _Fixture {
  /// Creates an observer with an authenticated controlled session.
  _Fixture() {
    peer = _create_peer();
  }

  /// Observation implementation under test.
  final RemoteStateObserver observer = RemoteStateObserver();

  /// Current controlled authenticated session.
  late _Peer peer;

  /// All sessions retained for fixture disposal.
  final List<_Peer> _peers = [];

  /// Independently controlled local stream subscriptions.
  final List<StreamIterator<RudraState>> _listeners = [];

  /// Creates and attaches a fresh authenticated session.
  ///
  /// Session termination invalidates only its own observation.
  _Peer _create_peer() {
    final created = _Peer(observer);

    _peers.add(created);

    observer.attach_session(created);

    created.done.then<void>((_) {
      observer.detach_session(
        created,
        StateError('Controlled session disconnected.'),
        StackTrace.current,
      );
    }).ignore();

    return created;
  }

  /// Creates an independent local observation iterator.
  StreamIterator<RudraState> listen() {
    final iterator = StreamIterator<RudraState>(observer.observe());

    _listeners.add(iterator);

    return iterator;
  }

  /// Cancels the last [listener] and confirms remote cancellation.
  Future<void> cancel_last(StreamIterator<RudraState> listener) async {
    final cancellation = listener.cancel();

    cancellation.ignore();

    final call = await peer.next_unsubscribe();

    call.response.complete(
      StateUnsubscribeResponse(subscription_id: call.request.subscription_id),
    );

    await cancellation;
  }

  /// Invalidates the previous session and attaches its replacement.
  Future<void> replace_peer() async {
    final previous = peer;

    observer.detach_session(
      previous,
      StateError('Controlled connection replacement.'),
      StackTrace.current,
    );

    await previous.close();

    peer = _create_peer();
  }

  /// Releases all controlled listeners and sessions.
  Future<void> dispose() async {
    observer.close();

    for (final listener in _listeners) {
      await listener.cancel();
    }

    for (final session in _peers) {
      await session.dispose();
    }
  }
}

/// Controls application requests on one authenticated test session.
///
/// Uses the real request handler registry for incoming state delivery.
///
/// Example:
/// ```dart
/// final peer = _Peer(observer);
/// final call = await peer.next_subscribe();
/// ```
final class _Peer implements MessageSession {
  /// Creates a session using the observer's receiving handlers.
  _Peer(RemoteStateObserver observer) {
    observer.register_handlers(_handlers);

    _handlers.freeze(codecs: create_application_message_codecs());
  }

  /// Deadline for controlled request admission.
  static const timeout = Duration(seconds: 5);

  /// Trusted authenticated peer identity.
  @override
  String get os_user_id => 'trusted-owner';

  /// Real application receiving-handler registry.
  final RequestHandlerRegistry _handlers = RequestHandlerRegistry();

  /// Controlled outgoing subscription requests.
  final StreamController<_SubscribeCall> _subscribes =
      StreamController<_SubscribeCall>();

  /// Controlled outgoing cancellation requests.
  final StreamController<_UnsubscribeCall> _unsubscribes =
      StreamController<_UnsubscribeCall>();

  /// Sequential access to subscription request admission.
  late final StreamIterator<_SubscribeCall> _subscribe_iterator =
      StreamIterator<_SubscribeCall>(_subscribes.stream);

  /// Sequential access to cancellation request admission.
  late final StreamIterator<_UnsubscribeCall> _unsubscribe_iterator =
      StreamIterator<_UnsubscribeCall>(_unsubscribes.stream);

  /// Callbacks settling outstanding requests on session closure.
  final List<void Function()> _abort = [];

  /// Completion of the controlled session.
  final Completer<void> _completion = Completer<void>();

  /// Number of admitted subscription requests.
  int subscribe_count = 0;

  /// Number of admitted cancellation requests.
  int unsubscribe_count = 0;

  /// Session termination notification.
  @override
  Future<void> get done => _completion.future;

  /// Receives the next outgoing subscription request.
  Future<_SubscribeCall> next_subscribe() async {
    if (!await _subscribe_iterator.moveNext().timeout(timeout)) {
      throw StateError('Subscription request stream ended.');
    }

    return _subscribe_iterator.current;
  }

  /// Receives the next outgoing cancellation request.
  Future<_UnsubscribeCall> next_unsubscribe() async {
    if (!await _unsubscribe_iterator.moveNext().timeout(timeout)) {
      throw StateError('Cancellation request stream ended.');
    }

    return _unsubscribe_iterator.current;
  }

  /// Admits a supported outgoing application [request].
  ///
  /// Returns its response after explicit test confirmation.
  /// Unexpected request types and closed sessions fail explicitly.
  @override
  Future<R> request<R extends Response>(Request<R> request) async {
    if (_completion.isCompleted) {
      throw StateError('Controlled session is closed.');
    }

    if (request is StateSubscribeRequest) {
      final _SubscribeCall call = (
        request: request as StateSubscribeRequest,
        response: Completer<StateSubscribeResponse>(),
      );

      subscribe_count++;

      _abort.add(() {
        if (!call.response.isCompleted) {
          call.response.completeError(
            StateError('Controlled session disconnected.'),
          );
        }
      });

      _subscribes.add(call);

      return (await call.response.future) as R;
    }

    if (request is StateUnsubscribeRequest) {
      final _UnsubscribeCall call = (
        request: request as StateUnsubscribeRequest,
        response: Completer<StateUnsubscribeResponse>(),
      );

      unsubscribe_count++;

      _abort.add(() {
        if (!call.response.isCompleted) {
          call.response.completeError(
            StateError('Controlled session disconnected.'),
          );
        }
      });

      _unsubscribes.add(call);

      return (await call.response.future) as R;
    }

    throw UnsupportedError('Unexpected observation request.');
  }

  /// Dispatches a controlled incoming [publication].
  ///
  /// [subscription_id] identifies its intended subscription.
  /// Returns the receiver's validated acknowledgment.
  ///
  /// Deliberately permits dispatch after closure to exercise stale
  /// session rejection in the receiving implementation.
  Future<StateDeliveryResponse> deliver(
    String subscription_id,
    StatePublicationSnapshot publication,
  ) async {
    final response = await _handlers.dispatch(
      StateDeliveryRequest(
        subscription_id: subscription_id,
        publication: publication,
      ),
      this,
    );

    return response as StateDeliveryResponse;
  }

  /// Terminates the session and settles outstanding requests.
  ///
  /// Repeated closure has no additional effect.
  @override
  Future<void> close() async {
    if (_completion.isCompleted) return;

    for (final abort in _abort) {
      abort();
    }

    _abort.clear();

    _completion.complete();

    _subscribes.close().ignore();
    _unsubscribes.close().ignore();
  }

  /// Releases controlled request streams and session resources.
  Future<void> dispose() async {
    await close();

    await _subscribe_iterator.cancel();
    await _unsubscribe_iterator.cancel();
  }
}
