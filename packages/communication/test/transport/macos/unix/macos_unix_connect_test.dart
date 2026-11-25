import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:test/test.dart';

import '../../../support/macos_test_identity.dart';

/// Verifies authenticated outbound macOS transport connectivity.
///
/// Exercises native peer authentication, bidirectional byte delivery
/// and preservation of listener-owned filesystem endpoints.
void main() {
  const transport = MacOsUnixTransport();
  const operation_timeout = Duration(seconds: 15);

  late Directory directory;
  late String scope;
  late String owner;
  late String socket_path;

  group('MacOsUnixTransport.connect', () {
    setUp(() async {
      directory = await Directory('/tmp').createTemp('rudra-connect-');

      scope = await directory.resolveSymbolicLinks();
      owner = await resolve_macos_test_identity();

      socket_path = '$scope/${MacOsUnixTransport.socket_filename}';
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    /// Opens a listener within the fixture's exclusive scope.
    ///
    /// Returns the authenticated native listener.
    Future<TransportListener> listen() {
      return transport.listen(scope_directory: scope, os_user_id: owner);
    }

    /// Connects to the fixture's existing communication endpoint.
    ///
    /// [expected_owner] optionally substitutes the expected remote
    /// identity to exercise authentication failure.
    ///
    /// Returns the authenticated connection.
    Future<TransportConnection> connect({String? expected_owner}) {
      return transport.connect(
        scope_directory: scope,
        os_user_id: expected_owner ?? owner,
      );
    }

    test('authenticates peers in both directions', () async {
      final listener = await listen();

      final accepted = StreamIterator<TransportConnection>(
        listener.connections,
      );

      TransportConnection? client;

      StreamIterator<Uint8List>? client_input;
      StreamIterator<Uint8List>? server_input;

      try {
        final pending = accepted.moveNext();

        final connected = await connect();
        client = connected;

        expect(await pending.timeout(operation_timeout), isTrue);

        final server = accepted.current;

        expect(connected.os_user_id, owner);
        expect(server.os_user_id, owner);

        final incoming_client = StreamIterator<Uint8List>(connected.incoming);

        final incoming_server = StreamIterator<Uint8List>(server.incoming);

        client_input = incoming_client;
        server_input = incoming_server;

        final request = incoming_server.moveNext();

        await connected.send(Uint8List.fromList([0x01]));

        expect(await request.timeout(operation_timeout), isTrue);

        expect(incoming_server.current, [0x01]);

        final response = incoming_client.moveNext();

        await server.send(Uint8List.fromList([0x02]));

        expect(await response.timeout(operation_timeout), isTrue);

        expect(incoming_client.current, [0x02]);
      } finally {
        await client?.close();
        await listener.close();

        await client_input?.cancel();
        await server_input?.cancel();
        await accepted.cancel();
      }
    });

    test('rejects an unexpected remote owner and closes its socket', () async {
      // Use a native server so the remote transport closure can
      // be observed independently of listener authentication.
      final address = InternetAddress(
        socket_path,
        type: InternetAddressType.unix,
      );

      final server = await ServerSocket.bind(address, 0);

      final accepted = StreamIterator<Socket>(server);

      Socket? peer;

      try {
        final pending = accepted.moveNext();

        await expectLater(
          connect(expected_owner: 'different-owner'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Connected peer does not match the trusted owner.',
            ),
          ),
        );

        expect(await pending.timeout(operation_timeout), isTrue);

        final connected = accepted.current;
        peer = connected;

        connected.done.ignore();

        // Authentication failure must terminate the acquired
        // native connection without transmitting application data.
        final received = await connected.toList().timeout(operation_timeout);

        expect(received, isEmpty);

        expect(
          await FileSystemEntity.type(socket_path, followLinks: false),
          FileSystemEntityType.unixDomainSock,
        );
      } finally {
        peer?.destroy();

        await server.close();
        await accepted.cancel();
      }
    });

    test('client disposal preserves the listener endpoint', () async {
      final listener = await listen();

      final accepted = StreamIterator<TransportConnection>(
        listener.connections,
      );

      TransportConnection? first;
      TransportConnection? second;

      try {
        final first_pending = accepted.moveNext();

        first = await connect();

        expect(await first_pending.timeout(operation_timeout), isTrue);

        final first_server = accepted.current;

        final disconnected = first_server.incoming.drain<void>();

        await first.close();
        await disconnected.timeout(operation_timeout);

        expect(
          await FileSystemEntity.type(socket_path, followLinks: false),
          FileSystemEntityType.unixDomainSock,
        );

        // A subsequent client must be able to connect without
        // requiring listener restart or endpoint preparation.
        final second_pending = accepted.moveNext();

        second = await connect();

        expect(await second_pending.timeout(operation_timeout), isTrue);

        expect(accepted.current, isNot(same(first_server)));
        expect(second.os_user_id, owner);

        await first_server.close();
      } finally {
        await first?.close();
        await second?.close();
        await listener.close();
        await accepted.cancel();
      }
    });

    test('does not create a missing endpoint', () async {
      await expectLater(connect(), throwsA(isA<FileSystemException>()));

      expect(
        await FileSystemEntity.type(socket_path, followLinks: false),
        FileSystemEntityType.notFound,
      );
    });

    test('does not create a missing communication directory', () async {
      final missing_scope = '$scope/missing';

      await expectLater(
        transport.connect(scope_directory: missing_scope, os_user_id: owner),
        throwsA(isA<FileSystemException>()),
      );

      expect(await Directory(missing_scope).exists(), isFalse);
    });

    test('rejects and preserves a regular file endpoint', () async {
      final file = File(socket_path);

      await file.writeAsString('preserve me');

      await expectLater(connect(), throwsA(isA<FileSystemException>()));

      expect(await file.readAsString(), 'preserve me');
    });

    test('rejects and preserves a symbolic link endpoint', () async {
      final target = File('$scope/unrelated');

      await target.writeAsString('preserve me');

      final link = Link(socket_path);

      await link.create(target.path);

      await expectLater(connect(), throwsA(isA<FileSystemException>()));

      expect(
        await FileSystemEntity.type(socket_path, followLinks: false),
        FileSystemEntityType.link,
      );

      expect(await target.readAsString(), 'preserve me');
    });

    test('rejects communication scopes with shared permissions', () async {
      final permissions = await Process.run('chmod', ['0755', scope]);

      expect(permissions.exitCode, 0);

      await expectLater(connect(), throwsA(isA<FileSystemException>()));

      expect(
        await FileSystemEntity.type(socket_path, followLinks: false),
        FileSystemEntityType.notFound,
      );
    });

    test('rejects an empty trusted peer identity', () async {
      await expectLater(connect(expected_owner: ''), throwsArgumentError);

      expect(
        await FileSystemEntity.type(socket_path, followLinks: false),
        FileSystemEntityType.notFound,
      );
    });

    test('rejects relative communication scopes', () async {
      await expectLater(
        transport.connect(
          scope_directory: 'relative-directory',
          os_user_id: owner,
        ),
        throwsArgumentError,
      );
    });
  }, skip: !Platform.isMacOS);
}
