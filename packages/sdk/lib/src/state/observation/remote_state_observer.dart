import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:uuid/uuid.dart';

import '../messaging/subscription/state_subscription_messages.dart';
import '../publication/state_publication_snapshot.dart';
import '../rudra_state.dart';

import 'state_synchronization_status.dart';

/// Consumes authoritative state through one shared remote subscription.
///
/// Independent local listeners receive the latest verified state without
/// owning individual communication sessions or remote subscriptions.
///
/// State acceptance, delivery acknowledgment and local rendering remain
/// independent. Paused listeners retain only their latest pending value.
///
/// The owning SDK supplies authenticated sessions and coordinates their
/// lifecycle. This observer borrows those sessions.
///
/// Example:
/// ```dart
/// final observer = RemoteStateObserver();
/// observer.attach_session(authenticated_session);
///
/// final subscription = observer.observe().listen((state) {
///   print(state.workflows.current_workflow);
/// });
///
/// await subscription.cancel();
/// ```
final class RemoteStateObserver {
  /// Creates an inactive remote observation capability.
  ///
  /// [initial_state_timeout] bounds initial delivery after subscription
  /// acceptance. Request transmission and acceptance use the communication
  /// session's existing request deadlines.
  ///
  /// Throws [ArgumentError] for a non-positive timeout.
  /// Construction does not establish communication or subscribe.
  RemoteStateObserver({
    Duration initial_state_timeout = const Duration(seconds: 30),
  }) : _initial_state_timeout = initial_state_timeout {
    if (initial_state_timeout <= Duration.zero) {
      throw ArgumentError.value(initial_state_timeout, 'initial_state_timeout');
    }
  }

  /// Deadline for receiving initial verified state after acceptance.
  final Duration _initial_state_timeout;

  /// Independently identified remote subscription lifecycles.
  final Uuid _identifiers = Uuid();

  /// Authenticated session borrowed from the SDK connection owner.
  MessageSession? _session;

  /// Active or draining remote subscription.
  _RemoteSubscription? _binding;

  /// Publication generation established on the current session.
  String? _session_generation;

  /// Last accepted publication position across subscription replacement.
  ///
  /// Retains ordering metadata without retaining unavailable domain state.
  ({String generation, int revision})? _last_position;

  /// Latest verified state from the currently admitted subscription.
  RudraState? _current;

  /// Independent local application-state listeners.
  final Set<_LatestListener<RudraState>> _listeners = {};

  /// Independent synchronization-status listeners.
  final Set<_LatestListener<StateSynchronizationStatus>> _status_listeners = {};

  /// Current availability of authoritative observation.
  StateSynchronizationStatus _status = StateSynchronizationStatus.disconnected;

  /// Whether this observation capability has permanently closed.
  bool _closed = false;

  /// Returns the current infrastructure synchronization status.
  StateSynchronizationStatus get status => _status;

  /// Registers the receiving feature's delivery handler.
  ///
  /// [registry] belongs to the composing communication lifecycle.
  /// Registration must occur before its handler configuration is frozen.
  ///
  /// Registration failures propagate. No subscription is established.
  void register_handlers(RequestHandlerRegistry registry) {
    registry.register<StateDeliveryResponse, StateDeliveryRequest>(_receive);
  }

  /// Borrows an established authenticated [session].
  ///
  /// Invoked by the SDK connection owner after successful establishment.
  /// No previous subscription or cached state is revived.
  ///
  /// Connection lifecycle serialization guarantees that an older
  /// session has already been invalidated.
  void attach_session(MessageSession session) {
    _session = session;
    _session_generation = null;
    _set_status(StateSynchronizationStatus.idle);
  }

  /// Invalidates observation associated with the supplied [session].
  ///
  /// [error] and [stack_trace] describe the lost communication boundary.
  /// Outstanding local observation terminates with this failure.
  ///
  /// Notifications belonging to previously replaced sessions are ignored.
  /// Communication resources remain owned by the SDK connection owner.
  void detach_session(
    MessageSession session,
    Object error,
    StackTrace stack_trace,
  ) {
    if (!identical(_session, session)) return;

    _session = null;
    _session_generation = null;

    final binding = _binding;
    _binding = null;
    _current = null;

    // Release any initial-delivery wait without reviving the retired
    // binding when its asynchronous request eventually completes.
    binding?.signal_initial();

    if (_status != StateSynchronizationStatus.failed) {
      _set_status(StateSynchronizationStatus.disconnected);
    }

    _fail_listeners(error, stack_trace);
  }

