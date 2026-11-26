import 'dart:convert';
import 'dart:io';

import 'package:rudra_platform_macos/rudra_platform_macos.dart';

import '../../contracts/transport.dart';
import '../../contracts/transport_connection.dart';
import '../../contracts/transport_listener.dart';

import 'darwin_peer_credentials.dart';
import 'macos_unix_connection.dart';
import 'macos_unix_listener.dart';

/// Provides native Unix-domain IPC authenticated by Darwin peer credentials.
///
/// By default both sides use the effective user's protected runtime endpoint.
/// An explicit path changes only the socket location.
///
/// ```dart
/// final transport = MacOsUnixTransport(socket_path: '/private/tmp/fixture/host.sock');
/// final connection = await transport.connect();
/// await connection.close();
/// ```
final class MacOsUnixTransport implements Transport {
  /// Retains an optional absolute [socket_path] without touching the filesystem.
  ///
  /// An override must be in a canonical, private directory owned by the
  /// effective UID. Both ends continue to authenticate peers as that UID.
  const MacOsUnixTransport({this.socket_path});

  /// The explicitly selected endpoint, or null for native default resolution.
  final String? socket_path;

  /// Darwin sockaddr_un pathname capacity, including termination.
  static const int _socket_path_capacity = 104;

  /// Darwin ECONNREFUSED error code.
  static const int _connection_refused = 61;

  /// Maximum duration of a stale-endpoint connection probe.
  static const Duration _probe_timeout = Duration(seconds: 2);

  /// Maximum duration of outbound native connection establishment.
  static const Duration _connection_timeout = Duration(seconds: 5);

  /// Binds the configured endpoint and accepts only the effective user's peers.
  ///
  /// The caller must retain exclusive ownership until listener disposal.
  @override
  Future<TransportListener> listen() async {
    final endpoint = await _resolve_endpoint();
    await _prepare_endpoint(
      address: endpoint.address,
      socket_path: endpoint.path,
    );

    final server = await ServerSocket.bind(endpoint.address, 0, shared: false);
    final listener = MacOsUnixListener(
      server: server,
      socket_path: endpoint.path,
      os_user_id: macos_user_id(endpoint.uid),
    );

    try {
      // The directory is already private during the bind-to-chmod interval.
      final result = await Process.run('/bin/chmod', ['0600', endpoint.path]);
      if (result.exitCode != 0) {
        throw FileSystemException(
          'Unable to protect the Rudra socket.',
          endpoint.path,
        );
      }
      return listener;
    } catch (error) {
      try {
        await listener.close();
      } catch (disposal_error) {
        throw TransportDisposalException(error, disposal_error);
      }
      rethrow;
    }
  }

  /// Connects to an existing endpoint and verifies the host's native identity.
  ///
  /// The caller owns the returned connection. Unavailable or unsafe endpoints
  /// and mismatched peers cause explicit failure.
  @override
  Future<TransportConnection> connect() async {
    final endpoint = await _resolve_endpoint();
    final type = await FileSystemEntity.type(endpoint.path, followLinks: false);
    if (type != FileSystemEntityType.unixDomainSock) {
      throw FileSystemException(
        'Existing Unix socket endpoint required.',
        endpoint.path,
      );
    }

    final socket = await Socket.connect(
      endpoint.address,
      0,
      timeout: _connection_timeout,
    );
    return authenticate_macos_unix_connection(
      socket,
      macos_user_id(endpoint.uid),
    );
  }

  /// Resolves the endpoint and validates its parent before socket operations.
  Future<({InternetAddress address, String path, int uid})>
  _resolve_endpoint() async {
    final uid = await macos_effective_uid();
    final path = socket_path ?? macos_default_socket_path(uid);
    if (!path.startsWith('/') ||
        path.endsWith('/') ||
        path.contains('\u0000')) {
      throw ArgumentError.value(
        path,
        'socket_path',
        'Expected an absolute socket file path.',
      );
    }

    // Darwin counts pathname bytes, including the native NUL terminator.
    if (utf8.encode(path).length >= _socket_path_capacity) {
      throw FileSystemException('Unix socket endpoint path is too long.', path);
    }

    await require_macos_private_directory(File(path).parent.path, uid);
    return (
      address: InternetAddress(path, type: InternetAddressType.unix),
      path: path,
      uid: uid,
    );
  }

  /// Prepares [socket_path] for exclusive listener binding.
  ///
  /// [address] supplies the corresponding native socket address.
  ///
  /// An absent endpoint is accepted. An existing socket is removed
  /// only after a native connection attempt reports refusal.
  ///
  /// Live sockets, unexpected filesystem entries and ambiguous
  /// connection failures are preserved and cause startup failure.
  Future<void> _prepare_endpoint({
    required InternetAddress address,
    required String socket_path,
  }) async {
    final type = await FileSystemEntity.type(socket_path, followLinks: false);

    if (type == FileSystemEntityType.notFound) {
      return;
    }

    if (type != FileSystemEntityType.unixDomainSock) {
      throw FileSystemException(
        'Unexpected existing host endpoint.',
        socket_path,
      );
    }

    try {
      final existing = await Socket.connect(
        address,
        0,
        timeout: _probe_timeout,
      );

      existing.done.ignore();
      existing.destroy();

      // Exclusive scope ownership alone does not establish that an
      // existing endpoint is abandoned. Preserve reachable endpoints
      // to avoid disrupting an active communication listener.
      throw FileSystemException(
        'Host socket endpoint is already listening.',
        socket_path,
      );
    } on SocketException catch (error) {
      // Timeout, permission failure and other errors do not
      // establish that an existing socket is abandoned.
      if (error.osError?.errorCode != _connection_refused) {
        rethrow;
      }
    }

    // Recheck the filesystem entry before removing the stale
    // socket. Never recursively delete an endpoint location.
    final current_type = await FileSystemEntity.type(
      socket_path,
      followLinks: false,
    );

    if (current_type != FileSystemEntityType.unixDomainSock) {
      throw FileSystemException(
        'Host endpoint changed during preparation.',
        socket_path,
      );
    }

    await File(socket_path).delete();
  }
}

/// Resolves the deterministic default Unix endpoint for a trusted [uid].
String macos_default_socket_path(int uid) =>
    '${MacOsResourceLayout.user_runtime(uid)}/${MacOsResourceLayout.socket_filename}';

/// Transfers [socket] to a managed connection after native peer verification.
///
/// On authentication failure, destroys the acquired socket before returning.
TransportConnection authenticate_macos_unix_connection(
  Socket socket,
  String expected_owner,
) {
  socket.done.ignore();

  try {
    final peer_owner = const DarwinPeerCredentials().read_os_user_id(socket);
    if (peer_owner != expected_owner) {
      throw StateError('Connected peer does not match the trusted owner.');
    }
    return MacOsUnixConnection(socket: socket, os_user_id: peer_owner);
  } catch (_) {
    socket.destroy();
    rethrow;
  }
}
