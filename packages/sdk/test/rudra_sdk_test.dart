import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies mandatory host-backed SDK composition.
void main() {
  late int resolutions;
  late RudraSdk sdk;

  setUp(() {
    resolutions = 0;

    sdk = RudraSdk(
      target_id: 'test-target',
      connection_setup: () {
        resolutions++;

        throw StateError('Unexpected endpoint resolution.');
      },
    );
  });

  tearDown(() async {
    await sdk.close();
  });

  group('RudraSdk', () {
    test('composes application services without acquiring resources', () {
      expect(sdk.target_id, 'test-target');
      expect(sdk.filesystem.target_id, sdk.target_id);
      expect(sdk.workflows.target_id, sdk.target_id);

      expect(sdk.is_connected, isFalse);
      expect(sdk.resources_released, isTrue);
      expect(resolutions, 0);
    });

    test('retains stable application service identities', () {
      final filesystem = sdk.filesystem;
      final workflows = sdk.workflows;

      expect(sdk.filesystem, same(filesystem));
      expect(sdk.workflows, same(workflows));
    });

    test('filesystem inspection requires authenticated connectivity', () async {
      await expectLater(
        sdk.filesystem.list(directory: TargetPath('/workspace')),
        throwsStateError,
      );

      expect(resolutions, 0);
      expect(sdk.resources_released, isTrue);
    });

    test('retained filesystem services cannot execute after closure', () async {
      final filesystem = sdk.filesystem;

      await sdk.close();

      await expectLater(
        filesystem.list(directory: TargetPath('/workspace')),
        throwsStateError,
      );

      expect(resolutions, 0);
      expect(sdk.resources_released, isTrue);
    });

    test('rejects invalid target identifiers', () {
      for (final target_id in ['', ' ', '\t\n']) {
        expect(
          () => RudraSdk(
            target_id: target_id,
            connection_setup: () {
              throw StateError('Unexpected endpoint resolution.');
            },
          ),
          throwsArgumentError,
        );
      }
    });

    test('keeps independently configured SDK instances isolated', () async {
      final second = RudraSdk(
        target_id: 'second-target',
        connection_setup: () {
          throw StateError('Unexpected endpoint resolution.');
        },
      );

      addTearDown(second.close);

      expect(sdk.target_id, 'test-target');
      expect(second.target_id, 'second-target');

      expect(sdk.filesystem, isNot(same(second.filesystem)));
      expect(sdk.workflows, isNot(same(second.workflows)));

      await sdk.close();

      expect(second.filesystem.target_id, 'second-target');
      expect(second.resources_released, isTrue);
    });
  });
}