  /// Observes verified composite application state.
  ///
  /// Returns a stream supporting independent local subscriptions.
  /// The first listener establishes the remote subscription.
  /// Additional listeners receive its latest verified state.
  ///
  /// Rapid publications may be coalesced. Paused listeners retain
  /// at most one pending value.
  ///
  /// Unavailable communication and protocol failures terminate
  /// observation with an error.
  ///
  /// Cancelling the last listener waits for remote cancellation while
  /// its session remains available.
  Stream<RudraState> observe() {
    return _LatestStream<RudraState>(
      attach: _attach_listener,
      detach: _detach_listener,
    );
  }

  /// Observes current and subsequent synchronization availability.
  ///
  /// Each listener initially receives the current status. Slow or
  /// paused listeners may coalesce intermediate status changes.
  ///
  /// The stream remains available across connection replacement and
  /// terminates when the observation capability permanently closes.
  Stream<StateSynchronizationStatus> observe_status() {
    return _LatestStream<StateSynchronizationStatus>(
      attach: (listener) {
        if (_closed) {
          listener.offer(_status);
          listener.finish();
          return;
        }

        _status_listeners.add(listener);
        listener.offer(_status);
      },
      detach: (listener) {
        _status_listeners.remove(listener);
      },
    );
  }

  /// Permanently closes local observation resources.
  ///
  /// Called by the SDK after its communication lifecycle has drained.
  /// Does not close independently owned communication resources.
  ///
  /// Pending frontend rendering and paused listeners cannot delay
  /// completion of SDK resource disposal.
  void close() {
    if (_closed) return;

    _closed = true;
    _session = null;
    _session_generation = null;

    _binding?.signal_initial();
    _binding = null;
    _current = null;

    _set_status(StateSynchronizationStatus.closed);

    _fail_listeners(
      StateError('SDK state observation has closed.'),
      StackTrace.current,
    );

    final listeners = _status_listeners.toList();
    _status_listeners.clear();

    for (final listener in listeners) {
      listener.finish();
    }
  }

  /// Admits an independent local [listener].
  ///
  /// Immediately offers retained state when synchronized.
  /// Otherwise starts observation or waits for an outstanding
  /// cancellation to drain.
  ///
  /// Unavailable observation terminates the listener with an error.
  void _attach_listener(_LatestListener<RudraState> listener) {
    if (_closed ||
        _session == null ||
        _status == StateSynchronizationStatus.failed) {
      listener.finish(
        error: StateError('SDK state observation is unavailable.'),
        stack_trace: StackTrace.current,
      );

      return;
    }

    _listeners.add(listener);

    final current = _current;

    if (current != null) {
      listener.offer(current);
    }

    _start_if_needed();
  }

  /// Removes an independent local [listener].
  ///
  /// Returns after remote cancellation when this was the final
  /// listener of an admitted subscription.
  Future<void> _detach_listener(_LatestListener<RudraState> listener) async {
    if (!_listeners.remove(listener) || _listeners.isNotEmpty) {
      return;
    }

    final binding = _binding;

    if (binding != null && !binding.retiring) {
      await _retire(binding);
    }
  }

  /// Establishes a remote subscription when local demand exists.
  ///
  /// Admission is retained before sending the subscription request,
  /// because initial delivery may precede subscription acceptance.
  void _start_if_needed() {
    final session = _session;

    if (_closed ||
        session == null ||
        _binding != null ||
        _listeners.isEmpty ||
        _status == StateSynchronizationStatus.failed) {
      return;
    }

    final binding = _RemoteSubscription(
      session: session,
      id: _identifiers.v4(),
    );

    _binding = binding;

    _set_status(StateSynchronizationStatus.synchronizing);

    binding.opening = _open(binding);
    binding.opening.ignore();
  }

