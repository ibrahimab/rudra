import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../contracts/transport_connection.dart';

/// Adapts an authenticated Unix-domain socket to the portable
/// transport connection contract.
///
/// Retains the connected native socket and its verified peer
/// identity throughout the connection lifecycle.
///
/// Connections may be accepted by an owning listener or established
/// independently through outbound transport connectivity.
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
  ///
  /// [on_close] optionally releases the connection from its owning
  /// listener after successful native socket disposal.
  ///
  /// Outbound connections require no listener callback.
  MacOsUnixConnection({
    required Socket socket,
    required this.os_user_id,
    void Function(MacOsUnixConnection)? on_close,
  }) : _socket = socket,
       _on_close = on_close {
    // Write failures are observed through send(). Prevent the
    // separate IOSink completion future from becoming unhandled.
    _socket.done.ignore();
  }

  /// Native socket carrying bidirectional transport bytes.
  final Socket _socket;

  /// Optional callback releasing the listener's connection reference.
  final void Function(MacOsUnixConnection)? _on_close;

  /// Whether native connection termination has begun.
  bool _closed = false;

  /// Retained result of the initial resource disposal operation.
  Future<void>? _closing;

  /// Interruption signal belonging to the current transport write.
  ///
  /// At most one write may be active. The signal is released
  /// when that write settles.
  Completer<void>? _active_write;

  /// Kernel-authenticated identity of the connected peer.
  @override
  final String os_user_id;

  /// Returns the underlying single-subscription byte stream.
  @override
  Stream<Uint8List> get incoming => _socket;

  /// Sends [bytes] through the native socket.
  ///
  /// Returns after flushing buffered bytes to the transport.
  ///
  /// Throws [StateError] after connection termination or when
  /// another transport write remains active.
  ///
  /// Closing the connection interrupts an outstanding write.
  /// Native write failures propagate to the caller.
  @override
  Future<void> send(Uint8List bytes) async {
    if (_closed) {
      throw StateError('Host connection is closed.');
    }

    if (_active_write != null) {
      throw StateError('Concurrent transport writes are prohibited.');
    }

    final interruption = Completer<void>();

    _active_write = interruption;

    try {
      _socket.add(bytes);

      // Connection disposal must settle the exposed write even
      // when native flush completion is interrupted.
      await Future.any<void>([_socket.flush(), interruption.future]);

      if (_closed) {
        throw StateError('Host connection closed during transmission.');
      }
    } finally {
      _active_write = null;
    }
  }

  /// Terminates the socket and releases listener ownership.
  ///
  /// Interrupts any outstanding transport write.
  ///
  /// Repeated calls return the retained resource disposal result.
  /// Native resource disposal failures propagate to the caller.
  @override
  Future<void> close() => _closing ??= _dispose();

  /// Disposes of the native socket and interrupts active transmission.
  ///
  /// Listener ownership is released only after successful native
  /// socket destruction.
  ///
  /// Returns after initiating termination of both native directions.
  /// Native disposal failures propagate without confirming release.
  Future<void> _dispose() async {
    _closed = true;

    try {
      // IOSink.close() only closes the sending direction.
      // Destroy terminates both directions and pending reads.
      _socket.destroy();

      _on_close?.call(this);
    } finally {
      // Release the caller-facing write independently of native
      // flush completion. The original flush remains observed.
      _active_write?.complete();
    }
  }
}
