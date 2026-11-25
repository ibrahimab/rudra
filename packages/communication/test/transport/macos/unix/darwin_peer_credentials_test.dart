import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:rudra_communication/src/transport/macos/unix/darwin_peer_credentials.dart';

import '../../../support/macos_test_identity.dart';

import 'package:test/test.dart';

/// Verifies native Unix-domain transport and peer authentication.
///
/// Uses independent operating-system processes to establish
/// bidirectional communication and retrieve trusted peer identity.
///
/// Workflow persistence and application processing are outside
/// this test boundary.
void main() {
  const ping = 0x01;
  const pong = 0x02;

  const operation_timeout = Duration(seconds: 20);

  group('DarwinPeerCredentials', () {
    test('authenticates independent Unix-domain peers '
        'and exchanges bytes', () async {
      // Use a short private directory to avoid Darwin's
      // limited Unix-domain socket pathname capacity.
      final directory = await Directory('/tmp').createTemp('rudra-ipc-');

      addTearDown(() async {
        await directory.delete(recursive: true);
      });

      final scope = await directory.resolveSymbolicLinks();

      final socket_path = '$scope/host.sock';

      final address = InternetAddress(
        socket_path,
        type: InternetAddressType.unix,
      );

      final expected_owner = await resolve_macos_test_identity();

      final server = await ServerSocket.bind(address, 0);

      addTearDown(() async {
        await server.close();
      });

      final connections = StreamIterator<Socket>(server);

      addTearDown(connections.cancel);

      expect(
        await FileSystemEntity.type(socket_path, followLinks: false),
        FileSystemEntityType.unixDomainSock,
      );

      final fixture = File(
        'test/transport/macos/unix/fixtures/peer_client.dart',
      ).absolute;

      // Launch a genuinely independent operating-system
      // process rather than another isolate.
      final process = await Process.start(Platform.resolvedExecutable, [
        fixture.path,
        socket_path,
      ]);

      final output = process.stdout.transform(utf8.decoder).join();

      final diagnostics = process.stderr.transform(utf8.decoder).join();

      final completion = process.exitCode;

      addTearDown(() async {
        process.kill(ProcessSignal.sigkill);

        await completion.timeout(operation_timeout);
        await output;
        await diagnostics;
      });

      expect(await connections.moveNext().timeout(operation_timeout), isTrue);

      final socket = connections.current;

      addTearDown(socket.destroy);

      const credentials = DarwinPeerCredentials();

      // Resolve the client's identity before consuming
      // any application-supplied bytes.
      final peer_owner = credentials.read_os_user_id(socket);

      expect(peer_owner, expected_owner);

      final incoming = StreamIterator<Uint8List>(socket);

      addTearDown(incoming.cancel);

      expect(await incoming.moveNext().timeout(operation_timeout), isTrue);

      expect(incoming.current, [ping]);

      socket.add([pong]);
      await socket.flush();

      final status = await completion.timeout(operation_timeout);

      expect(status, 0, reason: await diagnostics);

      // The independent client must also authenticate
      // the listening process through native credentials.
      expect(await output, 'peer=$expected_owner\nPONG\n');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('rejects non-Unix socket families', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

      addTearDown(() async {
        await server.close();
      });

      final connections = StreamIterator<Socket>(server);

      addTearDown(connections.cancel);

      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
        timeout: operation_timeout,
      );

      addTearDown(client.destroy);

      expect(await connections.moveNext().timeout(operation_timeout), isTrue);

      final socket = connections.current;

      addTearDown(socket.destroy);

      const credentials = DarwinPeerCredentials();

      // Unix-domain credential retrieval must never be
      // attempted against an unrelated socket family.
      expect(() => credentials.read_os_user_id(socket), throwsArgumentError);
    });
  }, skip: !Platform.isMacOS);
}
