import 'dart:io';
import 'dart:typed_data';

import '../../contracts/transport_connection.dart';

/// Adapts an authenticated Unix-domain socket to the portable
/// transport connection contract.
///
/// Retains the connected native socket and its verified peer
/// identity throughout the connection lifecycle.
///
/// Example:
/// ```dart
/// await connection.send(Uint8List.fromList([0x01]));
/// await connection.close();
/// ```
final class MacOsUnixConnection implements TransportConnection {
  /// Takes ownership of an authenticated [socket].
  ///
  /// [os_user_id] contains the kernel-verified peer identity.
  /// [on_close] removes the connection from its owning listener.
  MacOsUnixConnection({
    required Socket socket,
    required this.os_user_id,
    required void Function(MacOsUnixConnection) on_close,
  }) : _socket = socket,
       _on_close = on_close {
    // Write failures are observed through send(). Prevent the
    // separate IOSink completion future from becoming unhandled.
    _socket.done.ignore();
  }

  /// Native socket carrying bidirectional transport bytes.
  final Socket _socket;

  /// Callback releasing the listener's connection reference.
  final void Function(MacOsUnixConnection) _on_close;

  /// Whether this connection has been disposed of.
  bool _closed = false;

  /// Kernel-authenticated identity of the connected peer.
  @override
  final String os_user_id;

  /// Returns the underlying single-subscription byte stream.
  @override
  Stream<Uint8List> get incoming => _socket;

  /// Sends [bytes] through the native socket.
  ///
  /// Returns after flushing buffered bytes to the transport.
  /// Throws [StateError] after connection disposal.
  /// Native write failures propagate to the caller.
  @override
  Future<void> send(Uint8List bytes) async {
    if (_closed) {
      throw StateError('Host connection is closed.');
    }

    _socket.add(bytes);
    await _socket.flush();
  }

  /// Terminates the socket and releases listener ownership.
  ///
  /// Repeated calls have no additional effect.
  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closed = true;

    try {
      // IOSink.close() only closes the sending direction.
      // Destroy terminates both directions and pending reads.
      _socket.destroy();
    } finally {
      _on_close(this);
    }
  }
}
