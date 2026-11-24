import 'dart:convert';
import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';

import 'macos_unix_listener.dart';

/// Provides authenticated local Unix-domain IPC on macOS.
///
/// Prepares a stable socket endpoint inside the exclusively owned
/// persistence directory and restricts accepted peers to the
/// configured trusted operating-system owner.
///
/// The caller must retain exclusive host ownership throughout
/// endpoint preparation, execution and disposal.
///
/// Example:
/// ```dart
/// final transport = MacOsUnixTransport();
///
/// final listener = await transport.listen(
///   scope_directory: scope,
///   os_user_id: trusted_owner,
/// );
///
/// await listener.close();
/// ```
final class MacOsUnixTransport implements HostTransport {
  /// Creates a native transport without acquiring resources.
  const MacOsUnixTransport();

  /// Stable endpoint filename within the persistence scope.
  static const String socket_filename = 'rudra-host.sock';

  /// Darwin sockaddr_un pathname capacity, including termination.
  static const int _socket_path_capacity = 104;

  /// Permission bits representing group and other access.
  static const int _shared_permission_mask = 0x003f;

  /// Darwin ECONNREFUSED error code.
  static const int _connection_refused = 61;

  /// Maximum duration of a stale-endpoint connection probe.
  static const Duration _probe_timeout = Duration(seconds: 2);

  /// Opens an authenticated local host listener.
  ///
  /// [scope_directory] must identify an existing canonical private
  /// persistence directory under exclusive host ownership.
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
  Future<HostListener> listen({
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

    final address = InternetAddress(
      socket_path,
      type: InternetAddressType.unix,
    );

    await _prepare_endpoint(address: address, socket_path: socket_path);

    final server = await ServerSocket.bind(address, 0, shared: false);

    return MacOsUnixListener(
      server: server,
      socket_path: socket_path,
      os_user_id: os_user_id,
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

      // A reachable endpoint must never be displaced, even if
      // the caller currently holds the cooperative host lock.
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