  /// Establishes and validates the remote subscription [binding].
  ///
  /// Acceptance and initial delivery may arrive in either order.
  /// State becomes available only after both have been validated.
  ///
  /// A retired binding may finish establishment for the purpose of
  /// orderly cancellation without publishing its state.
  Future<void> _open(_RemoteSubscription binding) async {
    try {
      final response = await binding.session.request(
        StateSubscribeRequest(subscription_id: binding.id),
      );

      if (!identical(_binding, binding)) return;

      if (response.subscription_id != binding.id) {
        throw StateError('State subscription acceptance mismatch.');
      }

      final session_generation = _session_generation;
      final delivered_generation = binding.latest?.generation;

      if ((session_generation != null &&
              response.generation != session_generation) ||
          (delivered_generation != null &&
              response.generation != delivered_generation)) {
        throw StateError('State subscription generation mismatch.');
      }

      binding.accepted_generation = response.generation;
      _session_generation = response.generation;

      _accept_latest(binding);

      if (!binding.retiring) {
        await binding.initial.future.timeout(_initial_state_timeout);
      }
    } catch (error, stack_trace) {
      if (!identical(_binding, binding)) return;

      _fail(binding.session, error, stack_trace);

      rethrow;
    }
  }

  /// Receives one state [request] through its authenticated [session].
  ///
  /// Validates session identity, subscription identity, generation and
  /// publication ordering before acknowledging the exact position.
  ///
  /// Valid deliveries received during cancellation are acknowledged
  /// without making their state available to local observers.
  ///
  /// Invalid delivery terminates the affected session and propagates
  /// the protocol failure to communication.
  StateDeliveryResponse _receive(
    StateDeliveryRequest request,
    MessageSession session,
  ) {
    try {
      final binding = _binding;

      if (!identical(_session, session) ||
          binding == null ||
          !identical(binding.session, session) ||
          binding.id != request.subscription_id) {
        throw StateError('Unexpected state subscription delivery.');
      }

      final publication = request.publication;
      final previous = binding.latest;
      final last_position = _last_position;

      final expected_generation =
          binding.accepted_generation ??
          _session_generation ??
          previous?.generation;

      if (expected_generation != null &&
          publication.generation != expected_generation) {
        throw StateError('Unexpected state publication generation.');
      }

      if (previous != null && publication.revision <= previous.revision) {
        throw StateError('State publication revision did not advance.');
      }

      // A new subscription may receive the same latest publication,
      // but cannot move backward within an already observed generation.
      if (previous == null &&
          last_position != null &&
          publication.generation == last_position.generation &&
          publication.revision < last_position.revision) {
        throw StateError('State publication position regressed.');
      }

      binding.latest = publication;

      _accept_latest(binding);

      binding.signal_initial();

      return StateDeliveryResponse(
        subscription_id: binding.id,
        generation: publication.generation,
        revision: publication.revision,
      );
    } catch (error, stack_trace) {
      _fail(session, error, stack_trace);

      rethrow;
    }
  }

  /// Accepts the latest delivered publication for [binding].
  ///
  /// Publication requires matching subscription acceptance.
  /// Ordering metadata remains available across connection replacement.
  ///
  /// Retiring subscriptions never publish state to local listeners.
  void _accept_latest(_RemoteSubscription binding) {
    final publication = binding.latest;
    final generation = binding.accepted_generation;

    if (publication == null || generation == null) return;

    if (publication.generation != generation) {
      throw StateError('Accepted state generation mismatch.');
    }

    _last_position = (
      generation: publication.generation,
      revision: publication.revision,
    );

    if (binding.retiring) return;

    _current = publication.state;

    _set_status(StateSynchronizationStatus.synchronized);

    for (final listener in _listeners) {
      listener.offer(publication.state);
    }
  }

