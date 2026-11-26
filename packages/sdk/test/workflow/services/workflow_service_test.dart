import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies workflow service composition and application admission.
///
/// Connection establishment is deliberately unavailable in these
/// tests. Host-backed operations must fail explicitly without
/// invoking native filesystem inspection or endpoint resolution.
void main() {
  late RudraSdk sdk;
  late int resolution_count;

  setUp(() {
    resolution_count = 0;

    sdk = RudraSdk(
      target_id: 'test-target',
      inspector: _UnusedInspector(),
      connection_setup: () {
        resolution_count++;

        throw StateError('Unexpected endpoint resolution.');
      },
    );
  });

  tearDown(() async {
    await sdk.close();
  });

  test('exposes one stable target-bound workflow service', () {
    final workflows = sdk.workflows;

    expect(workflows, isA<WorkflowService>());
    expect(workflows.target_id, sdk.target_id);
    expect(sdk.workflows, same(workflows));

    expect(sdk.is_connected, isFalse);
    expect(resolution_count, 0);
  });

  test(
    'rejects workflow access without configured host connectivity',
    () async {
      final local_sdk = RudraSdk(
        target_id: 'test-target',
        inspector: _UnusedInspector(),
      );

      try {
        expect(() => local_sdk.workflows, throwsStateError);

        await expectLater(local_sdk.read_state(), throwsStateError);
      } finally {
        await local_sdk.close();
      }
    },
  );

  test('Start requires an available authenticated connection', () async {
    await expectLater(
      sdk.workflows.start(
        root: TargetPath('/workspace'),
        idempotency_key: 'start-001',
      ),
      throwsStateError,
    );

    expect(resolution_count, 0);
    expect(sdk.resources_released, isTrue);
  });

  test('Stop requires an available authenticated connection', () async {
    await expectLater(
      sdk.workflows.stop(
        workflow_id: 'workflow-001',
        idempotency_key: 'stop-001',
      ),
      throwsStateError,
    );

    expect(resolution_count, 0);
    expect(sdk.resources_released, isTrue);
  });

  test('submission resolution requires an authenticated connection', () async {
    final receipt = EventSubmissionReceipt(
      event_id: 'event-001',
      correlation_id: 'correlation-001',
    );

    await expectLater(sdk.workflows.status_for(receipt), throwsStateError);

    expect(resolution_count, 0);
  });

  test('unavailable state is not represented as verified absence', () async {
    await expectLater(sdk.read_state(), throwsStateError);

    expect(resolution_count, 0);
  });

  test('rejects invalid Start arguments before forwarding', () async {
    await expectLater(
      sdk.workflows.start(root: TargetPath('/workspace'), idempotency_key: ' '),
      throwsArgumentError,
    );

    expect(resolution_count, 0);
  });

  test('rejects invalid Stop arguments before forwarding', () async {
    await expectLater(
      sdk.workflows.stop(workflow_id: ' ', idempotency_key: 'stop-001'),
      throwsArgumentError,
    );

    await expectLater(
      sdk.workflows.stop(workflow_id: 'workflow-001', idempotency_key: ' '),
      throwsArgumentError,
    );

    expect(resolution_count, 0);
  });

  test('retained workflow services cannot execute after SDK closure', () async {
    final workflows = sdk.workflows;

    await sdk.close();

    await expectLater(
      workflows.start(
        root: TargetPath('/workspace'),
        idempotency_key: 'start-001',
      ),
      throwsStateError,
    );

    await expectLater(sdk.read_state(), throwsStateError);

    expect(sdk.resources_released, isTrue);
    expect(resolution_count, 0);
  });
}

/// Rejects filesystem inspection in workflow capability tests.
///
/// Example:
/// ```dart
/// final sdk = RudraSdk(
///   target_id: 'test-target',
///   inspector: _UnusedInspector(),
/// );
/// ```
final class _UnusedInspector implements TargetInspector {
  /// Rejects the unexpected target operation in [invocation].
  ///
  /// Throws [UnsupportedError] for every inspection operation.
  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unexpected filesystem inspection: ${invocation.memberName}',
    );
  }
}
