import 'dart:io';

import 'package:rudra_host_macos/src/transports/unix/darwin_peer_credentials.dart';

/// Single-byte request used by the native transport fixture.
const int _ping = 0x01;

/// Single-byte response expected from the listening process.
const int _pong = 0x02;

/// Maximum duration of an individual socket operation.
const Duration _socket_timeout = Duration(seconds: 15);

/// Connects an independent process to a Unix-domain test listener.
///
/// [arguments] contains the native socket endpoint path.
///
/// Resolves the listener's kernel-provided identity and verifies
/// bidirectional byte transfer before closing the connection.
///
/// Example:
/// ```sh
/// dart test/transports/unix/fixtures/peer_client.dart /tmp/rudra.sock
/// ```
Future<void> main(List<String> arguments) async {
  final address = InternetAddress(
    arguments.single,
    type: InternetAddressType.unix,
  );

  final socket = await Socket.connect(address, 0, timeout: _socket_timeout);

  try {
    const credentials = DarwinPeerCredentials();

    // Authenticate the listening process independently of
    // any information received through the application stream.
    final os_user_id = credentials.read_os_user_id(socket);

    socket.add([_ping]);
    await socket.flush();

    final response = await socket.first.timeout(_socket_timeout);

    // A one-byte exchange deliberately avoids introducing
    // application message framing into this transport test.
    if (response.length != 1 || response.single != _pong) {
      throw StateError('Unexpected native transport response.');
    }

    stdout.writeln('peer=$os_user_id');
    stdout.writeln('PONG');
  } finally {
    // Release the connection regardless of authentication
    // or byte-transfer failures.
    socket.destroy();
  }
}
