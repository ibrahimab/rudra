import 'dart:convert';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/workflow/messaging/outcomes/workflow_operation_outcome.dart';
import 'package:rudra_sdk/src/workflow/messaging/outcomes/workflow_operation_outcome_codec.dart';
import 'package:test/test.dart';

/// Verifies typed workflow operation outcome representations.
void main() {
  const codec = WorkflowOperationOutcomeCodec();

  final receipt = EventSubmissionReceipt(
    event_id: 'event-001',
    correlation_id: 'correlation-001',
  );

  final pending_payload = <String, Object?>{
    'receipt': {
      'event_id': receipt.event_id,
      'correlation_id': receipt.correlation_id,
    },
    'state': 'pending',
  };

  group('operation outcomes', () {
    test('round-trips a resolved pending operation', () {
      final outcome = WorkflowOperationResolved(
        resolution: WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.pending,
        ),
      );

      final payload = codec.encode(outcome);

      expect(payload, {'kind': 'resolved', 'resolution': pending_payload});

      final restored = codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored, isA<WorkflowOperationResolved>());

      final resolution = (restored as WorkflowOperationResolved).resolution;

      expect(resolution.state, WorkflowSubmissionState.pending);
      expect(resolution.receipt.event_id, receipt.event_id);

      expect(resolution.receipt.correlation_id, receipt.correlation_id);
    });

    test('round-trips a resolved completed operation', () {
      final outcome = WorkflowOperationResolved(
        resolution: WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.completed,
          committed_outcome: WorkflowCommittedOutcome(
            workflow_id: 'workflow-001',
            event_type: WorkflowStartedEvent.type_id,
            version: 1,
            sequence: 42,
          ),
        ),
      );

      final payload = codec.encode(outcome);

      final restored = codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored, isA<WorkflowOperationResolved>());

      final resolution = (restored as WorkflowOperationResolved).resolution;

      expect(resolution.state, WorkflowSubmissionState.completed);
      expect(resolution.committed_outcome!.workflow_id, 'workflow-001');

      expect(codec.encode(restored), payload);
    });

    test('preserves an expected business rejection', () {
      const timestamp = 1795618800000;

      final outcome = WorkflowOperationResolved(
        resolution: WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.rejected,
          rejection_code: WorkflowRejectionCode.ownership_conflict,
          rejected_at_unix_ms: timestamp,
        ),
      );

      final restored = codec.decode(codec.encode(outcome));

      expect(restored, isA<WorkflowOperationResolved>());

      final resolution = (restored as WorkflowOperationResolved).resolution;

      expect(resolution.state, WorkflowSubmissionState.rejected);

      expect(
        resolution.rejection_code,
        WorkflowRejectionCode.ownership_conflict,
      );
    });

    test('round-trips an idempotency conflict without a receipt', () {
      const outcome = WorkflowOperationIdempotencyConflict();

      final payload = codec.encode(outcome);

      expect(payload, {'kind': 'idempotency_conflict'});

      final restored = codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored, isA<WorkflowOperationIdempotencyConflict>());
    });
  });

  group('representation integrity', () {
    test('rejects invalid nested resolution metadata during encoding', () {
      final outcome = WorkflowOperationResolved(
        resolution: WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.completed,
        ),
      );

      expect(() => codec.encode(outcome), throwsArgumentError);
    });

    test('rejects unknown or malformed operation outcomes', () {
      final invalid_payloads = <Object?>[
        null,
        [],
        'resolved',
        <String, Object?>{},
        {'kind': 'unsupported'},
        {'kind': 42},
        {'kind': 'resolved'},
        {'kind': 'resolved', 'resolution': null},
        {'kind': 'resolved', 'unexpected': pending_payload},
        {'kind': 'resolved', 'resolution': pending_payload, 'unexpected': true},
      ];

      for (final payload in invalid_payloads) {
        expect(
          () => codec.decode(payload),
          throwsA(isA<FormatException>()),
          reason: 'Invalid operation outcome: $payload',
        );
      }
    });

    test('rejects invalid nested resolution metadata during decoding', () {
      expect(
        () => codec.decode({
          'kind': 'resolved',
          'resolution': {...pending_payload, 'state': 'completed'},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects submission metadata on an idempotency conflict', () {
      expect(
        () => codec.decode({
          'kind': 'idempotency_conflict',
          'resolution': pending_payload,
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
