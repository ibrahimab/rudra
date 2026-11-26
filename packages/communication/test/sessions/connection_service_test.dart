import 'dart:async';
import 'dart:typed_data';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:test/test.dart';

import 'package:rudra_communication/src/sessions/connection_service.dart';
import 'package:rudra_communication/src/sessions/default_message_session.dart';

/// Verifies portable host connection lifecycle coordination.
void main() {
  const operation_timeout = Duration(seconds: 5);

  late ConnectionService service;

  setUp(() {
    service = ConnectionService();
  });

  test('executes independent sessions concurrently', () async {
    final listener = _TestListener();
    final shutdown = Completer<void>();

    final first = _TestConnection();
    final second = _TestConnection();

    final both_started = Completer<void>();

    var started = 0;
    var completed = 0;

    final running = service.run(
      listeners: [listener],
      shutdown: shutdown.future,
      open_session: (connection) {
        final session = _open_session(connection);

        started++;

        session.done.then<void>((_) {
          completed++;
        }).ignore();

        if (started == 2) {
          both_started.complete();
        }

        return session;
      },
    );

    try {
      listener.accept(first);
      listener.accept(second);

      await both_started.future.timeout(operation_timeout);

      expect(started, 2);
      expect(completed, 0);
    } finally {
      shutdown.complete();
      await running.timeout(operation_timeout);
    }

    expect(completed, 2);
    expect(listener.is_closed, isTrue);
    expect(first.is_closed, isTrue);
    expect(second.is_closed, isTrue);
  });

  test('session admission is bounded across enabled listeners', () async {
    final coordinator = ConnectionService(maximum_sessions: 1);
    final first_listener = _TestListener();
    final second_listener = _TestListener();
    final shutdown = Completer<void>();
    final admitted = Completer<void>();
    final first = _TestConnection();
    final excess = _TestConnection();

    final running = coordinator.run(
      listeners: [first_listener, second_listener],
      shutdown: shutdown.future,
      open_session: (connection) {
        expect(connection, same(first));
        admitted.complete();
        return _open_session(connection);
      },
    );

    try {
      first_listener.accept(first);
      await admitted.future.timeout(operation_timeout);
      second_listener.accept(excess);
      await excess.closed.timeout(operation_timeout);
      expect(first.is_closed, isFalse);
    } finally {
      shutdown.complete();
      await running.timeout(operation_timeout);
    }
    expect(first.is_closed, isTrue);
    expect(coordinator.resources_released, isTrue);
  });

  test('startup failure disposes of the listener', () async {
    final listener = _TestListener();

    await expectLater(
      service.run(
        listeners: [listener],
        shutdown: Future<void>.value(),
        open_session: (_) {
          fail('Client execution must not begin.');
        },
        on_startup: () async {
          throw StateError('Startup failed.');
        },
      ),
      throwsStateError,
    );

    expect(listener.is_closed, isTrue);
  });

  test('a failed session does not terminate the service', () async {
    final listener = _TestListener();
    final shutdown = Completer<void>();

    final first = _TestConnection();
    final second = _TestConnection();

    final second_started = Completer<void>();

    final running = service.run(
      listeners: [listener],
      shutdown: shutdown.future,
      open_session: (connection) {
        final session = _open_session(connection);

        if (identical(connection, second)) {
          second_started.complete();
        }

        return session;
      },
    );

    try {
      listener.accept(first);

      // A zero-length frame violates the actual communication
      // protocol and terminates only this client session.
      first.inject(Uint8List(4));

      await first.closed.timeout(operation_timeout);

      listener.accept(second);

      await second_started.future.timeout(operation_timeout);

      expect(listener.is_closed, isFalse);
      expect(first.is_closed, isTrue);
      expect(second.is_closed, isFalse);
    } finally {
      shutdown.complete();
      await running.timeout(operation_timeout);
    }
  });

  test('failed connection disposal leaves resources unconfirmed', () async {
    final listener = _TestListener();
    final shutdown = Completer<void>();

    final connection = _TestConnection(fail_disposal: true);

    final running = service.run(
      listeners: [listener],
      shutdown: shutdown.future,
      open_session: _open_session,
    );

    final result = expectLater(
      running.timeout(operation_timeout),
      throwsStateError,
    );

    listener.accept(connection);

    // Initiate actual protocol termination. Failed session
    // disposal must propagate rather than be isolated as an
    // ordinary client execution failure.
    connection.inject(Uint8List(4));

    await result;

    expect(listener.is_closed, isTrue);
    expect(service.resources_released, isFalse);
  });
}

