import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('HostPlatformRegistry', () {
    test('supports an empty plugin configuration', () {
      final registry = HostPlatformRegistry([]);

      expect(registry.find<ServiceCapability>(), isNull);
    });

    test('resolves a capability by its declared contract', () {
      final service = ServiceImplementation();

      final registry = HostPlatformRegistry([
        TestPlugin(
          id: 'service',
          contribute: (registration) {
            registration.add<ServiceCapability>(service);
          },
        ),
      ]);

      expect(registry.require<ServiceCapability>(), same(service));

      expect(registry.find<ServiceImplementation>(), isNull);
    });

    test('independent plugins contribute independent capabilities', () {
      final service = ServiceImplementation();
      const power = PowerImplementation();

      final registry = HostPlatformRegistry([
        TestPlugin(
          id: 'service',
          contribute: (registration) {
            registration.add<ServiceCapability>(service);
          },
        ),
        TestPlugin(
          id: 'power',
          contribute: (registration) {
            registration.add<PowerCapability>(power);
          },
        ),
      ]);

      expect(registry.require<ServiceCapability>(), same(service));

      expect(registry.require<PowerCapability>(), same(power));
    });

    test('one plugin may contribute multiple capabilities', () {
      final service = ServiceImplementation();
      const power = PowerImplementation();

      final registry = HostPlatformRegistry([
        TestPlugin(
          id: 'combined',
          contribute: (registration) {
            registration.add<ServiceCapability>(service);
            registration.add<PowerCapability>(power);
          },
        ),
      ]);

      expect(registry.require<ServiceCapability>(), same(service));

      expect(registry.require<PowerCapability>(), same(power));
    });

    test('registration and lookup do not activate capabilities', () {
      final service = ServiceImplementation();

      final registry = HostPlatformRegistry([
        TestPlugin(
          id: 'service',
          contribute: (registration) {
            registration.add<ServiceCapability>(service);
          },
        ),
      ]);

      expect(service.activation_count, 0);

      final capability = registry.require<ServiceCapability>();

      expect(service.activation_count, 0);

      capability.activate();

      expect(service.activation_count, 1);
    });

    test('rejects blank plugin identifiers', () {
      expect(
        () => HostPlatformRegistry([
          TestPlugin(
            id: ' ',
            contribute: (_) {
              fail('Invalid plugin must not register capabilities.');
            },
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects duplicate plugin identifiers', () {
      expect(
        () => HostPlatformRegistry([
          TestPlugin(id: 'duplicate', contribute: (_) {}),
          TestPlugin(
            id: 'duplicate',
            contribute: (_) {
              fail('Duplicate plugin must not be registered.');
            },
          ),
        ]),
        throwsStateError,
      );
    });

    test('rejects duplicate capabilities from one plugin', () {
      expect(
        () => HostPlatformRegistry([
          TestPlugin(
            id: 'service',
            contribute: (registration) {
              registration.add<ServiceCapability>(ServiceImplementation());

              registration.add<ServiceCapability>(ServiceImplementation());
            },
          ),
        ]),
        throwsStateError,
      );
    });

    test('rejects conflicting providers across plugins', () {
      expect(
        () => HostPlatformRegistry([
          TestPlugin(
            id: 'first',
            contribute: (registration) {
              registration.add<ServiceCapability>(ServiceImplementation());
            },
          ),
          TestPlugin(
            id: 'second',
            contribute: (registration) {
              registration.add<ServiceCapability>(ServiceImplementation());
            },
          ),
        ]),
        throwsStateError,
      );
    });

    test('missing optional capabilities return null', () {
      final registry = HostPlatformRegistry([]);

      expect(registry.find<PowerCapability>(), isNull);
    });

    test('missing required capabilities fail explicitly', () {
      final registry = HostPlatformRegistry([]);

      expect(registry.require<PowerCapability>, throwsStateError);
    });

    test('registration scopes close after plugin registration', () {
      late HostPlatformRegistration retained_registration;

      final registry = HostPlatformRegistry([
        TestPlugin(
          id: 'service',
          contribute: (registration) {
            retained_registration = registration;

            registration.add<ServiceCapability>(ServiceImplementation());
          },
        ),
      ]);

      expect(
        () => retained_registration.add<PowerCapability>(
          const PowerImplementation(),
        ),
        throwsStateError,
      );

      expect(registry.find<PowerCapability>(), isNull);
    });

    test('plugin failures propagate and close registration scopes', () {
      late HostPlatformRegistration retained_registration;

      final failure = StateError('Registration failed.');

      expect(
        () => HostPlatformRegistry([
          TestPlugin(
            id: 'failing',
            contribute: (registration) {
              retained_registration = registration;

              registration.add<ServiceCapability>(ServiceImplementation());

              throw failure;
            },
          ),
        ]),
        throwsA(same(failure)),
      );

      expect(
        () => retained_registration.add<PowerCapability>(
          const PowerImplementation(),
        ),
        throwsStateError,
      );
    });

    test('independent registries retain independent providers', () {
      final first_service = ServiceImplementation();
      final second_service = ServiceImplementation();

      final first = HostPlatformRegistry([
        TestPlugin(
          id: 'service',
          contribute: (registration) {
            registration.add<ServiceCapability>(first_service);
          },
        ),
      ]);

      final second = HostPlatformRegistry([
        TestPlugin(
          id: 'service',
          contribute: (registration) {
            registration.add<ServiceCapability>(second_service);
          },
        ),
      ]);

      expect(first.require<ServiceCapability>(), same(first_service));

      expect(second.require<ServiceCapability>(), same(second_service));
    });
  });
}

/// Synthetic service capability used to verify explicit activation.
abstract interface class ServiceCapability {
  void activate();
}

/// Inactive service implementation recording activation requests.
final class ServiceImplementation implements ServiceCapability {
  int activation_count = 0;

  @override
  void activate() {
    activation_count++;
  }
}

/// Independent synthetic capability used to verify typed registration.
abstract interface class PowerCapability {}

/// Inactive implementation of the synthetic power capability.
final class PowerImplementation implements PowerCapability {
  const PowerImplementation();
}

/// Synthetic plugin delegating registration to a test-owned callback.
final class TestPlugin implements HostPlatformPlugin {
  const TestPlugin({required this.id, required this.contribute});

  @override
  final String id;

  final void Function(HostPlatformRegistration) contribute;

  @override
  void register(HostPlatformRegistration registration) {
    contribute(registration);
  }
}
