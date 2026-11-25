import 'dart:async';
import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_communication/src/transport/local_transport.dart';
import 'package:test/test.dart';

import '../support/macos_test_identity.dart';

/// Verifies default native transport selection for outbound
/// authenticated communication.
void main() {
  const transport = LocalTransport();
  const operation_timeout = Duration(seconds: 15);

  test('selects the macOS transport for outbound connectivity', () async {
    final directory = await Directory('/tmp')
        .createTemp('rudra-local-connect-');

    addTearDown(() async {
      await directory.delete(recursive: true);
    });

    final scope = await directory.resolveSymbolicLinks();
    final owner = await resolve_macos_test_identity();

    final listener = await transport.listen(
      scope_directory: scope,
      os_user_id: owner,
    );

    final accepted = StreamIterator<TransportConnection>(listener.connections);

    TransportConnection? client;

    try {
      final pending = accepted.moveNext();

      client = await transport.connect(
        scope_directory: scope,
        os_user_id: owner,
      );

      expect(await pending.timeout(operation_timeout), isTrue);

      expect(client.os_user_id, owner);
      expect(accepted.current.os_user_id, owner);
    } finally {
      await client?.close();
      await listener.close();
      await accepted.cancel();
    }
  }, skip: !Platform.isMacOS);

  test('unsupported platforms reject outbound connectivity', () {
    expect(
      () => transport.connect(
        scope_directory: '/unused',
        os_user_id: 'test-owner',
      ),
      throwsA(isA<UnsupportedError>()),
    );
  }, skip: Platform.isMacOS);
}
