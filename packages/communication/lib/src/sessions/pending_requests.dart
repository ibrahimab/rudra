import 'dart:async';

import '../messaging/message.dart';
import '../messaging/protocol/protocol_exception.dart';
import 'message_session_exception.dart';

/// Maintains outstanding outgoing requests for one message session.
///
/// Owns correlation identifiers, response completion and deadline
/// timers. Requests are removed when completed or terminated.
///
/// Example:
/// ```dart
/// final pending = PendingRequests(
///   on_timeout: handle_timeout,
/// );
///
/// final request = pending.register<EchoResponse>(
///   expected_response_type: EchoResponse,
/// );
///
/// pending.complete_response(
///   request.request_id,
///   const EchoResponse('Hello'),
/// );
///
/// final response = await request.response;
/// ```
final class PendingRequests {
  /// Creates an empty pending request coordinator.
  ///
  /// [on_timeout] notifies the owning session that a request deadline
  /// has expired. The owner must terminate communication in response.
  ///
  /// [maximum_pending] limits outstanding request registrations.
  /// [request_timeout] defines the deadline from registration.
  ///
  /// Throws [ArgumentError] for non-positive limits or deadlines.
  PendingRequests({
    required void Function() on_timeout,
    this.maximum_pending = default_maximum_pending,
    this.request_timeout = default_request_timeout,
  }) : _on_timeout = on_timeout {
    if (maximum_pending <= 0) {
      throw ArgumentError.value(
        maximum_pending,
        'maximum_pending',
        'Pending request capacity must be positive.',
      );
    }

    if (request_timeout <= Duration.zero) {
      throw ArgumentError.value(
        request_timeout,
        'request_timeout',
        'Request deadline must be positive.',
      );
    }
  }

  /// Default maximum number of outstanding outgoing requests.
  static const int default_maximum_pending = 32;

  /// Default deadline for an outgoing communication request.
  static const Duration default_request_timeout = Duration(seconds: 30);

  /// Maximum identifier supported by the version 1 envelope.
  static final BigInt _maximum_request_id = BigInt.parse(
    '99999999999999999999',
  );

  /// Maximum outstanding registrations maintained by this coordinator.
  final int maximum_pending;

  /// Deadline applied to newly registered requests.
  final Duration request_timeout;

  /// Notifies the session owner of an expired request.
  final void Function() _on_timeout;

  /// Outstanding requests indexed by their session-local identifiers.
  final Map<String, _PendingRequest> _pending = {};

  /// Last allocated identifier in this initiating direction.
  BigInt _last_request_id = BigInt.zero;

  /// Whether registration has been permanently terminated.
  bool _is_closed = false;

  /// Number of outstanding request registrations.
  int get count => _pending.length;

  /// Registers a request expecting the supplied concrete response type.
  ///
  /// [R] identifies the response type expected by the caller.
  /// [expected_response_type] identifies the exact response type
  /// recorded in the frozen message codec configuration.
  ///
  /// Returns a unique request identifier and typed response future.
  /// Starts the request deadline immediately.
  ///
  /// Throws [MessageSessionException] after termination or when
  /// outstanding request capacity has been exhausted.
  ///
  /// Throws [StateError] if the identifier space is exhausted.
  ({String request_id, Future<R> response}) register<R extends Response>({
    required Type expected_response_type,
  }) {
    if (_is_closed) {
      throw const MessageSessionException(
        MessageSessionErrorCode.session_closed,
      );
    }

    if (_pending.length >= maximum_pending) {
      throw const MessageSessionException(
        MessageSessionErrorCode.capacity_exceeded,
      );
    }

    if (_last_request_id >= _maximum_request_id) {
      throw StateError('Communication request identifiers exhausted.');
    }

    _last_request_id += BigInt.one;

    final request_id = _last_request_id.toString();
    final completion = Completer<Response>();

    // Attach an observer immediately. Session termination may occur
    // before the owning caller receives the response future.
    final response = completion.future.then<R>((response) => response as R);

    response.ignore();

    final deadline = Timer(request_timeout, () => _expire(request_id));

    _pending[request_id] = _PendingRequest(
      expected_response_type: expected_response_type,
      accepts_response: (response) => response is R,
      completion: completion,
      deadline: deadline,
    );

    return (request_id: request_id, response: response);
  }

