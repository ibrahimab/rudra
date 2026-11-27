import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:test/test.dart';

/// Verifies explicitly configured native listener execution
/// through the public communication API.
void main() {
  test('configured communication establishes a macOS Unix endpoint', () async {
    final directory = await Directory('/tmp')
        .createTemp('rudra-configured-transport-');

    addTearDown(() async {
      await directory.delete(recursive: true);
    });

    final scope = await directory.resolveSymbolicLinks();

    final socket_path = '$scope/rudra.sock';

    final communication = Communication(
      transport_configuration: TransportConfiguration.enabled([
        MacOsUnixTransport.endpoint(socket_path: socket_path),
      ]),
    );

    // Construction must not acquire native endpoint resources.
    expect(
      await FileSystemEntity.type(socket_path, followLinks: false),
      FileSystemEntityType.notFound,
    );

    expect(communication.resources_released, isTrue);

    await communication.run(
      shutdown: Future<void>.value(),
      on_startup: () async {
        expect(
          await FileSystemEntity.type(socket_path, followLinks: false),
          FileSystemEntityType.unixDomainSock,
        );

        expect(communication.resources_released, isFalse);
      },
    );

    expect(communication.resources_released, isTrue);

    expect(
      await FileSystemEntity.type(socket_path, followLinks: false),
      FileSystemEntityType.notFound,
    );
  }, skip: !Platform.isMacOS);

  test('unsupported native execution retains no resources', () async {
    final communication = Communication(
      transport_configuration: TransportConfiguration.enabled([
        MacOsUnixTransport.endpoint(socket_path: '/unused/rudra.sock'),
      ]),
    );

    await expectLater(
      communication.run(shutdown: Future<void>.value()),
      throwsA(isA<UnsupportedError>()),
    );

    expect(communication.resources_released, isTrue);
  }, skip: Platform.isMacOS);
}
