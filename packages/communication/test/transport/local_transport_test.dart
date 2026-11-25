import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:test/test.dart';

import '../support/macos_test_identity.dart';

/// Verifies default native transport selection through the public API.
void main() {
  test('default communication establishes a macOS Unix endpoint', () async {
    final directory = await Directory('/tmp')
        .createTemp('rudra-local-transport-');

    addTearDown(() async {
      await directory.delete(recursive: true);
    });

    final scope = await directory.resolveSymbolicLinks();
    final owner = await resolve_macos_test_identity();

    final socket_path = '$scope/${MacOsUnixTransport.socket_filename}';

    final communication = Communication();

    expect(
      await FileSystemEntity.type(socket_path, followLinks: false),
      FileSystemEntityType.notFound,
    );

    await communication.run(
      scope_directory: scope,
      os_user_id: owner,
      shutdown: Future<void>.value(),
      handle_connection: (_) async {
        fail('No client connection is expected.');
      },
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

  test('unsupported platforms fail without acquiring resources', () async {
    final communication = Communication();

    await expectLater(
      communication.run(
        scope_directory: '/unused',
        os_user_id: 'test-owner',
        shutdown: Future<void>.value(),
        handle_connection: (_) async {},
        on_startup: () async {
          fail('Unsupported transport must not report readiness.');
        },
      ),
      throwsA(isA<UnsupportedError>()),
    );

    expect(communication.resources_released, isTrue);
  }, skip: Platform.isMacOS);
}
