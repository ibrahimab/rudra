import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:rudra_communication/rudra_communication.dart';

import '../../../support/macos_test_identity.dart';

import 'package:test/test.dart';

/// Verifies authenticated local transport on macOS.
///
/// Exercises native endpoint protection, peer authorization,
/// independent connections and listener resource disposal.
void main() {
  const transport = MacOsUnixTransport();

  const operation_timeout = Duration(seconds: 15);

  late Directory directory;
  late String scope;
  late String owner;

  late String socket_path;
  late InternetAddress address;

  group('MacOsUnixTransport', () {
    setUp(() async {
      // A newly created private directory gives each test its
      // own exclusively controlled communication scope.
      directory = await Directory('/tmp').createTemp('rudra-transport-');

      scope = await directory.resolveSymbolicLinks();
      owner = await resolve_macos_test_identity();

      socket_path = '$scope/${MacOsUnixTransport.socket_filename}';

      address = InternetAddress(socket_path, type: InternetAddressType.unix);
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    /// Opens a listener for the trusted fixture owner.
    ///
    /// [authorized_owner] optionally overrides authorization
    /// to exercise rejection of a kernel-authenticated peer.
    Future<TransportListener> listen({String? authorized_owner}) => transport
        .listen(scope_directory: scope, os_user_id: authorized_owner ?? owner);

    /// Establishes a native client connection.
    ///
    /// Returns the connected socket or propagates native
    /// connection and timeout failures.
    Future<Socket> connect() async {
      final socket = await Socket.connect(
        address,
        0,
        timeout: operation_timeout,
      );

      socket.done.ignore();

      return socket;
    }

    test('accepts multiple authenticated connections', () async {
      final listener = await listen();

      final connections = StreamIterator<TransportConnection>(
        listener.connections,
      );

      Socket? first_client;
      Socket? second_client;

      try {
        final first_pending = connections.moveNext();
        first_client = await connect();

        expect(await first_pending.timeout(operation_timeout), isTrue);

        final first = connections.current;

        final second_pending = connections.moveNext();
        second_client = await connect();

        expect(await second_pending.timeout(operation_timeout), isTrue);

        final second = connections.current;

        expect(first.os_user_id, owner);
        expect(second.os_user_id, owner);
        expect(identical(first, second), isFalse);

        // Each accepted client retains its own byte stream.
        final first_request = first.incoming.first;
        final second_request = second.incoming.first;

        first_client.add([0x01]);
        second_client.add([0x02]);

        await first_client.flush();
        await second_client.flush();

        expect(await first_request.timeout(operation_timeout), [0x01]);

        expect(await second_request.timeout(operation_timeout), [0x02]);
      } finally {
        first_client?.destroy();
        second_client?.destroy();

        await listener.close();
        await connections.cancel();
      }
    });

    test('transfers bytes in both directions', () async {
      final listener = await listen();

      final connections = StreamIterator<TransportConnection>(
        listener.connections,
      );

      Socket? client;

      try {
        final pending = connections.moveNext();
        client = await connect();

        expect(await pending.timeout(operation_timeout), isTrue);

        final connection = connections.current;

        final incoming = StreamIterator<Uint8List>(connection.incoming);

        try {
          client.add([0x01]);
          await client.flush();

          expect(await incoming.moveNext().timeout(operation_timeout), isTrue);

          expect(incoming.current, [0x01]);

          final response = client.first;

          await connection.send(Uint8List.fromList([0x02]));

          expect(await response.timeout(operation_timeout), [0x02]);
        } finally {
          await incoming.cancel();
        }
      } finally {
        client?.destroy();

        await listener.close();
        await connections.cancel();
      }
    });

    test('rejects a peer outside the authorized owner scope', () async {
      final listener = await listen(authorized_owner: 'different-owner');

      final accepted = <TransportConnection>[];

      final subscription = listener.connections.listen(accepted.add);

      Socket? client;

      try {
        client = await connect();

        // Authorization rejection closes the native socket
        // without delivering an SDK connection.
        await client.drain<void>().timeout(operation_timeout);

        expect(accepted, isEmpty);
      } finally {
        client?.destroy();

        await listener.close();
        await subscription.cancel();
      }
    });

    test('preserves a regular file at the endpoint', () async {
      final file = File(socket_path);

      await file.writeAsString('preserve me');

      await expectLater(listen(), throwsA(isA<FileSystemException>()));

      expect(await file.readAsString(), 'preserve me');
    });

    test('preserves a symbolic link at the endpoint', () async {
      final target = File('$scope/unrelated');

      await target.writeAsString('preserve me');

      final link = Link(socket_path);
      await link.create(target.path);

      await expectLater(listen(), throwsA(isA<FileSystemException>()));

      expect(
        await FileSystemEntity.type(socket_path, followLinks: false),
        FileSystemEntityType.link,
      );

      expect(await target.readAsString(), 'preserve me');
    });

    test('refuses to replace a live endpoint', () async {
      final existing = await ServerSocket.bind(address, 0);

      final subscription = existing.listen((socket) {
        socket.done.ignore();
        socket.destroy();
      });

      try {
        await expectLater(listen(), throwsA(isA<FileSystemException>()));

        expect(
          await FileSystemEntity.type(socket_path, followLinks: false),
          FileSystemEntityType.unixDomainSock,
        );
      } finally {
        await existing.close();
        await subscription.cancel();
      }
    });

    test('close terminates accepted connections', () async {
      final listener = await listen();

      final connections = StreamIterator<TransportConnection>(
        listener.connections,
      );

      Socket? client;

      try {
        final pending = connections.moveNext();
        client = await connect();

        expect(await pending.timeout(operation_timeout), isTrue);

        final connection = connections.current;
        final disconnected = client.drain<void>();

        await listener.close();

        await disconnected.timeout(operation_timeout);

        await expectLater(
          connection.send(Uint8List.fromList([0x01])),
          throwsStateError,
        );

        expect(
          await FileSystemEntity.type(socket_path, followLinks: false),
          FileSystemEntityType.notFound,
        );

        // Repeated disposal must not affect subsequent listeners.
        await listener.close();
      } finally {
        client?.destroy();

        await listener.close();
        await connections.cancel();
      }
    });

    test('can bind again after graceful listener disposal', () async {
      final first = await listen();
      await first.close();

      final second = await listen();
      await second.close();
    });
  }, skip: !Platform.isMacOS);
}
