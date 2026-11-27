import 'dart:convert';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import 'package:rudra_sdk/src/workflow/messaging/start/codecs/workflow_start_request_codec.dart';
import 'package:rudra_sdk/src/workflow/messaging/start/codecs/workflow_start_response_codec.dart';

import 'package:test/test.dart';

/// Verifies workflow establishment messaging contracts.
void main() {
  const request_codec = WorkflowStartRequestCodec();
  const response_codec = WorkflowStartResponseCodec();

  final receipt = EventSubmissionReceipt(
    event_id: 'event-001',
    correlation_id: 'correlation-001',
  );

  final request_payload = <String, Object?>{
    'root': '/workspace',
    'idempotency_key': 'operation-001',
  };

  group('Start request', () {
    test('preserves the typed message contract and wire identities', () {
      final request = WorkflowStartRequest(
        root: TargetPath('/workspace'),
        idempotency_key: 'operation-001',
      );

      expect(request, isA<Request<WorkflowStartResponse>>());

      expect(request_codec.type_id, 'rudra.workflow.start.request.v2');

      expect(response_codec.type_id, 'rudra.workflow.start.response.v1');
    });

    test('round-trips target-native paths without normalization', () {
      final paths = [
        '/workspace',
        '/Users/example/Library/Caches',
        r'C:\Users\example\AppData',
        r'\\server\share\directory',
        '/workspace/../example',
      ];

      for (final path in paths) {
        final request = WorkflowStartRequest(
          root: TargetPath(path),
          idempotency_key: ' Operation-001 ',
        );

        final payload = request_codec.encode(request);

        expect(payload, {
          'root': path,
          'idempotency_key': request.idempotency_key,
        });

        final restored = request_codec.decode(jsonDecode(jsonEncode(payload)));

        expect(restored.root.value, path);

        expect(restored.idempotency_key, request.idempotency_key);
      }
    });

    test('rejects blank idempotency keys', () {
      for (final identifier in ['', ' ', '\t\n']) {
        expect(
          () => WorkflowStartRequest(
            root: TargetPath('/workspace'),
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
        'start',
        <String, Object?>{},
        {'target_id': 'local-macos', 'root': '/workspace'},
        {...request_payload, 'target_id': 'untrusted-target'},
        {...request_payload, 'target_id': 42},
        {...request_payload, 'root': ''},
        {...request_payload, 'root': '/workspace\u0000'},
        {...request_payload, 'root': null},
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
          reason: 'Invalid Start request: $payload',
        );
      }
    });
  });

  group('Start response', () {
    test('round-trips durable establishment outcomes', () {
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
          quarantined_at_unix_ms: 1795618800000,
        ),
      ];

      for (final resolution in resolutions) {
        final response = WorkflowStartResponse(
          outcome: WorkflowOperationResolved(resolution: resolution),
        );

        final payload = response_codec.encode(response);

        expect(payload['kind'], 'resolved');

        final restored = response_codec.decode(jsonDecode(jsonEncode(payload)));

        expect(restored.outcome, isA<WorkflowOperationResolved>());

        final restored_resolution =
            (restored.outcome as WorkflowOperationResolved).resolution;

        expect(restored_resolution.state, resolution.state);

        expect(restored_resolution.receipt.event_id, receipt.event_id);

        expect(response_codec.encode(restored), payload);
      }
    });

    test('represents idempotency conflicts as application responses', () {
      const response = WorkflowStartResponse(
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
  });
}
