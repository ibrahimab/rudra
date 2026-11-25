import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_communication/src/sessions/pending_requests.dart';
import 'package:test/test.dart';

/// Verifies outgoing correlation, response validation,
/// capacity enforcement and deadline ownership.
void main() {
  late PendingRequests pending;

  setUp(() {
    pending = PendingRequests(
      on_timeout: () {
        fail('Unexpected request deadline expiration.');
      },
    );
  });

  tearDown(() {
    pending.close(
      const MessageSessionException(MessageSessionErrorCode.session_closed),
    );
  });

  test('allocates increasing session-local identifiers', () async {
    final first = pending.register<_EchoResponse>(
      expected_response_type: _EchoResponse,
    );

    final second = pending.register<_EchoResponse>(
      expected_response_type: _EchoResponse,
    );

    expect(first.request_id, '1');
    expect(second.request_id, '2');
    expect(pending.count, 2);

    pending.complete_response(first.request_id, const _EchoResponse('first'));

    pending.complete_response(second.request_id, const _EchoResponse('second'));

    expect((await first.response).value, 'first');
    expect((await second.response).value, 'second');
    expect(pending.count, 0);
  });

  test('correlates responses arriving out of request order', () async {
    final first = pending.register<_EchoResponse>(
      expected_response_type: _EchoResponse,
    );

    final second = pending.register<_EchoResponse>(
      expected_response_type: _EchoResponse,
    );

    pending.complete_response(second.request_id, const _EchoResponse('second'));

    expect((await second.response).value, 'second');
    expect(pending.count, 1);

    pending.complete_response(first.request_id, const _EchoResponse('first'));

    expect((await first.response).value, 'first');
    expect(pending.count, 0);
  });

  test('rejects an unknown response identifier', () {
    expect(
      () => pending.complete_response('1', const _EchoResponse('unknown')),
      throwsA(
        isA<ProtocolException>().having(
          (error) => error.code,
          'code',
          ProtocolErrorCode.invalid_correlation,
        ),
      ),
    );
  });

  test('rejects a duplicate response identifier', () async {
    final request = pending.register<_EchoResponse>(
      expected_response_type: _EchoResponse,
    );

    const response = _EchoResponse('Hello');

    pending.complete_response(request.request_id, response);

    expect(await request.response, same(response));

    expect(
      () => pending.complete_response(request.request_id, response),
      throwsA(
        isA<ProtocolException>().having(
          (error) => error.code,
          'code',
          ProtocolErrorCode.invalid_correlation,
        ),
      ),
    );
  });

  test('rejects incompatible concrete response types', () async {
    // Widen the caller-facing type while retaining the exact
    // concrete response required by codec configuration.
    final request = pending.register<Response>(
      expected_response_type: _EchoResponse,
    );

    expect(
      () =>
          pending.complete_response(request.request_id, const _OtherResponse()),
      throwsA(
        isA<ProtocolException>().having(
          (error) => error.code,
          'code',
          ProtocolErrorCode.invalid_message,
        ),
      ),
    );

    expect(pending.count, 1);

    const expected = _EchoResponse('Hello');

    pending.complete_response(request.request_id, expected);

    expect(await request.response, same(expected));
  });

  test('completes sanitized remote failures independently', () async {
    final first = pending.register<_EchoResponse>(
      expected_response_type: _EchoResponse,
    );

    final second = pending.register<_EchoResponse>(
      expected_response_type: _EchoResponse,
    );

    const failure = MessageSessionException(
      MessageSessionErrorCode.handler_failed,
    );

    final failed = expectLater(first.response, throwsA(same(failure)));

    pending.complete_failure(first.request_id, failure);

    await failed;

    expect(pending.count, 1);

    const response = _EchoResponse('Hello');

    pending.complete_response(second.request_id, response);

    expect(await second.response, same(response));
    expect(pending.count, 0);
  });

  test('rejects an unsolicited remote failure', () {
    expect(
      () => pending.complete_failure(
        '1',
        const MessageSessionException(MessageSessionErrorCode.handler_failed),
      ),
      throwsA(
        isA<ProtocolException>().having(
          (error) => error.code,
          'code',
          ProtocolErrorCode.invalid_correlation,
        ),
      ),
    );
  });

  test('releases a locally failed request registration', () async {
    final request = pending.register<_EchoResponse>(
      expected_response_type: _EchoResponse,
    );

    final failure = StateError('Controlled submission failure.');

    final failed = expectLater(request.response, throwsA(same(failure)));

    pending.fail_local(request.request_id, failure);

    await failed;

    expect(pending.count, 0);

    // Local failure cleanup remains safe after completion.
    pending.fail_local(request.request_id, failure);

    final next = pending.register<_EchoResponse>(
      expected_response_type: _EchoResponse,
    );

    expect(next.request_id, '2');
  });

  test('enforces capacity and recovers completed capacity', () async {
    pending = PendingRequests(
      maximum_pending: 1,
      on_timeout: () {
        fail('Unexpected request deadline expiration.');
      },
    );

    final first = pending.register<_EchoResponse>(
      expected_response_type: _EchoResponse,
    );

    expect(
      () => pending.register<_EchoResponse>(
        expected_response_type: _EchoResponse,
      ),
      throwsA(
        isA<MessageSessionException>().having(
          (error) => error.code,
          'code',
          MessageSessionErrorCode.capacity_exceeded,
        ),
      ),
    );

    const response = _EchoResponse('Hello');

    pending.complete_response(first.request_id, response);

    expect(await first.response, same(response));

    final second = pending.register<_EchoResponse>(
      expected_response_type: _EchoResponse,
    );

    expect(second.request_id, '2');
    expect(pending.count, 1);
  });

  test('termination fails all outstanding requests', () async {
    final first = pending.register<_EchoResponse>(
      expected_response_type: _EchoResponse,
    );

    final second = pending.register<_EchoResponse>(
      expected_response_type: _EchoResponse,
    );

    const failure = MessageSessionException(
      MessageSessionErrorCode.session_closed,
    );

    final first_failed = expectLater(first.response, throwsA(same(failure)));

    final second_failed = expectLater(second.response, throwsA(same(failure)));

    pending.close(failure);
    pending.close(failure);

    await Future.wait([first_failed, second_failed]);

    expect(pending.count, 0);

    expect(
      () => pending.register<_EchoResponse>(
        expected_response_type: _EchoResponse,
      ),
      throwsA(
        isA<MessageSessionException>().having(
          (error) => error.code,
          'code',
          MessageSessionErrorCode.session_closed,
        ),
      ),
    );
  });

  test('expiration completes the request and notifies its owner', () async {
    final expired = Completer<void>();

    late _ControlledTimer deadline;

    pending = runZoned(
      () => PendingRequests(on_timeout: expired.complete),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          deadline = _ControlledTimer(callback);
          return deadline;
        },
      ),
    );

    final request = runZoned(
      () => pending.register<_EchoResponse>(
        expected_response_type: _EchoResponse,
      ),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          deadline = _ControlledTimer(callback);
          return deadline;
        },
      ),
    );

    final failed = expectLater(
      request.response,
      throwsA(
        isA<MessageSessionException>().having(
          (error) => error.code,
          'code',
          MessageSessionErrorCode.request_timeout,
        ),
      ),
    );

    deadline.fire();

    await expired.future;
    await failed;

    expect(pending.count, 0);
    expect(deadline.isActive, isFalse);
  });

  test('successful completion cancels its deadline', () async {
    late _ControlledTimer deadline;

    final request = runZoned(
      () => pending.register<_EchoResponse>(
        expected_response_type: _EchoResponse,
      ),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          deadline = _ControlledTimer(callback);
          return deadline;
        },
      ),
    );

    const response = _EchoResponse('Hello');

    pending.complete_response(request.request_id, response);

    expect(await request.response, same(response));
    expect(deadline.isActive, isFalse);

    deadline.fire();

    expect(pending.count, 0);
  });

  test('rejects invalid capacity and deadline configuration', () {
    expect(
      () => PendingRequests(maximum_pending: 0, on_timeout: () {}),
      throwsArgumentError,
    );

    expect(
      () => PendingRequests(request_timeout: Duration.zero, on_timeout: () {}),
      throwsArgumentError,
    );
  });
}

