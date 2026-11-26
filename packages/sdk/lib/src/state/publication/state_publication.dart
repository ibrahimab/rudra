import 'dart:async';

import '../rudra_state.dart';
import 'state_publication_snapshot.dart';

/// Delivers a verified [publication] to one state consumer.
///
/// Completion acknowledges acceptance by the consumer.
/// A failed future terminates that consumer's subscription.
///
/// Delivery implementations must eventually settle admitted operations,
/// including when their underlying resources are terminated.
typedef StateDelivery = Future<void> Function(
  StatePublicationSnapshot publication,
);

/// Distributes one authoritative application observation to independent
/// state consumers.
///
/// Publications share one generation and increase monotonically in
/// revision. Each subscription retains at most one admitted delivery
/// and one pending latest publication.
///
/// The caller owns the application and its persistence resources.
/// Those resources must remain available until [close] completes.
///
/// Example:
/// ```dart
/// final publication = StatePublication(
///   generation: generation,
///   observe_state: application.observe_state,
/// );
///
/// final ready = publication.start();
/// final subscription = publication.subscribe(
///   deliver: (snapshot) async {
///     print(snapshot.revision);
///   },
/// );
///
/// await ready;
/// await subscription.cancel();
/// await publication.close();
/// ```
final class StatePublication {
  /// Creates an inactive application-state publication lifecycle.
  ///
  /// [generation] must uniquely identify this publication lifecycle.
  /// [observe_state] supplies verified initial and subsequent state.
  /// [maximum_subscriptions] bounds active and draining consumers.
  ///
  /// Throws [ArgumentError] for a blank generation or non-positive
  /// subscription capacity.
  ///
  /// Construction does not begin authoritative observation.
  StatePublication({
    required this.generation,
    required Stream<RudraState> Function() observe_state,
    this.maximum_subscriptions = default_maximum_subscriptions,
  }) : _observe_state = observe_state {
    if (generation.trim().isEmpty) {
      throw ArgumentError.value(generation, 'generation');
    }

    if (maximum_subscriptions <= 0) {
      throw ArgumentError.value(maximum_subscriptions, 'maximum_subscriptions');
    }

    // Termination may precede an external lifecycle observer.
    _ready.future.ignore();
    _completion.future.ignore();
  }

  /// Default maximum number of retained subscriber lifecycles.
  static const int default_maximum_subscriptions = 32;

  /// Unique identity of this publication lifecycle.
  final String generation;

  /// Maximum number of active and draining subscriptions.
  final int maximum_subscriptions;

  /// Borrowed authoritative application observation capability.
  final Stream<RudraState> Function() _observe_state;

  /// Owned application observation subscription.
  StreamSubscription<RudraState>? _source;

  /// Subscriber resources retained until their deliveries have settled.
  final Set<StateSubscription> _subscriptions = {};

  /// Completion of initial authoritative state restoration.
  final Completer<void> _ready = Completer<void>();

  /// Terminal publication lifecycle result.
  final Completer<void> _completion = Completer<void>();

  /// Latest available verified publication.
  StatePublicationSnapshot? _latest;

  /// Last assigned publication revision.
  int _revision = 0;

  /// Whether authoritative observation has been started.
  bool _started = false;

  /// Whether publication and subscription admission have terminated.
  bool _stopped = false;

  /// Retained resource disposal operation.
  Future<void>? _closing;

  /// Latest verified state publication, when available.
  ///
  /// Null indicates that initial restoration has not completed or
  /// that this publication lifecycle has terminated.
  StatePublicationSnapshot? get latest => _latest;

  /// Number of subscriber lifecycles retaining publication capacity.
  ///
  /// Includes cancelled subscriptions with outstanding deliveries.
  int get subscription_count => _subscriptions.length;

  /// Terminal publication lifecycle result.
  ///
  /// Completes normally on explicit closure or with the authoritative
  /// observation failure that invalidated this generation.
  ///
  /// Termination notification precedes resource draining.
  /// Await [close] to confirm resource disposal.
  Future<void> get done => _completion.future;

