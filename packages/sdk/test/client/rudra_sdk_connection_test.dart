import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies mandatory SDK connection composition and lifecycle.
void main() {
  test('construction retains configuration without resolving it', () async {
    var resolutions = 0;

    final sdk = RudraSdk(
      target_id: 'local-macos',
      connection_setup: () {
        resolutions++;

        return (scope_directory: '/unused-scope', os_user_id: 'trusted-owner');
      },
      communication_factory: ({required codecs, required handlers}) {
        throw StateError(
          'Communication must not be constructed during initialization.',
        );
      },
    );

    addTearDown(sdk.close);

    expect(resolutions, 0);
    expect(sdk.is_connected, isFalse);
    expect(sdk.resources_released, isTrue);

    await sdk.close();

    expect(resolutions, 0);
    expect(sdk.resources_released, isTrue);

    await expectLater(sdk.connect(), throwsStateError);
    await expectLater(sdk.reconnect(), throwsStateError);
  });

  test('resolves the trusted endpoint during explicit connection', () async {
    var resolutions = 0;

    final sdk = RudraSdk(
      target_id: 'local-macos',
      connection_setup: () {
        resolutions++;

        throw StateError('Configured host is unavailable.');
      },
    );

    addTearDown(sdk.close);

    expect(resolutions, 0);

    await expectLater(sdk.connect(), throwsStateError);

    expect(resolutions, 1);
    expect(sdk.is_connected, isFalse);
    expect(sdk.resources_released, isTrue);

    await expectLater(sdk.reconnect(), throwsStateError);

    expect(resolutions, 2);
    expect(sdk.resources_released, isTrue);
  });
}
