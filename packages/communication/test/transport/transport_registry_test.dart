import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_communication/src/transport/macos/unix/macos_unix_transport.dart'
    show macos_default_socket_path;
import 'package:test/test.dart';

void main() {
  test(
    'standard registration selects the macOS default without resolving it',
    () {
      final transport = TransportRegistry.standard.create_default('macos');
      expect(
        transport,
        isA<MacOsUnixTransport>().having(
          (value) => value.socket_path,
          'override',
          isNull,
        ),
      );
      expect(
        macos_default_socket_path(501),
        '/Library/Application Support/Rudra/runtime/501/rudra.sock',
      );
      expect(
        macos_default_socket_path(502),
        '/Library/Application Support/Rudra/runtime/502/rudra.sock',
      );
      expect(
        () => TransportRegistry.standard.create_default('windows'),
        throwsUnsupportedError,
      );
    },
  );

  test('registration does not activate available alternatives', () {
    final registry = TransportRegistry([
      (
        id: 'default',
        default_platform: 'fixture',
        create: (_) => const MacOsUnixTransport(),
      ),
      (
        id: 'alternative',
        default_platform: null,
        create: (_) => fail('Alternative selected.'),
      ),
    ]);

    expect(registry.create_default('fixture'), isA<MacOsUnixTransport>());
  });

  test('rejects duplicate implementation IDs and platform defaults', () {
    Transport create(Map<String, String> _) => const MacOsUnixTransport();
    expect(
      () => TransportRegistry([
        (id: 'unix', default_platform: 'macos', create: create),
        (id: 'unix', default_platform: null, create: create),
      ]),
      throwsArgumentError,
    );
    expect(
      () => TransportRegistry([
        (id: 'unix', default_platform: 'macos', create: create),
        (id: 'other', default_platform: 'macos', create: create),
      ]),
      throwsArgumentError,
    );
  });
}