  /// Starts the single authoritative observation.
  ///
  /// Returns when the initial verified publication is available.
  /// Subscriptions may be registered while restoration is pending.
  ///
  /// Source initialization and restoration failures propagate through
  /// the returned future and [done].
  ///
  /// Throws [StateError] on repeated execution or after termination.
  Future<void> start() {
    if (_started || _stopped) {
      throw StateError('State publication cannot be started.');
    }

    _started = true;

    try {
      _source = _observe_state().listen(
        _publish,
        onError: _fail,
        onDone: () {
          _fail(
            StateError('Authoritative state observation ended.'),
            StackTrace.current,
          );
        },
      );
    } catch (error, stack_trace) {
      _fail(error, stack_trace);
    }

    return _ready.future;
  }

  /// Registers an independent consumer using [deliver].
  ///
  /// Returns a subscription that receives the latest verified publication,
  /// or the initial publication once restoration completes.
  ///
  /// Registration and initial publication admission occur synchronously
  /// to preserve ordering with subsequent publications.
  ///
  /// Throws [StateError] before startup, after termination or when
  /// subscription capacity is exhausted.
  StateSubscription subscribe({required StateDelivery deliver}) {
    if (!_started || _stopped) {
      throw StateError('State publication is unavailable.');
    }

    if (_subscriptions.length >= maximum_subscriptions) {
      throw StateError('State subscription capacity exhausted.');
    }

    final subscription = StateSubscription._(
      deliver: deliver,
      on_drained: (subscription) {
        _subscriptions.remove(subscription);
      },
    );

    // Register before offering the initial publication. No asynchronous
    // boundary separates registration from the current publication.
    _subscriptions.add(subscription);

    final current = _latest;

    if (current != null) {
      subscription._offer(current);
    }

    return subscription;
  }

  /// Assigns the next revision to verified [state] and offers it
  /// independently to every retained subscriber.
  ///
  /// Delivery execution is scheduled separately from source observation.
  void _publish(RudraState state) {
    if (_stopped) return;

    final publication = StatePublicationSnapshot(
      generation: generation,
      revision: ++_revision,
      state: state,
    );

    _latest = publication;

    for (final subscription in _subscriptions) {
      subscription._offer(publication);
    }

    if (!_ready.isCompleted) {
      _ready.complete();
    }
  }

  /// Invalidates this generation after an authoritative [error].
  ///
  /// [stack_trace] preserves the source failure's diagnostics.
  void _fail(Object error, StackTrace stack_trace) {
    _terminate(error, stack_trace);
  }

  /// Terminates publication and drains its owned resources.
  ///
  /// Further subscriptions and publications are prohibited immediately.
  /// Outstanding authoritative restoration and admitted subscriber
  /// deliveries must settle before the returned future completes.
  ///
  /// Repeated calls return the retained disposal operation.
  /// Resource disposal failures propagate independently of [done].
  ///
  /// Callers must release external delivery resources where necessary
  /// to allow previously admitted delivery operations to settle.
  Future<void> close() {
    _terminate();
    return _closing!;
  }

  /// Establishes the terminal lifecycle result and schedules disposal.
  ///
  /// [error] optionally identifies an authoritative observation failure.
  /// [stack_trace] optionally preserves the failure stack.
  ///
  /// The first termination result is retained.
  void _terminate([Object? error, StackTrace? stack_trace]) {
    if (_stopped) return;

    _stopped = true;
    _latest = null;

    // Disposal must not execute inside an observation callback.
    _closing = Future<void>.microtask(_dispose);
    _closing!.ignore();

    for (final subscription in _subscriptions.toList()) {
      subscription._stop(error, stack_trace);
    }

    if (!_ready.isCompleted) {
      _ready.completeError(
        error ?? StateError('State publication closed before readiness.'),
        stack_trace,
      );
    }

    if (error == null) {
      _completion.complete();
    } else {
      _completion.completeError(error, stack_trace);
    }
  }