/// Synthetic application response carrying an arbitrary value.
///
/// Example:
/// ```dart
/// const response = _EchoResponse('Hello');
/// ```
final class _EchoResponse implements Response {
  /// Creates a response containing [value].
  const _EchoResponse(this.value);

  /// Synthetic application result.
  final String value;
}

/// Independent response used to verify concrete type validation.
///
/// Example:
/// ```dart
/// const response = _OtherResponse();
/// ```
final class _OtherResponse implements Response {
  /// Creates an empty synthetic response.
  const _OtherResponse();
}

/// Supplies a manually triggered one-shot deadline timer.
///
/// Allows deadline behavior to be verified independently of
/// wall-clock scheduling.
///
/// Example:
/// ```dart
/// final timer = _ControlledTimer(handle_expiration);
/// timer.fire();
/// ```
final class _ControlledTimer implements Timer {
  /// Creates an active timer retaining [callback].
  _ControlledTimer(this._callback);

  /// Callback executed on controlled expiration.
  final void Function() _callback;

  /// Whether the timer remains eligible for expiration.
  bool _active = true;

  /// Number of times this one-shot timer has expired.
  int _tick = 0;

  /// Whether this timer remains active.
  @override
  bool get isActive => _active;

  /// Number of completed timer ticks.
  @override
  int get tick => _tick;

  /// Prevents subsequent expiration.
  @override
  void cancel() {
    _active = false;
  }

  /// Expires the timer once if it remains active.
  void fire() {
    if (!_active) {
      return;
    }

    _active = false;
    _tick++;

    _callback();
  }
}
