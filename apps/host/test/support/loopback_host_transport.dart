import 'dart:async';
import 'dart:typed_data';

import 'package:rudra_communication/rudra_communication.dart';

/// Supplies in-memory authenticated connectivity for host integration tests.
///
/// Uses the public transport contracts so tests exercise the real
/// Communication facade, framing, codecs and message sessions.
///
/// Each connection receives independently owned client and server
/// endpoints.
final class LoopbackHostTransport implements Transport {
  /// Creates an inactive loopback transport.
  ///
  /// [server_peer_override] deliberately substitutes the identity
  /// reported to the server. It is used exclusively to verify that
  /// application handlers fail closed when transport authentication
  /// evidence disagrees with trusted application ownership.
  LoopbackHostTransport({this.server_peer_override});

  /// Optional deliberately inconsistent server-side peer identity.
  final String? server_peer_override;

  /// Current listening endpoint.
  _LoopbackListener? _listener;

  /// Canonical communication scope supplied during listener creation.
  String? _scope_directory;

  /// Trusted owner authorized by the listening endpoint.
  String? _owner;

  /// Opens a controlled listener for [scope_directory] and [os_user_id].
  ///
  /// Throws [StateError] when this transport already owns a listener.
  @override
  Future<TransportListener> listen({
    required String scope_directory,
    required String os_user_id,
  }) async {
    if (_listener != null) {
      throw StateError('Loopback transport already owns a listener.');
    }

    final listener = _LoopbackListener();

    _scope_directory = scope_directory;
    _owner = os_user_id;
    _listener = listener;

    return listener;
  }

  /// Creates an independent connection to the configured test listener.
  ///
  /// [scope_directory] and [os_user_id] must match the trusted
  /// listener configuration.
  ///
  /// Returns the client endpoint after delivering its server
  /// counterpart to the listener.
  ///
  /// Throws [StateError] for unavailable or mismatched configuration.
  @override
  Future<TransportConnection> connect({
    required String scope_directory,
    required String os_user_id,
  }) async {
    final listener = _listener;

    if (listener == null ||
        listener.is_closed ||
        scope_directory != _scope_directory ||
        os_user_id != _owner) {
      throw StateError('Loopback connection is unavailable.');
    }

    final client = _LoopbackConnection(os_user_id);

    final server = _LoopbackConnection(server_peer_override ?? os_user_id);

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
  _LoopbackConnection(this.os_user_id);

  /// Trusted remote peer identity reported by this endpoint.
  @override
  final String os_user_id;

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
  /// Throws [StateError] when either direction is closed.
  @override
  Future<void> send(Uint8List bytes) async {
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

  /// Terminates this endpoint's incoming byte stream.
  void _finish_input() {
    if (!_input.isClosed) {
      _input.close().ignore();
    }
  }
}