  /// Drains the source observation and retained subscriber deliveries.
  ///
  /// Initiates independent cancellation operations before awaiting their
  /// combined completion.
  Future<void> _dispose() async {
    final source = _source;
    final subscriptions = _subscriptions.toList(growable: false);

    await Future.wait<void>([
      if (source != null) Future<void>.sync(source.cancel),
      for (final subscription in subscriptions)
        Future<void>.sync(subscription.cancel),
    ]);
  }
}

/// Owns one bounded delivery lifecycle within a state publication.
///
/// Delivery is serialized. While acknowledgment is outstanding, newer
/// publications replace the pending latest publication.
///
/// Terminating a subscription prevents additional delivery admission
/// but does not retract an already executing delivery operation.
final class StateSubscription {
  /// Creates a subscription owned by its enclosing publication.
  ///
  /// [deliver] accepts and acknowledges individual publications.
  /// [on_drained] releases the registration after termination and
  /// completion of outstanding delivery.
  StateSubscription._({
    required StateDelivery deliver,
    required void Function(StateSubscription) on_drained,
  }) : _deliver = deliver,
       _on_drained = on_drained {
    _completion.future.ignore();
  }

  /// Consumer-owned acknowledged delivery capability.
  final StateDelivery _deliver;

  /// Callback releasing the owning publication's retained registration.
  final void Function(StateSubscription) _on_drained;

  /// Terminal subscription lifecycle result.
  final Completer<void> _completion = Completer<void>();

  /// Publication admitted to the delivery worker.
  StatePublicationSnapshot? _in_flight;

  /// Latest publication awaiting admission.
  StatePublicationSnapshot? _pending;

  /// Outstanding serialized delivery worker.
  Future<void>? _worker;

  /// Whether further delivery admission has been prohibited.
  bool _stopped = false;

  /// Terminal subscription lifecycle result.
  ///
  /// Completes normally on cancellation, or with an authoritative
  /// observation or subscriber-specific delivery failure.
  ///
  /// Await [cancel] to confirm outstanding delivery has settled.
  Future<void> get done => _completion.future;

  /// Offers a newer verified [publication] to this subscriber.
  ///
  /// Preserves the admitted publication and replaces any pending
  /// publication with the latest available state.
  void _offer(StatePublicationSnapshot publication) {
    if (_stopped) return;

    if (_worker != null) {
      _pending = publication;
      return;
    }

    _in_flight = publication;

    // Reserve the delivery worker before invoking consumer code.
    _worker = Future<void>.microtask(_drain);
  }

  /// Delivers admitted publications sequentially until no pending
  /// publication remains or the subscription terminates.
  ///
  /// Consumer failures terminate this subscription independently
  /// of other subscribers and authoritative observation.
  Future<void> _drain() async {
    try {
      while (!_stopped && _in_flight != null) {
        await _deliver(_in_flight!);

        if (_stopped) break;

        _in_flight = _pending;
        _pending = null;
      }
    } catch (error, stack_trace) {
      _stop(error, stack_trace);
    } finally {
      _in_flight = null;
      _pending = null;
      _worker = null;

      if (_stopped) {
        _on_drained(this);
      }
    }
  }

  /// Terminates this subscription and awaits its delivery worker.
  ///
  /// Pending publications are discarded immediately.
  /// Repeated cancellation has no additional effect.
  ///
  /// The delivery callback must not await cancellation of its own
  /// subscription, because cancellation awaits that callback.
  Future<void> cancel() {
    _stop();

    return _worker ?? Future<void>.value();
  }

  /// Establishes the subscription's terminal lifecycle result.
  ///
  /// [error] optionally identifies a delivery or observation failure.
  /// [stack_trace] optionally preserves the failure stack.
  ///
  /// Capacity is released only after outstanding delivery has settled.
  void _stop([Object? error, StackTrace? stack_trace]) {
    if (_stopped) return;

    _stopped = true;
    _pending = null;

    if (error == null) {
      _completion.complete();
    } else {
      _completion.completeError(error, stack_trace);
    }

    if (_worker == null) {
      _on_drained(this);
    }
  }
}
