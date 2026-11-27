import 'dart:async';
import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_host/rudra_host.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../support/test_host_ownership_provider.dart';
import '../support/test_host_transport.dart';
import '../support/unused_target_inspector.dart';
import '../support/host_test_transport_registry.dart';

/// Verifies exclusive ownership at the host composition boundary.
///
/// Native locking is tested independently. These tests establish
/// the ordering and lifetime of application-owned resources.
void main() {
  late Directory directory;
  late TestHostOwnershipProvider ownership;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rudra-host-ownership-');

    ownership = TestHostOwnershipProvider();
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  File database(String directory_path) => File('$directory_path/rudra.sqlite');

  HostComposition create_composition({
    File Function()? resolve_database,
    TestHostTransport? transport,
  }) => HostComposition(
    identity_provider: const _TestIdentityProvider(),
    ownership_provider: ownership,
    resolve_database: resolve_database ?? () => database(directory.path),
    target_id: 'test-target',
    inspector: const UnusedTargetInspector(),
    communication_factory: ({required codecs, required handlers}) {
      expect(ownership.is_owned, isTrue);
      return Communication(
        transport_registry: host_test_transport_registry(
          transport ?? TestHostTransport(),
        ),
        codecs: codecs,
        handlers: handlers,
      );
    },
  );

  test(
    'acquires ownership before resolving storage or binding listeners',
    () async {
      var resolutions = 0;
      final transport = TestHostTransport();

      final composition = create_composition(
        transport: transport,
        resolve_database: () {
          resolutions++;
          expect(ownership.is_owned, isTrue);
          expect(ownership.acquire_count, 1);
          expect(transport.listen_count, 0);
          return database(directory.path);
        },
      );

      expect(resolutions, 0);
      await composition.run(
        shutdown: Future<void>.value(),
        on_ready: (_, _) {
          expect(resolutions, 1);
          expect(transport.listen_count, 1);
        },
      );

      expect(resolutions, 1);
      expect(transport.close_count, 1);
      expect(ownership.is_owned, isFalse);
    },
  );

  test(
    'occupied user prevents another database or endpoint from activating',
    () async {
      final lease = await ownership.acquire();
      final other_transport = TestHostTransport();

      try {
        final composition = create_composition(
          transport: other_transport,
          resolve_database: () =>
              fail('Competing host must not resolve storage.'),
        );

        await expectLater(
          composition.run(
            shutdown: Future<void>.value(),
            on_ready: (_, _) =>
                fail('Competing host must not report readiness.'),
          ),
          throwsA(isA<HostAlreadyOwnedException>()),
        );

        expect(other_transport.listen_count, 0);
        expect(ownership.is_owned, isTrue);
      } finally {
        await lease.release();
      }
    },
  );

  test('failed storage resolution releases acquired ownership', () async {
    final failure = StateError('Controlled storage resolution failure.');
    final transport = TestHostTransport();
    final composition = create_composition(
      transport: transport,
      resolve_database: () {
        expect(ownership.is_owned, isTrue);
        throw failure;
      },
    );

    await expectLater(
      composition.run(
        shutdown: Future<void>.value(),
        on_ready: (_, _) =>
            fail('Failed configuration must not report readiness.'),
      ),
      throwsA(same(failure)),
    );

    expect(transport.listen_count, 0);
    expect(ownership.is_owned, isFalse);
    expect(ownership.release_count, 1);
  });

  test('ownership remains acquired throughout execution', () async {
    final composition = create_composition();

    final ready = Completer<void>();
    final shutdown = Completer<void>();

    final running = composition.run(
      shutdown: shutdown.future,
      on_ready: (_, _) {
        ready.complete();
      },
    );

    try {
      await Future.any([ready.future, running]);

      expect(ready.isCompleted, isTrue);
      expect(ownership.is_owned, isTrue);
      expect(ownership.release_count, 0);

      // Ownership acquisition must not initialize workflow storage.
      expect(await database(directory.path).exists(), isFalse);
    } finally {
      shutdown.complete();
      await running;
    }

    expect(ownership.is_owned, isFalse);
    expect(ownership.release_count, 1);
  });

  test('occupied scope rejects startup before persistence', () async {
    final lease = await ownership.acquire();

    final composition = create_composition();

    try {
      await expectLater(
        composition.run(
          shutdown: Future<void>.value(),
          startup_root: TargetPath(directory.path),
          on_ready: (_, _) {
            fail('Rejected ownership must not report readiness.');
          },
        ),
        throwsA(isA<HostAlreadyOwnedException>()),
      );

      // Even an explicit workflow Start must not initialize
      // persistence after unsuccessful ownership acquisition.
      expect(await database(directory.path).exists(), isFalse);
      expect(ownership.is_owned, isTrue);
    } finally {
      await lease.release();
    }
  });

  test('failed startup releases acquired ownership', () async {
    final composition = create_composition();

    await expectLater(
      composition.run(
        shutdown: Future<void>.value(),
        on_ready: (_, _) {
          throw StateError('Controlled startup failure.');
        },
      ),
      throwsStateError,
    );

    expect(ownership.is_owned, isFalse);
    expect(ownership.release_count, 1);
  });

  test('a new composition can acquire a released scope', () async {
    for (var attempt = 0; attempt < 2; attempt++) {
      await create_composition().run(
        shutdown: Future<void>.value(),
        on_ready: (_, _) {},
      );
    }

    expect(ownership.acquire_count, 2);
    expect(ownership.release_count, 2);
    expect(ownership.is_owned, isFalse);
  });
}

/// Supplies deterministic identity for ownership composition tests.
///
/// Example:
/// ```dart
/// final owner = await _TestIdentityProvider().resolve();
/// ```
final class _TestIdentityProvider implements HostIdentityProvider {
  /// Creates a deterministic test identity provider.
  const _TestIdentityProvider();

  /// Returns the trusted identity reserved for the test scope.
  @override
  Future<String> resolve() async => 'test-owner';
}
