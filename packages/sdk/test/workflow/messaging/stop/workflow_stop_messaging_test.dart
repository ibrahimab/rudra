import 'dart:convert';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import 'package:rudra_sdk/src/workflow/messaging/stop/codecs/workflow_stop_request_codec.dart';
import 'package:rudra_sdk/src/workflow/messaging/stop/codecs/workflow_stop_response_codec.dart';

import 'package:test/test.dart';

/// Verifies workflow termination messaging contracts.
void main() {
  const request_codec = WorkflowStopRequestCodec();
  const response_codec = WorkflowStopResponseCodec();

  final receipt = EventSubmissionReceipt(
    event_id: 'event-002',
    correlation_id: 'correlation-002',
  );

  final request_payload = <String, Object?>{
    'workflow_id': 'workflow-001',
    'idempotency_key': 'operation-002',
  };

  group('Stop request', () {
    test('preserves the typed message contract and wire identities', () {
      final request = WorkflowStopRequest(
        workflow_id: 'workflow-001',
        idempotency_key: 'operation-002',
      );

      expect(request, isA<Request<WorkflowStopResponse>>());

      expect(request_codec.type_id, 'rudra.workflow.stop.request.v1');

      expect(response_codec.type_id, 'rudra.workflow.stop.response.v1');
    });

    test('round-trips the original workflow identity and operation key', () {
      final request = WorkflowStopRequest(
        workflow_id: ' Workflow-001 ',
        idempotency_key: ' Operation-002 ',
      );

      final payload = request_codec.encode(request);

      expect(payload, {
        'workflow_id': request.workflow_id,
        'idempotency_key': request.idempotency_key,
      });

      final restored = request_codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored.workflow_id, request.workflow_id);

      expect(restored.idempotency_key, request.idempotency_key);
    });

    test('requires nonblank workflow and operation identities', () {
      for (final identifier in ['', ' ', '\t\n']) {
        expect(
          () => WorkflowStopRequest(
            workflow_id: identifier,
            idempotency_key: 'operation-002',
          ),
          throwsArgumentError,
        );

        expect(
          () => WorkflowStopRequest(
            workflow_id: 'workflow-001',
            idempotency_key: identifier,
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects malformed or unauthorized request fields', () {
      final invalid_payloads = <Object?>[
        null,
        [],
        'stop',
        <String, Object?>{},
        {'idempotency_key': 'operation-002'},
        {'workflow_id': 'workflow-001'},
        {...request_payload, 'workflow_id': null},
        {...request_payload, 'workflow_id': ''},
        {...request_payload, 'workflow_id': 42},
        {...request_payload, 'idempotency_key': ' '},
        {...request_payload, 'idempotency_key': null},
        {...request_payload, 'os_user_id': 'untrusted-user'},
        {...request_payload, 'scope_id': 'untrusted-scope'},
        {...request_payload, 'correlation_id': 'untrusted-correlation'},
      ];

      for (final payload in invalid_payloads) {
        expect(
          () => request_codec.decode(payload),
          throwsA(isA<FormatException>()),
          reason: 'Invalid Stop request: $payload',
        );
      }
    });
  });

  group('Stop response', () {
    test('round-trips the original committed termination outcome', () {
      final response = WorkflowStopResponse(
        outcome: WorkflowOperationResolved(
          resolution: WorkflowSubmissionResolution(
            receipt: receipt,
            state: WorkflowSubmissionState.completed,
            committed_outcome: WorkflowCommittedOutcome(
              workflow_id: 'workflow-001',
              event_type: WorkflowEndedEvent.type_id,
              version: 5,
              sequence: 73,
            ),
          ),
        ),
      );

      final payload = response_codec.encode(response);

      expect(payload, {
        'kind': 'resolved',
        'resolution': {
          'receipt': {
            'event_id': receipt.event_id,
            'correlation_id': receipt.correlation_id,
          },
          'state': 'completed',
          'committed_outcome': {
            'workflow_id': 'workflow-001',
            'event_type': WorkflowEndedEvent.type_id,
            'version': 5,
            'sequence': 73,
          },
        },
      });

      final restored = response_codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored.outcome, isA<WorkflowOperationResolved>());

      final resolution =
          (restored.outcome as WorkflowOperationResolved).resolution;

      expect(resolution.state, WorkflowSubmissionState.completed);

      expect(resolution.committed_outcome!.workflow_id, 'workflow-001');

      expect(response_codec.encode(restored), payload);
    });

    test('preserves expected termination rejections', () {
      final rejection_codes = [
        WorkflowRejectionCode.workflow_not_active,
        WorkflowRejectionCode.workflow_id_mismatch,
      ];

      for (final code in rejection_codes) {
        final response = WorkflowStopResponse(
          outcome: WorkflowOperationResolved(
            resolution: WorkflowSubmissionResolution(
              receipt: receipt,
              state: WorkflowSubmissionState.rejected,
              rejection_code: code,
              rejected_at_unix_ms: 1795618800000,
            ),
          ),
        );

        final payload = response_codec.encode(response);

        final restored = response_codec.decode(jsonDecode(jsonEncode(payload)));

        final resolution =
            (restored.outcome as WorkflowOperationResolved).resolution;

        expect(resolution.state, WorkflowSubmissionState.rejected);
        expect(resolution.rejection_code, code);
        expect(response_codec.encode(restored), payload);
      }
    });

    test('preserves pending and quarantined termination submissions', () {
      final resolutions = [
        WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.pending,
        ),
        WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.quarantined,
          quarantine_code: WorkflowQuarantineCode.undecodable_command,
          quarantined_at_unix_ms: 1795618800000,
        ),
      ];

      for (final resolution in resolutions) {
        final payload = response_codec.encode(
          WorkflowStopResponse(
            outcome: WorkflowOperationResolved(resolution: resolution),
          ),
        );

        final restored = response_codec.decode(jsonDecode(jsonEncode(payload)));

        final restored_resolution =
            (restored.outcome as WorkflowOperationResolved).resolution;

        expect(restored_resolution.state, resolution.state);
        expect(response_codec.encode(restored), payload);
      }
    });

    test('represents idempotency conflicts as application responses', () {
      const response = WorkflowStopResponse(
        outcome: WorkflowOperationIdempotencyConflict(),
      );

      final payload = response_codec.encode(response);

      expect(payload, {'kind': 'idempotency_conflict'});

      final restored = response_codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored.outcome, isA<WorkflowOperationIdempotencyConflict>());
    });

    test('rejects malformed operation outcome representations', () {
      final invalid_payloads = <Object?>[
        null,
        {'kind': 'unsupported'},
        {'kind': 'resolved', 'resolution': null},
        {'kind': 'idempotency_conflict', 'receipt': null},
      ];

      for (final payload in invalid_payloads) {
        expect(
          () => response_codec.decode(payload),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects invalid nested resolutions during encoding', () {
      final response = WorkflowStopResponse(
        outcome: WorkflowOperationResolved(
          resolution: WorkflowSubmissionResolution(
            receipt: receipt,
            state: WorkflowSubmissionState.rejected,
          ),
        ),
      );

      expect(() => response_codec.encode(response), throwsArgumentError);
    });
  });
}
