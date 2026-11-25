import 'dart:convert';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import 'package:rudra_sdk/src/workflow/messaging/submission/workflow_submission_request.dart';
import 'package:rudra_sdk/src/workflow/messaging/submission/workflow_submission_response.dart';

import 'package:rudra_sdk/src/workflow/messaging/submission/codecs/workflow_submission_request_codec.dart';
import 'package:rudra_sdk/src/workflow/messaging/submission/codecs/workflow_submission_response_codec.dart';

import 'package:test/test.dart';

/// Verifies durable submission resolution messaging contracts.
void main() {
  const request_codec = WorkflowSubmissionRequestCodec();
  const response_codec = WorkflowSubmissionResponseCodec();

  final receipt = EventSubmissionReceipt(
    event_id: 'event-001',
    correlation_id: 'correlation-001',
  );

  final receipt_payload = <String, Object?>{
    'event_id': receipt.event_id,
    'correlation_id': receipt.correlation_id,
  };

  final pending_payload = <String, Object?>{
    'receipt': receipt_payload,
    'state': 'pending',
  };

  group('submission request', () {
    test('preserves the typed message contract and wire identities', () {
      final request = WorkflowSubmissionRequest(receipt: receipt);

      expect(request, isA<Request<WorkflowSubmissionResponse>>());

      expect(request_codec.type_id, 'rudra.workflow.submission.request.v1');

      expect(response_codec.type_id, 'rudra.workflow.submission.response.v1');
    });

    test('round-trips the original submission receipt', () {
      final request = WorkflowSubmissionRequest(receipt: receipt);

      final payload = request_codec.encode(request);

      expect(payload, {'receipt': receipt_payload});

      final restored = request_codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored.receipt.event_id, receipt.event_id);

      expect(restored.receipt.correlation_id, receipt.correlation_id);
    });

    test('rejects malformed or unauthorized query fields', () {
      final invalid_payloads = <Object?>[
        null,
        [],
        'submission',
        <String, Object?>{},
        {'receipt': null},
        {
          'receipt': {'event_id': 'event-001'},
        },
        {
          'receipt': {'event_id': '', 'correlation_id': 'correlation-001'},
        },
        {'receipt': receipt_payload, 'scope_id': 'untrusted-scope'},
        {'receipt': receipt_payload, 'os_user_id': 'untrusted-user'},
        {'receipt': receipt_payload, 'idempotency_key': 'operation-001'},
      ];

      for (final payload in invalid_payloads) {
        expect(
          () => request_codec.decode(payload),
          throwsA(isA<FormatException>()),
          reason: 'Invalid submission query: $payload',
        );
      }
    });
  });

  group('submission response', () {
    test('round-trips accessible durable submission resolutions', () {
      final resolutions = [
        WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.pending,
        ),
        WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.completed,
          committed_outcome: WorkflowCommittedOutcome(
            workflow_id: 'workflow-001',
            event_type: WorkflowStartedEvent.type_id,
            version: 1,
            sequence: 42,
          ),
        ),
        WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.rejected,
          rejection_code: WorkflowRejectionCode.ownership_conflict,
          rejected_at_unix_ms: 1795618800000,
        ),
        WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.quarantined,
          quarantine_code: WorkflowQuarantineCode.undecodable_command,
          quarantine_diagnostic: 'Internal diagnostic.',
          quarantined_at_unix_ms: 1795618800000,
        ),
      ];

      for (final resolution in resolutions) {
        final response = WorkflowSubmissionResponse(resolution: resolution);

        final payload = response_codec.encode(response);

        expect(payload['kind'], 'found');

        final restored = response_codec.decode(jsonDecode(jsonEncode(payload)));

        expect(restored.resolution, isNotNull);
        expect(restored.resolution!.state, resolution.state);

        expect(restored.resolution!.receipt.event_id, receipt.event_id);

        expect(restored.resolution!.quarantine_diagnostic, isNull);
        expect(response_codec.encode(restored), payload);
      }
    });

    test('round-trips an absent submission explicitly', () {
      const response = WorkflowSubmissionResponse(resolution: null);

      final payload = response_codec.encode(response);

      expect(payload, {'kind': 'not_found'});

      final restored = response_codec.decode(jsonDecode(jsonEncode(payload)));

      expect(restored.resolution, isNull);
    });

    test('distinguishes pending submissions from absent submissions', () {
      final pending = WorkflowSubmissionResponse(
        resolution: WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.pending,
        ),
      );

      const absent = WorkflowSubmissionResponse(resolution: null);

      final pending_representation = response_codec.encode(pending);
      final absent_representation = response_codec.encode(absent);

      expect(pending_representation, {
        'kind': 'found',
        'resolution': pending_payload,
      });

      expect(absent_representation, {'kind': 'not_found'});

      expect(pending_representation, isNot(equals(absent_representation)));

      expect(
        response_codec.decode(pending_representation).resolution!.state,
        WorkflowSubmissionState.pending,
      );

      expect(response_codec.decode(absent_representation).resolution, isNull);
    });

    test('rejects malformed or contradictory response representations', () {
      final invalid_payloads = <Object?>[
        null,
        [],
        <String, Object?>{},
        {'kind': 'unsupported'},
        {'kind': 'idempotency_conflict'},
        {'kind': 'found'},
        {'kind': 'found', 'resolution': null},
        {
          'kind': 'found',
          'resolution': {...pending_payload, 'state': 'completed'},
        },
        {'kind': 'found', 'resolution': pending_payload, 'unexpected': true},
        {'kind': 'not_found', 'resolution': pending_payload},
        {'kind': 'not_found', 'resolution': null},
      ];

      for (final payload in invalid_payloads) {
        expect(
          () => response_codec.decode(payload),
          throwsA(isA<FormatException>()),
          reason: 'Invalid submission response: $payload',
        );
      }
    });

    test('rejects invalid nested resolutions during encoding', () {
      final response = WorkflowSubmissionResponse(
        resolution: WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.completed,
        ),
      );

      expect(() => response_codec.encode(response), throwsArgumentError);
    });
  });
}
