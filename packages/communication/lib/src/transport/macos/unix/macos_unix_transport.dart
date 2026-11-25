import 'dart:convert';
import 'dart:io';

import '../../contracts/transport.dart';
import '../../contracts/transport_connection.dart';
import '../../contracts/transport_listener.dart';

import 'darwin_peer_credentials.dart';
import 'macos_unix_connection.dart';
import 'macos_unix_listener.dart';

/// Provides authenticated local Unix-domain IPC on macOS.
///
/// Establishes listening endpoints inside exclusively owned
/// communication scopes and connects to existing trusted endpoints.
///
/// Both accepted and outbound connections verify remote operating-system
/// identities using kernel-provided peer credentials.
///
/// Listener ownership remains exclusive throughout endpoint
/// preparation, execution and disposal. Outbound connections do not
/// acquire or modify listener ownership.
///
/// Example:
/// ```dart
/// const transport = MacOsUnixTransport();
///
/// final connection = await transport.connect(
///   scope_directory: scope,
///   os_user_id: trusted_owner,
/// );
///
/// await connection.close();
/// ```
final class MacOsUnixTransport implements Transport {
  /// Creates a native transport without acquiring resources.
  const MacOsUnixTransport();

  /// Stable endpoint filename within the communication scope.
  static const String socket_filename = 'rudra-host.sock';

  /// Darwin sockaddr_un pathname capacity, including termination.
  static const int _socket_path_capacity = 104;

  /// Permission bits representing group and other access.
  static const int _shared_permission_mask = 0x003f;

  /// Darwin ECONNREFUSED error code.
  static const int _connection_refused = 61;

  /// Maximum duration of a stale-endpoint connection probe.
  static const Duration _probe_timeout = Duration(seconds: 2);

  /// Maximum duration of outbound native connection establishment.
  static const Duration _connection_timeout = Duration(seconds: 5);

  /// Kernel credential reader used to authenticate outbound peers.
  static const DarwinPeerCredentials _credentials = DarwinPeerCredentials();

  /// Opens an authenticated local host listener.
  ///
  /// [scope_directory] must identify an existing canonical private
  /// communication directory under the caller's exclusive ownership.
  ///
  /// Exclusive ownership must remain established until the returned
  /// listener and its outstanding connections have been disposed of.
  ///
  /// [os_user_id] identifies the trusted owner authorized to connect.
  ///
  /// Returns a bound listener.
  ///
  /// Throws [UnsupportedError] outside macOS, [ArgumentError]
  /// for invalid configuration, or [FileSystemException] for
  /// unsafe endpoint entries and directory configuration.
  ///
  /// Native socket failures propagate to the caller.
  @override
  Future<TransportListener> listen({
    required String scope_directory,
    required String os_user_id,
  }) async {
    final endpoint = await _resolve_endpoint(
      scope_directory: scope_directory,
      os_user_id: os_user_id,
    );

    await _prepare_endpoint(
      address: endpoint.address,
      socket_path: endpoint.socket_path,
    );

    final server = await ServerSocket.bind(endpoint.address, 0, shared: false);

    return MacOsUnixListener(
      server: server,
      socket_path: endpoint.socket_path,
      os_user_id: os_user_id,
    );
  }

  /// Connects to an existing authenticated macOS Unix endpoint.
  ///
  /// [scope_directory] must identify the trusted canonical private
  /// communication directory containing the remote endpoint.
  ///
  /// [os_user_id] identifies the expected kernel-authenticated
  /// identity of the remote process.
  ///
  /// Returns an authenticated connection owned by the caller.
  ///
  /// Throws [UnsupportedError] outside macOS, [ArgumentError]
  /// for invalid configuration, [FileSystemException] for absent
  /// or unsafe endpoints, or [StateError] when peer authentication
  /// does not establish the expected identity.
  ///
  /// Native connection and credential retrieval failures propagate.
  ///
  /// Failed authentication destroys the acquired socket before
  /// propagating the failure. Connecting never changes endpoint
  /// filesystem entries.
  @override
  Future<TransportConnection> connect({
    required String scope_directory,
    required String os_user_id,
  }) async {
    final endpoint = await _resolve_endpoint(
      scope_directory: scope_directory,
      os_user_id: os_user_id,
    );

    final type = await FileSystemEntity.type(
      endpoint.socket_path,
      followLinks: false,
    );

    if (type != FileSystemEntityType.unixDomainSock) {
      throw FileSystemException(
        'Existing Unix socket endpoint required.',
        endpoint.socket_path,
      );
    }

    final socket = await Socket.connect(
      endpoint.address,
      0,
      timeout: _connection_timeout,
    );

    // Observe sink completion even when authentication rejects
    // the socket before a managed connection can be constructed.
    socket.done.ignore();

    try {
      final peer_owner = _credentials.read_os_user_id(socket);

      if (peer_owner != os_user_id) {
        throw StateError('Connected peer does not match the trusted owner.');
      }

      return MacOsUnixConnection(socket: socket, os_user_id: peer_owner);
    } catch (_) {
      socket.destroy();

      rethrow;
    }
  }

  /// Resolves native endpoint configuration without modifying it.
  ///
  /// [scope_directory] identifies the canonical private directory
  /// supplied by trusted composition.
  ///
  /// [os_user_id] supplies the trusted identity used for peer
  /// authorization.
  ///
  /// Returns the validated native address and filesystem pathname.
  ///
  /// Throws [UnsupportedError] outside macOS, [ArgumentError]
  /// for invalid configuration, or [FileSystemException] for
  /// missing or unsafe directory configuration and excessive
  /// native pathname length.
  Future<({InternetAddress address, String socket_path})> _resolve_endpoint({
    required String scope_directory,
    required String os_user_id,
  }) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('macOS Unix transport requires macOS.');
    }

    if (os_user_id.trim().isEmpty || !scope_directory.startsWith('/')) {
      throw ArgumentError('Invalid host transport configuration.');
    }

    final directory = Directory(scope_directory);
    final metadata = await directory.stat();

    if (metadata.type != FileSystemEntityType.directory ||
        (metadata.mode & _shared_permission_mask) != 0) {
      throw FileSystemException(
        'Host transport requires a private directory.',
        scope_directory,
      );
    }

    final socket_path = File.fromUri(directory.uri.resolve(socket_filename))
        .path;

    // Darwin limits pathname length in bytes, not Dart string
    // characters. Reserve one byte for native NUL termination.
    if (utf8.encode(socket_path).length >= _socket_path_capacity) {
      throw FileSystemException(
        'Unix socket endpoint path is too long.',
        socket_path,
      );
    }

    return (
      address: InternetAddress(socket_path, type: InternetAddressType.unix),
      socket_path: socket_path,
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
