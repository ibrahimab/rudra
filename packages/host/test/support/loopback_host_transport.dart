import 'dart:async';
import 'dart:typed_data';

import 'package:rudra_communication/rudra_communication.dart';

/// Controls the first outbound frame of a test connection.
///
/// Allows tests to distinguish completed application execution from
/// successful delivery of its communication response.
final class LoopbackResponseBarrier {
  /// Signals that outbound transmission has reached the barrier.
  final Completer<void> _entered = Completer<void>();

  /// Releases the suspended transmission.
  final Completer<void> _released = Completer<void>();

  /// Completes when transmission reaches the controlled boundary.
  Future<void> get entered => _entered.future;

  /// Signals transmission entry and waits for explicit release.
  Future<void> hold() {
    if (!_entered.isCompleted) {
      _entered.complete();
    }

    return _released.future;
  }

  /// Releases the held transmission.
  ///
  /// Repeated release is permitted.
  void release() {
    if (!_released.isCompleted) {
      _released.complete();
    }
  }
}

/// Supplies in-memory authenticated connectivity for host integration tests.
///
/// Uses the public transport contracts so tests exercise the real
/// Communication facade, framing, codecs and message sessions.
///
/// Each connection receives independently owned client and server
/// endpoints within the configured in-memory communication environment.
///
/// Example:
/// ```dart
/// final transport = LoopbackHostTransport(
///   os_user_id: 'trusted-owner',
/// );
///
/// final listener = await transport.listen();
/// final connection = await transport.connect();
///
/// await connection.close();
/// await listener.close();
/// ```
final class LoopbackHostTransport implements Transport {
  /// Creates a configured inactive loopback transport.
  ///
  /// [os_user_id] identifies the trusted synthetic peer.
  ///
  /// [server_peer_override] deliberately substitutes the identity
  /// reported to the server. It is used exclusively to verify that
  /// application handlers fail closed when transport authentication
  /// evidence disagrees with trusted application ownership.
  LoopbackHostTransport({required this.os_user_id, this.server_peer_override});

  /// Trusted synthetic operating-system identity.
  final String os_user_id;

  /// Optional deliberately inconsistent server-side peer identity.
  final String? server_peer_override;

  /// Optional barrier assigned to the next connected server endpoint.
  ///
  /// The next connection consumes this configuration. Its first outbound
  /// frame is held until the barrier is released or the connection closes.
  LoopbackResponseBarrier? next_response_barrier;

  /// Current listening endpoint.
  _LoopbackListener? _listener;

  /// Opens the configured controlled listening endpoint.
  ///
  /// Returns an independently owned listener.
  ///
  /// Throws [StateError] when this transport already owns a listener.
  @override
  Future<TransportListener> listen() async {
    if (_listener != null) {
      throw StateError('Loopback transport already owns a listener.');
    }

    final listener = _LoopbackListener();

    _listener = listener;

    return listener;
  }

  /// Creates an independent connection to the configured test listener.
  ///
  /// Returns the client endpoint after delivering its server
  /// counterpart to the listener.
  ///
  /// Throws [StateError] when no active listener is available.
  @override
  Future<TransportConnection> connect() async {
    final listener = _listener;

    if (listener == null || listener.is_closed) {
      throw StateError('Loopback connection is unavailable.');
    }

    final client = _LoopbackConnection(os_user_id);

    final server = _LoopbackConnection(
      server_peer_override ?? os_user_id,
      response_barrier: next_response_barrier,
    );

    next_response_barrier = null;

    client.peer = server;
    server.peer = client;

    listener.accept(server);

    return client;
  }
}

/// Owns controlled incoming server connections.
final class _LoopbackListener implements TransportListener {
  /// Stream of accepted authenticated connections.
  final StreamController<TransportConnection> _accepted =
      StreamController<TransportConnection>();

  /// Server endpoints retained until listener disposal.
  final Set<_LoopbackConnection> _connections = {};

  /// Retained listener disposal operation.
  Future<void>? _closing;

  /// Whether listener disposal has begun.
  bool get is_closed => _closing != null;

  /// Supplies independently accepted connection endpoints.
  @override
  Stream<TransportConnection> get connections => _accepted.stream;

  /// Delivers [connection] to the listening communication subsystem.
  ///
  /// Throws [StateError] when the listener has been closed.
  void accept(_LoopbackConnection connection) {
    if (is_closed) {
      throw StateError('Loopback listener is closed.');
    }

    _connections.add(connection);
    _accepted.add(connection);
  }

  /// Closes all retained endpoints and terminates listener delivery.
  ///
  /// Repeated calls return the original disposal operation.
  @override
  Future<void> close() => _closing ??= _dispose();

  /// Releases all controlled listener resources.
  Future<void> _dispose() async {
    try {
      await Future.wait<void>(
        _connections.map((connection) => connection.close()),
      );
    } finally {
      _connections.clear();

      // An unsuccessful startup may leave this stream unconsumed.
      _accepted.close().ignore();
    }
  }
}

/// Represents one endpoint of a bidirectional loopback connection.
final class _LoopbackConnection implements TransportConnection {
  /// Creates an endpoint reporting authenticated [os_user_id].
  ///
  /// [response_barrier] optionally suspends the first outbound frame.
  _LoopbackConnection(
    this.os_user_id, {
    LoopbackResponseBarrier? response_barrier,
  }) : _response_barrier = response_barrier;

  /// Trusted remote peer identity reported by this endpoint.
  @override
  final String os_user_id;

  /// Optional barrier consumed by the first outbound transmission.
  LoopbackResponseBarrier? _response_barrier;

  /// Signals termination of incoming delivery and releases blocked writes.
  final Completer<void> _terminated = Completer<void>();

  /// Independently owned endpoint receiving transmitted bytes.
  late final _LoopbackConnection peer;

  /// Incoming ordered byte stream.
  final StreamController<Uint8List> _input = StreamController<Uint8List>();

  /// Retained connection disposal operation.
  Future<void>? _closing;

  /// Supplies the incoming connection byte stream.
  @override
  Stream<Uint8List> get incoming => _input.stream;

  /// Transmits an independent copy of [bytes] to the peer.
  ///
  /// An optional response barrier suspends the first transmission.
  /// Connection termination releases that suspension.
  ///
  /// Throws [StateError] when either direction is closed.
  @override
  Future<void> send(Uint8List bytes) async {
    final barrier = _response_barrier;
    _response_barrier = null;

    if (barrier != null) {
      await Future.any<void>([barrier.hold(), _terminated.future]);
    }

    if (_closing != null || _input.isClosed || peer._input.isClosed) {
      throw StateError('Loopback connection is closed.');
    }

    peer._input.add(Uint8List.fromList(bytes));
  }

  /// Terminates both directions of the controlled connection.
  ///
  /// Repeated calls return the original disposal operation.
  @override
  Future<void> close() => _closing ??= _dispose();

  /// Signals incoming-stream termination on both endpoints.
  Future<void> _dispose() async {
    _finish_input();
    peer._finish_input();
  }

  /// Terminates incoming delivery and releases suspended transmission.
  void _finish_input() {
    if (!_terminated.isCompleted) {
      _terminated.complete();
    }

    if (!_input.isClosed) {
      _input.close().ignore();
    }
  }
}
