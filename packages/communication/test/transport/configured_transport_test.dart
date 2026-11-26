import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:test/test.dart';

import '../support/macos_test_identity.dart';

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
    final owner = await resolve_macos_test_identity();

    final socket_path = '$scope/${MacOsUnixTransport.socket_filename}';

    final transport = MacOsUnixTransport(
      scope_directory: scope,
      os_user_id: owner,
    );

    final communication = Communication(transport: transport);

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
    const transport = MacOsUnixTransport(
      scope_directory: '/unused',
      os_user_id: 'test-owner',
    );

    final communication = Communication(transport: transport);

    await expectLater(
      communication.run(shutdown: Future<void>.value()),
      throwsA(isA<UnsupportedError>()),
    );

    expect(communication.resources_released, isTrue);
  }, skip: Platform.isMacOS);
}
