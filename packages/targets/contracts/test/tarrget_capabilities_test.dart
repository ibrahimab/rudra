import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('TargetCapabilities', () {
    test('defaults every feature to unknown', () {
      final capabilities = TargetCapabilities();

      for (final feature in TargetInspectionFeature.values) {
        expect(
          capabilities.status_for(feature),
          TargetCapabilityStatus.unknown,
        );
      }
    });

    test('reports supported features', () {
      final capabilities = TargetCapabilities(
        statuses: {
          TargetInspectionFeature.allocatedSize:
              TargetCapabilityStatus.supported,
        },
      );

      expect(
        capabilities.status_for(TargetInspectionFeature.allocatedSize),
        TargetCapabilityStatus.supported,
      );
    });

    test('reports unsupported features', () {
      final capabilities = TargetCapabilities(
        statuses: {
          TargetInspectionFeature.posixMode: TargetCapabilityStatus.unsupported,
        },
      );

      expect(
        capabilities.status_for(TargetInspectionFeature.posixMode),
        TargetCapabilityStatus.unsupported,
      );
    });

    test('preserves explicitly unknown features', () {
      final capabilities = TargetCapabilities(
        statuses: {
          TargetInspectionFeature.accessTime: TargetCapabilityStatus.unknown,
        },
      );

      expect(
        capabilities.status_for(TargetInspectionFeature.accessTime),
        TargetCapabilityStatus.unknown,
      );

      expect(
        capabilities.statuses.containsKey(TargetInspectionFeature.accessTime),
        isTrue,
      );
    });

    test('treats omitted features as unknown', () {
      final capabilities = TargetCapabilities(
        statuses: {
          TargetInspectionFeature.allocatedSize:
              TargetCapabilityStatus.supported,
        },
      );

      expect(
        capabilities.status_for(TargetInspectionFeature.filesystemIdentity),
        TargetCapabilityStatus.unknown,
      );
    });

    test('preserves independent capability statuses', () {
      final capabilities = TargetCapabilities(
        statuses: {
          TargetInspectionFeature.allocatedSize:
              TargetCapabilityStatus.supported,
          TargetInspectionFeature.posixMode: TargetCapabilityStatus.unsupported,
          TargetInspectionFeature.accessTime: TargetCapabilityStatus.unknown,
        },
      );

      expect(
        capabilities.status_for(TargetInspectionFeature.allocatedSize),
        TargetCapabilityStatus.supported,
      );

      expect(
        capabilities.status_for(TargetInspectionFeature.posixMode),
        TargetCapabilityStatus.unsupported,
      );

      expect(
        capabilities.status_for(TargetInspectionFeature.accessTime),
        TargetCapabilityStatus.unknown,
      );
    });

    test('defensively copies the supplied map', () {
      final statuses = <TargetInspectionFeature, TargetCapabilityStatus>{
        TargetInspectionFeature.allocatedSize: TargetCapabilityStatus.supported,
      };

      final capabilities = TargetCapabilities(statuses: statuses);

      statuses[TargetInspectionFeature.allocatedSize] =
          TargetCapabilityStatus.unsupported;

      expect(
        capabilities.status_for(TargetInspectionFeature.allocatedSize),
        TargetCapabilityStatus.supported,
      );
    });

    test('prevents modification of exposed statuses', () {
      final capabilities = TargetCapabilities(
        statuses: {
          TargetInspectionFeature.allocatedSize:
              TargetCapabilityStatus.supported,
        },
      );

      expect(
        () => capabilities.statuses[TargetInspectionFeature.allocatedSize] =
            TargetCapabilityStatus.unsupported,
        throwsUnsupportedError,
      );
    });

    test('distinguishes unsupported from unknown', () {
      expect(
        TargetCapabilityStatus.unsupported,
        isNot(TargetCapabilityStatus.unknown),
      );
    });

    test('an empty snapshot has no explicit statuses', () {
      final capabilities = TargetCapabilities();

      expect(capabilities.statuses, isEmpty);
    });
  });
}
