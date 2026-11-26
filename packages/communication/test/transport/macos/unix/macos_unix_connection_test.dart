import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:test/test.dart';

/// Verifies native connection disposal during active transmission.
///
/// Exercises both independently owned outbound connections and
/// connections retained by a native listener.
void main() {
  late MacOsUnixTransport transport;

  const operation_timeout = Duration(seconds: 15);

  // Exceeds ordinary native socket buffering capacity while the
  // receiving peer deliberately does not consume incoming bytes.
  const stalled_write_size = 8 * 1024 * 1024;

  late Directory directory;
  late String scope;

  group('MacOsUnixConnection disposal', () {
    setUp(() async {
      directory = await Directory('/tmp').createTemp('rudra-connection-');

      scope = await directory.resolveSymbolicLinks();

      transport = MacOsUnixTransport(socket_path: '$scope/rudra.sock');
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    for (final close_listener in [false, true]) {
      final description = close_listener
          ? 'listener closure interrupts accepted connection writes'
          : 'client closure interrupts outbound connection writes';

      test(description, () async {
        final listener = await transport.listen();

        final accepted = StreamIterator<TransportConnection>(
          listener.connections,
        );

        TransportConnection? client;

        try {
          final pending = accepted.moveNext();

          final connected = await transport.connect();

          client = connected;

          expect(await pending.timeout(operation_timeout), isTrue);

          final connection = close_listener ? accepted.current : connected;

          // The receiving peer remains connected but does not
          // consume incoming data. Initiate termination while
          // the native transmission remains outstanding.
          final write = connection.send(Uint8List(stalled_write_size));

          final write_failed = expectLater(
            write.timeout(operation_timeout),
            throwsStateError,
          );

          if (close_listener) {
            await listener.close().timeout(operation_timeout);
          } else {
            final first = connection.close();
            final second = connection.close();

            expect(second, same(first));

            await first.timeout(operation_timeout);
          }

          await write_failed;

          // Successful disposal permanently prohibits further
          // transmission through this connection.
          await expectLater(
            connection.send(Uint8List.fromList([0x01])),
            throwsStateError,
          );

          await connection.close();
        } finally {
          await client?.close();
          await listener.close();
          await accepted.cancel();
        }
      });
    }

    test('rejects overlapping native transport writes', () async {
      final listener = await transport.listen();

      final accepted = StreamIterator<TransportConnection>(
        listener.connections,
      );

      TransportConnection? client;

      try {
        final pending = accepted.moveNext();

        final connected = await transport.connect();

        client = connected;

        expect(await pending.timeout(operation_timeout), isTrue);

        final first = connected.send(Uint8List(stalled_write_size));

        final interrupted = expectLater(
          first.timeout(operation_timeout),
          throwsStateError,
        );

        await expectLater(
          connected.send(Uint8List.fromList([0x01])),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Concurrent transport writes are prohibited.',
            ),
          ),
        );

        await connected.close().timeout(operation_timeout);
        await interrupted;
      } finally {
        await client?.close();
        await listener.close();
        await accepted.cancel();
      }
    });
  }, skip: !Platform.isMacOS);
}
