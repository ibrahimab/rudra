import 'dart:async';
import 'dart:typed_data';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/host/runtime/host_connection_service.dart';
import 'package:test/test.dart';

/// Verifies portable host connection lifecycle coordination.
void main() {
  const service = HostConnectionService();
  const operation_timeout = Duration(seconds: 5);

  test('executes independent sessions concurrently', () async {
    final listener = _TestListener();
    final shutdown = Completer<void>();

    final first = _TestConnection();
    final second = _TestConnection();

    final both_started = Completer<void>();

    var started = 0;
    var completed = 0;

    final running = service.run(
      listener: listener,
      shutdown: shutdown.future,
      handle_connection: (connection) async {
        started++;

        if (started == 2) {
          both_started.complete();
        }

        // Both handlers must remain active until listener
        // disposal terminates their respective streams.
        await connection.incoming.drain<void>();

        completed++;
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

  test('startup failure disposes of the listener', () async {
    final listener = _TestListener();

    await expectLater(
      service.run(
        listener: listener,
        shutdown: Future<void>.value(),
        handle_connection: (_) async {
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
      listener: listener,
      shutdown: shutdown.future,
      handle_connection: (connection) async {
        if (identical(connection, first)) {
          throw StateError('Controlled session failure.');
        }

        second_started.complete();

        await connection.incoming.drain<void>();
      },
    );

    try {
      listener.accept(first);

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
}

/// Supplies controlled connections to the portable coordinator.
///
/// Example:
/// ```dart
/// final listener = _TestListener();
/// listener.accept(_TestConnection());
/// await listener.close();
/// ```
final class _TestListener implements HostListener {
  /// Creates an isolated in-memory listener.
  _TestListener();

  /// Stream delivering controlled accepted connections.
  final StreamController<HostConnection> _controller =
      StreamController<HostConnection>();

  /// Connections retained until listener disposal.
  final Set<_TestConnection> _active = {};

  /// Whether the listener has been disposed of.
  bool is_closed = false;

  /// Supplies the controlled connection stream.
  @override
  Stream<HostConnection> get connections => _controller.stream;

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
final class _TestConnection implements HostConnection {
  /// Creates an isolated in-memory connection.
  _TestConnection();

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
  }
}