  /// Retires the remote subscription associated with [binding].
  ///
  /// Stops local state acceptance immediately, waits for establishment
  /// when necessary and sends cancellation through the original session.
  ///
  /// Returns after remote cancellation has been confirmed or the
  /// original session has been invalidated.
  ///
  /// New listeners wait for this admission slot to be released.
  /// Cancellation protocol failures propagate.
  Future<void> _retire(_RemoteSubscription binding) async {
    binding.retiring = true;
    _current = null;

    _set_status(StateSynchronizationStatus.cancelling);

    // Cancellation need not wait for initial state after acceptance.
    binding.signal_initial();

    try {
      await binding.opening;

      if (!identical(_binding, binding)) return;

      final response = await binding.session.request(
        StateUnsubscribeRequest(subscription_id: binding.id),
      );

      if (!identical(_binding, binding)) return;

      if (response.subscription_id != binding.id) {
        throw StateError('State subscription cancellation mismatch.');
      }

      _binding = null;

      _set_status(StateSynchronizationStatus.idle);

      // Local demand may have returned while cancellation was draining.
      _start_if_needed();
    } catch (error, stack_trace) {
      if (!identical(_binding, binding)) return;

      _fail(binding.session, error, stack_trace);

      rethrow;
    }
  }

  /// Invalidates observation following failure on [session].
  ///
  /// Only the current session can invalidate its local listeners.
  /// Session termination is initiated without awaiting the owning
  /// communication lifecycle from inside a request handler.
  void _fail(MessageSession session, Object error, StackTrace stack_trace) {
    if (identical(_session, session)) {
      final binding = _binding;

      _binding = null;
      _current = null;

      binding?.signal_initial();

      _set_status(StateSynchronizationStatus.failed);

      _fail_listeners(error, stack_trace);
    }

    // Invalid protocol traffic also terminates a stale originating
    // session without affecting a newer authenticated connection.
    Future<void>.sync(session.close).ignore();
  }

  /// Terminates every retained state listener with [error].
  ///
  /// Ownership is released immediately, independently of paused
  /// frontend delivery.
  void _fail_listeners(Object error, StackTrace stack_trace) {
    final listeners = _listeners.toList();

    _listeners.clear();

    for (final listener in listeners) {
      listener.finish(error: error, stack_trace: stack_trace);
    }
  }

  /// Publishes a changed synchronization [status] to local listeners.
  ///
  /// Repeated values are suppressed.
  void _set_status(StateSynchronizationStatus status) {
    if (_status == status) return;

    _status = status;

    for (final listener in _status_listeners) {
      listener.offer(status);
    }
  }
}

/// Retains protocol state for one admitted remote subscription.
///
/// Example:
/// ```dart
/// final binding = _RemoteSubscription(
///   session: session,
///   id: 'subscription-1',
/// );
/// ```
final class _RemoteSubscription {
  /// Associates the borrowed [session] with a distinct subscription [id].
  _RemoteSubscription({required this.session, required this.id});

  /// Original authenticated session for every subscription request.
  final MessageSession session;

  /// Connection-scoped identity of the remote subscription.
  final String id;

  /// Completion of subscription establishment.
  late final Future<void> opening;

  /// Generation confirmed by the host's acceptance response.
  String? accepted_generation;

  /// Latest validated delivery, including during establishment.
  StatePublicationSnapshot? latest;

  /// Whether local observation has retired this subscription.
  bool retiring = false;

  /// Initial-delivery or retirement notification.
  final Completer<void> initial = Completer<void>();

  /// Releases the initial-delivery wait.
  ///
  /// Repeated notifications have no additional effect.
  void signal_initial() {
    if (!initial.isCompleted) {
      initial.complete();
    }
  }
}

/// Creates independent bounded listeners for an observable value.
///
/// Each call to [listen] owns an independent stream controller and
/// pending-value slot.
///
/// Example:
/// ```dart
/// final stream = _LatestStream<RudraState>(
///   attach: register_listener,
///   detach: remove_listener,
/// );
///
/// final first = stream.listen(render_header);
/// final second = stream.listen(render_sidebar);
/// ```
final class _LatestStream<T extends Object> extends Stream<T> {
  /// Creates a stream using the supplied listener lifecycle callbacks.
  ///
  /// [attach] admits an independent listener.
  /// [detach] releases it and may await remote cancellation.
  _LatestStream({
    required void Function(_LatestListener<T>) attach,
    required FutureOr<void> Function(_LatestListener<T>) detach,
  }) : _attach = attach,
       _detach = detach;

