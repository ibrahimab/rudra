import 'dart:async';
import 'dart:io';

import 'package:rudra_host/rudra_host.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../support/test_host_ownership_provider.dart';

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

  /// Creates a composition sharing the configured ownership fixture.
  ///
  /// [scope] optionally supplies an alternative spelling of the
  /// persistence directory.
  HostComposition create_composition({Directory? scope}) => HostComposition(
    identity_provider: const _TestIdentityProvider(),
    ownership_provider: ownership,
    data_directory: scope ?? directory,
    target_id: 'test-target',
  );

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
      expect(await composition.database_file.exists(), isFalse);
    } finally {
      shutdown.complete();
      await running;
    }

    expect(ownership.is_owned, isFalse);
    expect(ownership.release_count, 1);
  });

  test('occupied scope rejects startup before persistence', () async {
    final canonical = await directory.resolveSymbolicLinks();

    final lease = await ownership.acquire(scope_directory: canonical);

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
      expect(await composition.database_file.exists(), isFalse);
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

  test('alternative directory spellings resolve to one scope', () async {
    final canonical = await directory.resolveSymbolicLinks();

    final composition = create_composition(
      scope: Directory('${directory.path}/.'),
    );

    await composition.run(shutdown: Future<void>.value(), on_ready: (_, _) {});

    expect(ownership.acquired_scopes, [canonical]);
    expect(ownership.release_count, 1);
  });

  test('a new composition can acquire a released scope', () async {
    for (var attempt = 0; attempt < 2; attempt++) {
      await create_composition().run(
        shutdown: Future<void>.value(),
        on_ready: (_, _) {},
      );
    }

    expect(ownership.acquired_scopes, hasLength(2));
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