/// Opens an executing session over the supplied [connection].
///
/// Uses empty frozen application registration so these tests
/// exercise communication lifecycle ownership independently of
/// application-specific messaging.
///
/// Returns a session owning the supplied connection.
DefaultMessageSession _open_session(TransportConnection connection) {
  final codecs = MessageCodecRegistry()..freeze();

  final handlers = RequestHandlerRegistry()..freeze(codecs: codecs);

  return DefaultMessageSession.open(
    connection: connection,
    codecs: codecs,
    handlers: handlers,
  );
}

/// Supplies controlled connections to the portable coordinator.
///
/// Example:
/// ```dart
/// final listener = _TestListener();
/// listener.accept(_TestConnection());
/// await listener.close();
/// ```
final class _TestListener implements TransportListener {
  /// Creates an isolated in-memory listener.
  _TestListener();

  /// Stream delivering controlled accepted connections.
  final StreamController<TransportConnection> _controller =
      StreamController<TransportConnection>();

  /// Connections retained until listener disposal.
  final Set<_TestConnection> _active = {};

  /// Whether the listener has been disposed of.
  bool is_closed = false;

  /// Supplies the controlled connection stream.
  @override
  Stream<TransportConnection> get connections => _controller.stream;

  /// Delivers [connection] as an authenticated accepted session.
  void accept(_TestConnection connection) {
    _active.add(connection);
    _controller.add(connection);
  }

  /// Terminates outstanding sessions and closes the listener.
  @override
  Future<void> close() async {
    if (is_closed) {
      return;
    }

    is_closed = true;

    await Future.wait(_active.map((connection) => connection.close()));

    final has_listener = _controller.hasListener;
    final completion = _controller.close();

    // An unsuccessful startup may dispose of the listener
    // before its single-subscription stream has been consumed.
    if (has_listener) {
      await completion;
    }
  }
}

/// Provides an idle authenticated session for lifecycle tests.
///
/// Example:
/// ```dart
/// final connection = _TestConnection();
/// await connection.close();
/// ```
final class _TestConnection implements TransportConnection {
  /// Creates an isolated in-memory connection.
  ///
  /// [fail_disposal] requests a failure during the initial
  /// connection disposal operation.
  _TestConnection({this.fail_disposal = false});

  /// Whether connection disposal should report failure.
  final bool fail_disposal;

  /// Stream representing incoming transport bytes.
  final StreamController<Uint8List> _incoming = StreamController<Uint8List>();

  /// Records completed connection disposal.
  final Completer<void> _closed = Completer<void>();

  /// Whether connection disposal has completed.
  bool get is_closed => _closed.isCompleted;

  /// Notification used to await connection disposal.
  Future<void> get closed => _closed.future;

  /// Trusted identity assigned to the test peer.
  @override
  String get os_user_id => 'test-owner';

  /// Controlled stream of incoming bytes.
  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  /// Delivers [bytes] to the executing session's incoming stream.
  void inject(Uint8List bytes) {
    _incoming.add(bytes);
  }

  /// Accepts [bytes] without performing native transport I/O.
  @override
  Future<void> send(Uint8List bytes) async {}

  /// Terminates the incoming stream and confirms disposal.
  @override
  Future<void> close() async {
    if (is_closed) {
      return;
    }

    _closed.complete();

    // Do not await single-subscription stream delivery when
    // a failed handler never subscribed to incoming bytes.
    unawaited(_incoming.close());

    if (fail_disposal) {
      throw StateError('Controlled connection disposal failure.');
    }
  }
}
