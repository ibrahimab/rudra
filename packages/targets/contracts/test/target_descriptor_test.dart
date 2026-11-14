import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

/// Verifies the identity, capability, and immutability contracts.
void main() {
  group('TargetDescriptor', () {
    test('exposes its configured identity and platform', () {
      final target = TargetDescriptor(
        target_id: 'local-macos',
        display_name: 'Local macOS filesystem',
        platform: TargetPlatform.macos,
        capabilities: const <TargetCapability>{},
      );

      expect(target.target_id, 'local-macos');
      expect(target.display_name, 'Local macOS filesystem');
      expect(target.platform, TargetPlatform.macos);
    });

    test('reports supported and unsupported capabilities', () {
      final target = TargetDescriptor(
        target_id: 'readonly',
        display_name: 'Read-only target',
        platform: TargetPlatform.linux,
        capabilities: {TargetCapability.list_directory},
      );

      expect(target.supports(TargetCapability.list_directory), isTrue);

      expect(target.supports(TargetCapability.measure_usage), isFalse);
    });

    test('defensively copies the supplied capability set', () {
      final supplied_capabilities = <TargetCapability>{
        TargetCapability.list_directory,
      };

      final target = TargetDescriptor(
        target_id: 'local',
        display_name: 'Local filesystem',
        platform: TargetPlatform.macos,
        capabilities: supplied_capabilities,
      );

      // Changing the original set must not change the descriptor.
      supplied_capabilities.add(TargetCapability.measure_usage);

      expect(target.supports(TargetCapability.measure_usage), isFalse);

      // Consumers must not be able to mutate the descriptor's set.
      expect(
        () => target.capabilities.add(TargetCapability.inspect_metadata),
        throwsUnsupportedError,
      );
    });

    test('rejects empty and whitespace-only identifiers', () {
      expect(
        () => TargetDescriptor(
          target_id: '   ',
          display_name: 'Valid name',
          platform: TargetPlatform.macos,
          capabilities: const <TargetCapability>{},
        ),
        throwsArgumentError,
      );
    });

    test('rejects blank display names', () {
      expect(
        () => TargetDescriptor(
          target_id: 'valid-id',
          display_name: '',
          platform: TargetPlatform.macos,
          capabilities: const <TargetCapability>{},
        ),
        throwsArgumentError,
      );
    });
  });
}
