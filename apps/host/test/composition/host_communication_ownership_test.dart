import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_host/rudra_host.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../support/test_host_ownership_provider.dart';
import '../support/test_host_transport.dart';

/// Verifies exclusive host ownership across communication disposal.
///
/// Uses synthetic communication and ownership resources with the
/// actual host application composition and persistence lifecycle.
void main() {
  late Directory directory;
  late TestHostOwnershipProvider ownership;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'rudra-host-communication-',
    );

    ownership = TestHostOwnershipProvider();
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  /// Constructs a host composition with controlled communication.
  ///
  /// [communication_factory] supplies the communication implementation
  /// using the host's validated application messaging configuration.
  ///
  /// Returns a composition sharing the fixture's exclusive ownership
  /// provider and isolated persistence directory.
  HostComposition create_composition(
    HostCommunicationFactory communication_factory,
  ) => HostComposition(
    identity_provider: const _TestIdentityProvider(),
    ownership_provider: ownership,
    data_directory: directory,
    target_id: 'test-target',
    communication_factory: communication_factory,
  );

  test('communication disposes before ownership is released', () async {
    final transport = TestHostTransport(
      on_close: () {
        expect(ownership.is_owned, isTrue);
        expect(ownership.release_count, 0);
      },
    );

    late final Communication communication;

    final composition = create_composition(({
      required codecs,
      required handlers,
    }) {
      communication = Communication(
        transport: transport,
        codecs: codecs,
        handlers: handlers,
      );

      return communication;
    });

    await composition.run(
      shutdown: Future<void>.value(),
      on_ready: (_, _) {
        expect(ownership.is_owned, isTrue);
        expect(communication.resources_released, isFalse);
      },
    );

    expect(transport.listen_count, 1);
    expect(transport.close_count, 1);
    expect(communication.resources_released, isTrue);
    expect(ownership.is_owned, isFalse);
    expect(ownership.release_count, 1);
    expect(await composition.database_file.exists(), isFalse);
  });

  test('failed communication disposal retains exclusive ownership', () async {
    final failure = StateError('Controlled communication disposal failure.');

    final transport = TestHostTransport(
      on_close: () {
        expect(ownership.is_owned, isTrue);

        throw failure;
      },
    );

    late final Communication communication;

    final composition = create_composition(({
      required codecs,
      required handlers,
    }) {
      communication = Communication(
        transport: transport,
        codecs: codecs,
        handlers: handlers,
      );

      return communication;
    });

    await expectLater(
      composition.run(shutdown: Future<void>.value(), on_ready: (_, _) {}),
      throwsA(same(failure)),
    );

    expect(communication.resources_released, isFalse);
    expect(transport.close_count, 0);
    expect(ownership.is_owned, isTrue);
    expect(ownership.release_count, 0);

    final competing_transport = TestHostTransport();

    final competing = create_composition(
      ({required codecs, required handlers}) => Communication(
        transport: competing_transport,
        codecs: codecs,
        handlers: handlers,
      ),
    );

    // Unconfirmed communication disposal must prevent a competing
    // host from acquiring the same application scope.
    await expectLater(
      competing.run(
        shutdown: Future<void>.value(),
        on_ready: (_, _) {
          fail('Competing host must not report readiness.');
        },
      ),
      throwsA(isA<HostAlreadyOwnedException>()),
    );

    expect(competing_transport.listen_count, 0);
    expect(ownership.release_count, 0);
  });
}

/// Supplies deterministic trusted identity for host ownership tests.
///
/// Example:
/// ```dart
/// final owner = await _TestIdentityProvider().resolve();
/// assert(owner == 'test-owner');
/// ```
final class _TestIdentityProvider implements HostIdentityProvider {
  /// Creates a deterministic trusted identity provider.
  const _TestIdentityProvider();

  /// Returns the operating-system identity reserved for the test scope.
  @override
  Future<String> resolve() async => 'test-owner';
}
