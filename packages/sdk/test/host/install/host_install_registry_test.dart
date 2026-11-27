import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('HostInstallRegistry', () {
    test('supports an empty configuration', () {
      final registry = HostInstallRegistry([]);

      expect(registry.installation_order, isEmpty);
      expect(registry.uninstallation_order, isEmpty);
    });

    test('preserves registration order for independent steps', () {
      final registry = HostInstallRegistry([
        RegistryStep('first'),
        RegistryStep('second'),
        RegistryStep('third'),
      ]);

      expect(registry.installation_order.map((step) => step.id), [
        'first',
        'second',
        'third',
      ]);
    });

    test('orders steps according to their prerequisites', () {
      final registry = HostInstallRegistry([
        RegistryStep('service', prerequisites: {'executable', 'storage'}),
        RegistryStep('executable', prerequisites: {'storage'}),
        RegistryStep('storage'),
      ]);

      expect(registry.installation_order.map((step) => step.id), [
        'storage',
        'executable',
        'service',
      ]);

      expect(registry.uninstallation_order.map((step) => step.id), [
        'service',
        'executable',
        'storage',
      ]);
    });

    test('resolves shared prerequisites without duplicate steps', () {
      final registry = HostInstallRegistry([
        RegistryStep('service', prerequisites: {'storage', 'executable'}),
        RegistryStep('executable', prerequisites: {'storage'}),
        RegistryStep('storage'),
      ]);

      expect(registry.installation_order, hasLength(3));
    });

    test('rejects blank step identifiers', () {
      expect(
        () => HostInstallRegistry([RegistryStep(' ')]),
        throwsArgumentError,
      );
    });

    test('rejects duplicate step identifiers', () {
      expect(
        () => HostInstallRegistry([
          RegistryStep('storage'),
          RegistryStep('storage'),
        ]),
        throwsStateError,
      );
    });

    test('rejects unknown prerequisites', () {
      expect(
        () => HostInstallRegistry([
          RegistryStep('service', prerequisites: {'missing'}),
        ]),
        throwsStateError,
      );
    });

    test('rejects self-referencing prerequisites', () {
      expect(
        () => HostInstallRegistry([
          RegistryStep('storage', prerequisites: {'storage'}),
        ]),
        throwsStateError,
      );
    });

    test('rejects cyclic dependencies', () {
      expect(
        () => HostInstallRegistry([
          RegistryStep('first', prerequisites: {'second'}),
          RegistryStep('second', prerequisites: {'third'}),
          RegistryStep('third', prerequisites: {'first'}),
        ]),
        throwsStateError,
      );
    });

    test('retains immutable ordered contributions', () {
      final steps = <HostInstallStep>[RegistryStep('storage')];

      final registry = HostInstallRegistry(steps);

      steps.clear();

      expect(registry.installation_order, hasLength(1));

      expect(() => registry.installation_order.clear(), throwsUnsupportedError);

      expect(
        () => registry.uninstallation_order.clear(),
        throwsUnsupportedError,
      );
    });
  });
}

/// Synthetic contribution exposing registration metadata only.
///
/// Resource operations fail if invoked during registry construction.
final class RegistryStep implements HostInstallStep {
  RegistryStep(this.id, {this.prerequisites = const {}});

  @override
  final String id;

  @override
  final Set<String> prerequisites;

  @override
  Future<HostInstallInspection> inspect(HostInstallOperation operation) async {
    fail('Registry must not inspect native resources.');
  }

  @override
  Future<void> install() async {
    fail('Registry must not install native resources.');
  }

  @override
  Future<void> uninstall() async {
    fail('Registry must not uninstall native resources.');
  }
}