  /// Resolves [request_id] with the supplied application [response].
  ///
  /// Validates the exact concrete response type before removing
  /// the pending registration and completing its response future.
  ///
  /// Throws [ProtocolException] for an unknown identifier or
  /// an incompatible response type.
  ///
  /// Invalid responses leave the request pending so that the owner
  /// can terminate all outstanding requests consistently.
  void complete_response(String request_id, Response response) {
    final pending = _require_pending(request_id);

    if (response.runtimeType != pending.expected_response_type ||
        response is Request<Response> ||
        !pending.accepts_response(response)) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_message,
        'Response violates the registered message contract.',
      );
    }

    _remove(request_id);

    pending.completion.complete(response);
  }

  /// Resolves [request_id] with a sanitized remote [failure].
  ///
  /// Removes the registration and cancels its deadline.
  /// Throws [ProtocolException] for an unknown request identifier.
  void complete_failure(String request_id, MessageSessionException failure) {
    final pending = _require_pending(request_id);

    _remove(request_id);

    pending.completion.completeError(failure);
  }

  /// Terminates a locally registered request with [failure].
  ///
  /// [request_id] identifies the registration to release.
  /// [stack] optionally preserves its local failure stack.
  ///
  /// Returns without effect if the request has already completed.
  /// This operation supports local submission failures and must
  /// not be used to accept unsolicited incoming responses.
  void fail_local(String request_id, Object failure, [StackTrace? stack]) {
    final pending = _remove(request_id);

    pending?.completion.completeError(failure, stack);
  }

  /// Permanently terminates registration and fails outstanding requests.
  ///
  /// [failure] supplies the termination cause.
  /// [stack] optionally preserves its local diagnostic stack.
  ///
  /// Cancels every outstanding deadline and releases all registrations.
  /// Repeated calls have no additional effect.
  void close(Object failure, [StackTrace? stack]) {
    if (_is_closed) {
      return;
    }

    _is_closed = true;

    final outstanding = _pending.values.toList(growable: false);

    _pending.clear();

    for (final pending in outstanding) {
      pending.deadline.cancel();
      pending.completion.completeError(failure, stack);
    }
  }

  /// Resolves an outstanding registration for [request_id].
  ///
  /// Throws [ProtocolException] for unknown or completed identifiers.
  _PendingRequest _require_pending(String request_id) {
    final pending = _pending[request_id];

    if (pending == null) {
      throw const ProtocolException(
        ProtocolErrorCode.invalid_correlation,
        'Response does not identify an outstanding request.',
      );
    }

    return pending;
  }

  /// Removes [request_id] and cancels its deadline timer.
  ///
  /// Returns the released registration, or null if already absent.
  _PendingRequest? _remove(String request_id) {
    final pending = _pending.remove(request_id);

    pending?.deadline.cancel();

    return pending;
  }

  /// Handles expiration of the deadline for [request_id].
  ///
  /// Completes the expired request and notifies the session owner.
  /// Expiration does not imply remote application cancellation.
  void _expire(String request_id) {
    final pending = _remove(request_id);

    if (pending == null) {
      return;
    }

    pending.completion.completeError(
      const MessageSessionException(MessageSessionErrorCode.request_timeout),
    );

    _on_timeout();
  }
}

/// Retains the completion state of one outstanding request.
///
/// Owned exclusively by its pending request coordinator.
final class _PendingRequest {
  /// Creates a registration containing its response contract,
  /// [completion] and associated [deadline] timer.
  ///
  /// [expected_response_type] identifies the exact response type
  /// permitted to complete this registration.
  ///
  /// [accepts_response] validates the caller's generic response
  /// contract independently of the configured concrete type.
  const _PendingRequest({
    required this.expected_response_type,
    required this.accepts_response,
    required this.completion,
    required this.deadline,
  });

  /// Concrete application response type expected by this request.
  final Type expected_response_type;

  /// Runtime validation of the caller's generic response contract.
  final bool Function(Response) accepts_response;

  /// Completion source for the outstanding application response.
  final Completer<Response> completion;

  /// Deadline timer owned by this registration.
  final Timer deadline;
}
