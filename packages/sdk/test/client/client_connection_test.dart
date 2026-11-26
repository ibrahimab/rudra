import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/client/client_connection.dart';
import 'package:test/test.dart';

/// Verifies connection ownership across independent communication lifecycles.
///
/// Uses actual SDK messaging configuration and controlled communication
/// completion boundaries without depending on native transport scheduling.
void main() {
  late ClientConnection connection;
  late List<_TestCommunication> created;
  late _TestTransport configured_transport;

  late int resolution_count;

  Object? next_resolution_error;
  Object? next_connection_error;

  setUp(() {
    created = [];
    resolution_count = 0;

    configured_transport = const _TestTransport(os_user_id: 'trusted-owner');

    next_resolution_error = null;
    next_connection_error = null;

    connection = ClientConnection(
      setup: () {
        resolution_count++;

        final error = next_resolution_error;

        if (error != null) {
          throw error;
        }

        return configured_transport;
      },
      runtime: WorkflowRuntime.standard(),
      communication_factory:
          ({required transport, required codecs, required handlers}) {
            expect(codecs.is_frozen, isTrue);
            expect(handlers.is_frozen, isTrue);
            expect(transport, same(configured_transport));

            final communication = _TestCommunication(
              transport: transport as _TestTransport,
              connection_error: next_connection_error,
            );

            created.add(communication);

            return communication;
          },
    );
  });

  tearDown(() async {
    if (created.any((communication) => communication.fail_disposal)) {
      await expectLater(connection.close(), throwsStateError);
    } else {
      await connection.close();
    }
  });

  test('construction acquires no communication resources', () {
    expect(resolution_count, 0);
    expect(created, isEmpty);

    expect(connection.is_connected, isFalse);
    expect(connection.resources_released, isTrue);
  });

  test('establishes a connection using the resolved transport', () async {
    await connection.connect();

    expect(resolution_count, 1);
    expect(created, hasLength(1));

    final communication = created.single;

    expect(communication.transport, same(configured_transport));
    expect(communication.session.os_user_id, configured_transport.os_user_id);
    expect(connection.is_connected, isTrue);
    expect(connection.resources_released, isFalse);

    await expectLater(connection.connect(), throwsStateError);

    expect(created, hasLength(1));
    expect(resolution_count, 1);
  });

  test(
    'failed transport resolution acquires no communication resources',
    () async {
      final failure = StateError('Configured transport could not be resolved.');

      next_resolution_error = failure;

      await expectLater(connection.connect(), throwsA(same(failure)));

      expect(resolution_count, 1);
      expect(created, isEmpty);
      expect(connection.is_connected, isFalse);
      expect(connection.resources_released, isTrue);

      next_resolution_error = null;

      await connection.connect();

      expect(resolution_count, 2);
      expect(created, hasLength(1));
      expect(created.single.transport, same(configured_transport));
      expect(connection.is_connected, isTrue);
    },
  );

  test('resolves a configured transport again during replacement', () async {
    await connection.connect();

    final previous = created.single;
    final original_transport = configured_transport;

    configured_transport = const _TestTransport(
      os_user_id: 'replacement-owner',
    );

    await connection.reconnect();

    expect(resolution_count, 2);
    expect(created, hasLength(2));

    expect(previous.session.is_closed, isTrue);
    expect(previous.resources_released, isTrue);

    expect(previous.transport, same(original_transport));
    expect(created.last.transport, same(configured_transport));

    expect(created.last.transport, isNot(same(original_transport)));

    expect(created.last.session, isNot(same(previous.session)));

    expect(created.last.session.os_user_id, 'replacement-owner');

    expect(connection.is_connected, isTrue);
  });

  test('replacement waits for admitted-handler draining', () async {
    await connection.connect();

    final previous = created.single;
    final barrier = previous.hold_drain();

    final replacement = connection.reconnect();

    replacement.ignore();

    try {
      await previous.session.done;

      expect(connection.is_connected, isFalse);
      expect(connection.resources_released, isFalse);

      // Endpoint resolution and communication construction cannot
      // begin while the previous lifecycle retains resources.
      expect(created, hasLength(1));
      expect(resolution_count, 1);

      await expectLater(connection.connect(), throwsStateError);
      await expectLater(connection.close(), throwsStateError);

      await expectLater(
        connection.request(const StateReadRequest()),
        throwsStateError,
      );
    } finally {
      barrier.complete();
    }

    await replacement;

    expect(created, hasLength(2));
    expect(previous.resources_released, isTrue);
    expect(connection.is_connected, isTrue);
  });

  test('failed establishment releases owned resources', () async {
    final failure = StateError('Host unavailable.');

    next_connection_error = failure;

    await expectLater(connection.connect(), throwsA(same(failure)));

    expect(connection.is_connected, isFalse);
    expect(connection.resources_released, isTrue);

    expect(created, hasLength(1));
    expect(created.single.resources_released, isTrue);

    next_connection_error = null;

    await connection.connect();

    expect(created, hasLength(2));
    expect(connection.is_connected, isTrue);
  });

  test(
    'authentication failure prevents application request admission',
    () async {
      final failure = StateError('Transport peer authentication failed.');

      next_connection_error = failure;

      await expectLater(connection.connect(), throwsA(same(failure)));

      expect(created, hasLength(1));
      expect(connection.resources_released, isTrue);
      expect(connection.is_connected, isFalse);

      await expectLater(
        connection.request(const StateReadRequest()),
        throwsStateError,
      );

      expect(created.single.session.request_count, 0);
    },
  );

  test(
    'remote termination invalidates application request admission',
    () async {
      await connection.connect();

      final previous = created.single;

      await previous.session.close();
      await previous.done;

      expect(connection.is_connected, isFalse);

      await expectLater(
        connection.request(const StateReadRequest()),
        throwsStateError,
      );

      await connection.reconnect();

      expect(created, hasLength(2));
      expect(connection.is_connected, isTrue);
    },
  );

  test(
    'terminal communication failure permits replacement after disposal',
    () async {
      await connection.connect();

      final previous = created.single;
      final failure = StateError('Transport failed.');

      final termination = expectLater(previous.done, throwsA(same(failure)));

      previous.session.fail(failure);

      await termination;

      expect(connection.is_connected, isFalse);
      expect(connection.resources_released, isTrue);

      await connection.reconnect();

      expect(created, hasLength(2));
      expect(connection.is_connected, isTrue);
    },
  );

  test('unconfirmed disposal prevents replacement communication', () async {
    await connection.connect();

    final previous = created.single;

    previous.fail_disposal = true;

    await expectLater(connection.reconnect(), throwsStateError);

    expect(connection.is_connected, isFalse);
    expect(connection.resources_released, isFalse);

    expect(created, hasLength(1));
    expect(resolution_count, 1);

    await expectLater(connection.connect(), throwsStateError);

    expect(created, hasLength(1));
  });

  test('forwards typed requests through the current connection', () async {
    await connection.connect();

    final response = await connection.request(const StateReadRequest());

    expect(response.state.workflows.current_workflow, isNull);
    expect(created.single.session.request_count, 1);
  });

  test('session-bound requests cannot execute through a replacement', () async {
    await connection.connect();

    final original = connection.require_session();

    await connection.reconnect();

    final replacement = connection.require_session();

    expect(replacement, isNot(same(original)));

    await expectLater(
      connection.request(const StateReadRequest(), session: original),
      throwsStateError,
    );

    expect(created.first.session.request_count, 0);
    expect(created.last.session.request_count, 0);

    final response = await connection.request(
      const StateReadRequest(),
      session: replacement,
    );

    expect(response.state.workflows.current_workflow, isNull);
    expect(created.last.session.request_count, 1);
  });

  test(
    'does not implicitly repeat unsuccessful application requests',
    () async {
      await connection.connect();

      final previous = created.single;
      final failure = StateError('Application request failed.');

      previous.session.request_error = failure;

      await expectLater(
        connection.request(const StateReadRequest()),
        throwsA(same(failure)),
      );

      expect(previous.session.request_count, 1);
      expect(created, hasLength(1));

      await connection.reconnect();

      expect(previous.session.request_count, 1);
      expect(created.last.session.request_count, 0);
    },
  );

  test(
    'closing releases communication and permanently ends connectivity',
    () async {
      await connection.connect();

      final previous = created.single;

      await connection.close();

      expect(previous.resources_released, isTrue);
      expect(connection.resources_released, isTrue);
      expect(connection.is_connected, isFalse);

      await connection.close();

      await expectLater(connection.connect(), throwsStateError);
      await expectLater(connection.reconnect(), throwsStateError);

      await expectLater(
        connection.request(const StateReadRequest()),
        throwsStateError,
      );

      expect(created, hasLength(1));
    },
  );
}

