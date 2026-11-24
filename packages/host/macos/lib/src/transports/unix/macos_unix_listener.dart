import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';

import 'darwin_peer_credentials.dart';
import 'macos_unix_connection.dart';

/// Owns a local Unix-domain listener and its authorized connections.
///
/// Verifies each peer's native credentials before exposing the
/// connection through the portable SDK transport contract.
///
/// Example:
/// ```dart
/// final subscription = listener.connections.listen(handle_connection);
///
/// await listener.close();
/// await subscription.cancel();
/// ```
final class MacOsUnixListener implements HostListener {
  /// Takes ownership of an already bound [server].
  ///
  /// [socket_path] identifies the transport-owned endpoint.
  /// [os_user_id] identifies the only authorized peer owner.
  MacOsUnixListener({
    required ServerSocket server,
    required String socket_path,
    required String os_user_id,
  }) : _server = server,
       _socket_path = socket_path,
       _os_user_id = os_user_id;

  /// Bound native Unix-domain listener.
  final ServerSocket _server;

  /// Filesystem endpoint owned by the listener.
  final String _socket_path;

  /// Trusted owner against which peer identities are validated.
  final String _os_user_id;

  /// Native credential reader shared by accepted connections.
  final DarwinPeerCredentials _credentials = const DarwinPeerCredentials();

  /// Outstanding authenticated connections owned by this listener.
  final Set<MacOsUnixConnection> _active = {};

  /// Whether listener shutdown has begun.
  bool _is_closing = false;

  /// Retained disposal result shared by repeated close requests.
  Future<void>? _closing;

  /// Exposes authorized native connections through the SDK contract.
  ///
  /// Authentication failures and unauthorized peers are disconnected
  /// without terminating the listening socket.
  @override
  late final Stream<HostConnection> connections = _server
      .map(_authorize)
      .where((connection) => connection != null)
      .cast<HostConnection>();

  /// Authenticates and authorizes an accepted [socket].
  ///
  /// Returns a managed connection for the trusted owner, or null
  /// after rejecting an unauthorized or unverifiable peer.
  MacOsUnixConnection? _authorize(Socket socket) {
    // Observe sink completion even when the peer is rejected
    // before a managed connection can be constructed.
    socket.done.ignore();

    if (_is_closing) {
      socket.destroy();
      return null;
    }

    final String peer_owner;

    try {
      peer_owner = _credentials.read_os_user_id(socket);
    } catch (_) {
      // Unverifiable identity must never reach the SDK.
      socket.destroy();
      return null;
    }

    if (peer_owner != _os_user_id) {
      socket.destroy();
      return null;
    }

    final connection = MacOsUnixConnection(
      socket: socket,
      os_user_id: peer_owner,
      on_close: (connection) {
        _active.remove(connection);
      },
    );

    _active.add(connection);

    return connection;
  }

  /// Closes the listener and its outstanding connections.
  ///
  /// Returns the same disposal result for repeated requests.
  /// Native resource and endpoint cleanup failures propagate.
  @override
  Future<void> close() => _closing ??= _close_resources();

  /// Releases the native resources owned by this listener.
  ///
  /// Stops acceptance before disposing of existing connections.
  /// The caller must retain exclusive scope ownership throughout.
  Future<void> _close_resources() async {
    _is_closing = true;

    try {
      await _server.close();
    } finally {
      // Closing a listening socket does not close its accepted
      // sockets. Dispose of every remaining connection explicitly.
      final outstanding = _active.toList(growable: false);

      await Future.wait(outstanding.map((connection) => connection.close()));
    }

    // Dart may already have removed the Unix socket pathname
    // during native listener disposal.
    final type = await FileSystemEntity.type(_socket_path, followLinks: false);

    if (type == FileSystemEntityType.notFound) {
      return;
    }

    if (type != FileSystemEntityType.unixDomainSock) {
      throw FileSystemException(
        'Unexpected entry at the host socket endpoint.',
        _socket_path,
      );
    }

    await File(_socket_path).delete();
  }
}
