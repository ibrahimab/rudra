import 'dart:async';
import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:test/test.dart';

import '../support/macos_test_identity.dart';

/// Verifies explicitly configured native outbound connectivity.
///
/// Listener and client transports retain independent endpoint
/// configuration while establishing authenticated communication.
void main() {
  const operation_timeout = Duration(seconds: 15);

  test(
    'independent configured transports establish authenticated connectivity',
    () async {
      final directory = await Directory('/tmp')
          .createTemp('rudra-configured-connect-');

      addTearDown(() async {
        await directory.delete(recursive: true);
      });

      final scope = await directory.resolveSymbolicLinks();
      final owner = await resolve_macos_test_identity();

      final listener_transport = MacOsUnixTransport(
        socket_path: '$scope/rudra.sock',
      );

      final client_transport = MacOsUnixTransport(
        socket_path: '$scope/rudra.sock',
      );

      final listener = await listener_transport.listen();

      final accepted = StreamIterator<TransportConnection>(
        listener.connections,
      );

      TransportConnection? client;

      try {
        final pending = accepted.moveNext();

        client = await client_transport.connect();

        expect(await pending.timeout(operation_timeout), isTrue);

        expect(client.os_user_id, owner);
        expect(accepted.current.os_user_id, owner);

        expect(listener_transport, isNot(same(client_transport)));
      } finally {
        await client?.close();
        await listener.close();
        await accepted.cancel();
      }
    },
    skip: !Platform.isMacOS,
  );

  test('unsupported native transports reject outbound connectivity', () async {
    const transport = MacOsUnixTransport(socket_path: '/unused/rudra.sock');

    await expectLater(transport.connect(), throwsA(isA<UnsupportedError>()));
  }, skip: Platform.isMacOS);
}