/// Retains synthetic authenticated connectivity configuration.
///
/// Communication lifecycle tests substitute actual endpoint
/// establishment with controlled message session execution.
///
/// Example:
/// ```dart
/// const transport = _TestTransport(
///   os_user_id: 'trusted-owner',
/// );
/// ```
final class _TestTransport implements Transport {
  /// Creates a configured inactive test transport.
  ///
  /// [os_user_id] identifies the synthetic authenticated peer.
  const _TestTransport({required this.os_user_id});

  /// Trusted synthetic peer identity.
  final String os_user_id;

  /// Rejects listening endpoint execution in this fixture.
  @override
  Future<TransportListener> listen() async {
    throw UnsupportedError('Unexpected fixture listener establishment.');
  }

  /// Rejects direct transport execution in this fixture.
  @override
  Future<TransportConnection> connect() async {
    throw UnsupportedError('Unexpected fixture connection establishment.');
  }
}

/// Supplies controlled communication completion for lifecycle tests.
///
/// Session termination and admitted-handler draining can complete
/// independently.
///
/// Example:
/// ```dart
/// final communication = _TestCommunication(
///   transport: const _TestTransport(
///     os_user_id: 'trusted-owner',
///   ),
/// );
///
/// final barrier = communication.hold_drain();
/// barrier.complete();
/// ```
final class _TestCommunication implements Communication {
  /// Creates a controlled communication lifecycle.
  ///
  /// [transport] supplies the retained synthetic authenticated
  /// connectivity configuration.
  ///
  /// [connection_error] optionally prevents session establishment.
  _TestCommunication({required this.transport, this.connection_error})
    : session = _TestSession(transport.os_user_id) {
    _completion.future.ignore();
  }

