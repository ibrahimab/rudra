import 'dart:async';
import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_host/src/composition/host_composition.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import '../support/test_host_ownership_provider.dart';
import '../support/test_host_transport.dart';

/// Verifies host resource ownership and workflow restoration
/// using isolated development persistence.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'rudra-host-composition-',
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  /// Constructs an independent composition for the test directory.
  ///
  /// Returns a fresh composition with deterministic trusted ownership.
  HostComposition create_composition() => HostComposition(
    identity_provider: const _TestIdentityProvider(),
    ownership_provider: TestHostOwnershipProvider(),
    communication: Communication(transport: TestHostTransport()),
    data_directory: directory,
    target_id: 'test-target',
  );

  /// Executes one host lifecycle and returns its verified startup state.
  ///
  /// [startup_root] optionally requests explicit workflow establishment.
  /// The host receives its shutdown notification after reporting readiness.
  Future<WorkflowSnapshot?> run_once(
    HostComposition composition, {
    TargetPath? startup_root,
  }) async {
    final shutdown = Completer<void>();
    WorkflowSnapshot? current;

    await composition.run(
      shutdown: shutdown.future,
      startup_root: startup_root,
      on_ready: (os_user_id, workflow) {
        current = workflow;
        shutdown.complete();
      },
    );

    return current;
  }

  test('ordinary startup does not initialize persistence', () async {
    final composition = create_composition();

    final current = await run_once(composition);

    expect(current, isNull);
    expect(await composition.database_file.exists(), isFalse);
  });

  test('explicit startup establishes a durable workflow', () async {
    final composition = create_composition();

    final current = await run_once(
      composition,
      startup_root: TargetPath(directory.path),
    );

    expect(current, isNotNull);
    expect(current!.version, 1);
    expect(current.identity.os_user_id, 'test-owner');
    expect(current.identity.target_id, 'test-target');
    expect(current.identity.root.value, directory.path);

    expect(await composition.database_file.exists(), isTrue);
  });

  test('host restart restores the established workflow', () async {
    final started = await run_once(
      create_composition(),
      startup_root: TargetPath(directory.path),
    );

    // A fresh composition represents a new host lifecycle with
    // independently constructed application resources.
    final restored = await run_once(create_composition());

    expect(restored, isNotNull);
    expect(restored!.identity.workflow_id, started!.identity.workflow_id);
    expect(restored.version, started.version);
  });

  test('explicit startup rejects an existing workflow', () async {
    final started = await run_once(
      create_composition(),
      startup_root: TargetPath(directory.path),
    );

    await expectLater(
      run_once(create_composition(), startup_root: TargetPath(directory.path)),
      throwsA(
        isA<HostStartupWorkflowException>().having(
          (error) => error.outcome,
          'outcome',
          isA<WorkflowOperationResolved>().having(
            (outcome) => outcome.resolution.rejection_code,
            'rejection_code',
            WorkflowRejectionCode.ownership_conflict,
          ),
        ),
      ),
    );

    // Failed startup must release persistence without replacing
    // the authoritative workflow established by the previous host.
    final restored = await run_once(create_composition());

    expect(restored!.identity.workflow_id, started!.identity.workflow_id);
    expect(restored.version, 1);
  });

  test('a composition cannot execute twice', () async {
    final composition = create_composition();

    await run_once(composition);

    await expectLater(run_once(composition), throwsStateError);
  });
}

/// Supplies deterministic trusted ownership for composition tests.
final class _TestIdentityProvider implements HostIdentityProvider {
  /// Creates an identity provider with a fixed test identity.
  const _TestIdentityProvider();

  /// Returns the trusted owner reserved for these tests.
  @override
  Future<String> resolve() async => 'test-owner';
}