  /// Local listener admission capability.
  final void Function(_LatestListener<T>) _attach;

  /// Local listener removal and optional cancellation capability.
  final FutureOr<void> Function(_LatestListener<T>) _detach;

  /// Whether this stream supports independent subscriptions.
  @override
  bool get isBroadcast => true;

  /// Establishes an independent subscription to this observable.
  ///
  /// [onData], [onError], [onDone] and [cancelOnError] follow
  /// the standard Dart stream-listener contract.
  ///
  /// Returns the subscription controlling this listener's delivery,
  /// pausing and cancellation.
  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final controller = StreamController<T>(sync: true);
    final listener = _LatestListener<T>(controller);

    controller.onListen = () {
      try {
        _attach(listener);
      } catch (error, stack_trace) {
        listener.finish(error: error, stack_trace: stack_trace);
      }
    };

    controller.onResume = listener.resume;

    controller.onCancel = () {
      listener.cancel();

      return _detach(listener);
    };

    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

/// Maintains bounded delivery for one local stream listener.
///
/// Offers replace the pending value rather than queueing historical
/// values inside a paused Dart stream.
///
/// Example:
/// ```dart
/// final listener = _LatestListener<RudraState>(controller);
///
/// listener.offer(first_state);
/// listener.offer(latest_state);
/// ```
final class _LatestListener<T extends Object> {
  /// Retains the independently owned [controller].
  _LatestListener(this._controller);

  /// Controller responsible for one local stream subscription.
  final StreamController<T> _controller;

  /// Latest value awaiting local delivery.
  T? _pending;

  /// Whether a delivery microtask is already scheduled.
  bool _scheduled = false;

  /// Whether terminal delivery has been requested.
  bool _finished = false;

  /// Whether the frontend subscription has been cancelled.
  bool _cancelled = false;

  /// Offers [value], replacing any previously pending value.
  ///
  /// Does not invoke frontend callbacks synchronously.
  /// Finished or cancelled listeners ignore subsequent offers.
  void offer(T value) {
    if (_finished || _cancelled) return;

    _pending = value;

    _schedule();
  }

  /// Schedules delivery after the frontend resumes its subscription.
  void resume() => _schedule();

  /// Cancels pending delivery immediately.
  ///
  /// Repeated cancellation has no additional effect.
  void cancel() {
    _cancelled = true;
    _pending = null;
  }

  /// Terminates this listener.
  ///
  /// [error] and [stack_trace] optionally describe terminal failure.
  ///
  /// Failed observation discards pending state. Normal completion may
  /// deliver its final pending value before closing.
  ///
  /// Terminal delivery is scheduled independently of the caller,
  /// preventing reentrant frontend callbacks during SDK lifecycle
  /// coordination.
  void finish({Object? error, StackTrace? stack_trace}) {
    if (_finished || _cancelled) return;

    _finished = true;

    final pending = error == null ? _pending : null;
    _pending = null;

    scheduleMicrotask(() {
      if (_cancelled) return;

      if (error != null) {
        _controller.addError(error, stack_trace);
      } else if (pending != null) {
        _controller.add(pending);
      }

      // A paused listener may defer receipt of the terminal
      // notification, but cannot delay SDK resource disposal.
      _controller.close().ignore();
    });
  }

  /// Schedules at most one pending delivery microtask.
  ///
  /// Paused subscriptions receive no ordinary stream events until
  /// resumed, keeping their retained state bounded.
  void _schedule() {
    if (_scheduled ||
        _finished ||
        _cancelled ||
        _controller.isPaused ||
        _pending == null) {
      return;
    }

    _scheduled = true;

    scheduleMicrotask(() {
      _scheduled = false;

      if (_finished || _cancelled || _controller.isPaused) {
        return;
      }

      final pending = _pending;
      _pending = null;

      if (pending != null) {
        _controller.add(pending);
      }
    });
  }
}