  /// Configured transport retained by this communication lifecycle.
  final _TestTransport transport;

  /// Controlled authenticated message session.
  final _TestSession session;

  /// Optional failure during connection establishment.
  final Object? connection_error;

  /// Whether execution has started.
  bool _started = false;

  /// Whether resource disposal should fail.
  bool fail_disposal = false;

  /// Optional barrier separating session closure from handler draining.
  Completer<void>? _drain_barrier;

  /// Completion of the full communication lifecycle.
  final Completer<void> _completion = Completer<void>();

  /// Whether communication resource disposal has been confirmed.
  @override
  bool get resources_released =>
      !_started || (_completion.isCompleted && !fail_disposal);

  /// Retained result of communication execution and disposal.
  @override
  Future<void> get done => _completion.future;

  /// Suspends completion until the returned barrier is released.
  ///
  /// Throws [StateError] when a draining barrier already exists.
  Completer<void> hold_drain() {
    if (_drain_barrier != null) {
      throw StateError('Communication draining is already controlled.');
    }

    return _drain_barrier = Completer<void>();
  }

  /// Establishes the configured controlled session.
  ///
  /// Returns the configured session or propagates [connection_error].
  /// Throws [StateError] for repeated execution.
  @override
  Future<MessageSession> connect() async {
    if (_started) {
      throw StateError('Test communication already executed.');
    }

    _started = true;

    final error = connection_error;

    if (error != null) {
      _completion.completeError(error);

      throw error;
    }

    session.done
        .then<void>(
          (_) => _finish(),
          onError: (Object error, StackTrace stack_trace) {
            return _finish(error, stack_trace);
          },
        )
        .ignore();

    return session;
  }

  /// Rejects listening endpoint execution in this client-only fixture.
  @override
  Future<void> run({
    required Future<void> shutdown,
    Future<void> Function()? on_startup,
  }) async {
    throw UnsupportedError('Client-only communication fixture.');
  }

  /// Completes the owning lifecycle after any draining barrier.
  ///
  /// [error] and [stack_trace] preserve terminal execution failure.
  /// Disposal failure takes precedence over execution failure.
  Future<void> _finish([Object? error, StackTrace? stack_trace]) async {
    await _drain_barrier?.future;

    if (fail_disposal) {
      _completion.completeError(StateError('Communication disposal failed.'));

      return;
    }

    if (error != null) {
      _completion.completeError(error, stack_trace);
    } else {
      _completion.complete();
    }
  }
}

/// Supplies controlled authenticated session execution.
///
/// Example:
/// ```dart
/// final session = _TestSession('trusted-owner');
///
/// await session.close();
///
/// assert(session.is_closed);
/// ```
final class _TestSession implements MessageSession {
  /// Creates a session reporting authenticated [os_user_id].
  _TestSession(this.os_user_id) {
    _completion.future.ignore();
  }

  /// Authenticated peer represented by this session.
  @override
  final String os_user_id;

  /// Number of application requests forwarded to this session.
  int request_count = 0;

  /// Optional application request failure.
  Object? request_error;

  /// Session termination notification.
  final Completer<void> _completion = Completer<void>();

  /// Whether the controlled session has terminated.
  bool get is_closed => _completion.isCompleted;

  /// Retained session execution result.
  @override
  Future<void> get done => _completion.future;

  /// Accepts a supported typed application [request].
  ///
  /// Returns a State Read response or propagates the configured
  /// [request_error].
  ///
  /// Throws [StateError] after closure and [UnsupportedError]
  /// for unexpected request types.
  @override
  Future<R> request<R extends Response>(Request<R> request) async {
    if (is_closed) {
      throw StateError('Test session is closed.');
    }

    request_count++;

    final error = request_error;

    if (error != null) {
      throw error;
    }

    if (request is StateReadRequest) {
      return StateReadResponse(
        state: RudraState(workflows: WorkflowsState(current_workflow: null)),
      ) as R;
    }

    throw UnsupportedError('Unexpected fixture request.');
  }

  /// Terminates session execution with the supplied [error].
  ///
  /// Repeated termination has no additional effect.
  void fail(Object error) {
    if (!_completion.isCompleted) {
      _completion.completeError(error);
    }
  }

  /// Releases the controlled session's communication resources.
  ///
  /// Repeated closure has no additional effect.
  @override
  Future<void> close() async {
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }
}
