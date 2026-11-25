import 'dart:convert';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/workflow/messaging/serialization/workflow_submission_resolution_codec.dart';
import 'package:test/test.dart';

/// Verifies durable resolution serialization and metadata integrity.
void main() {
  const codec = WorkflowSubmissionResolutionCodec();

  final receipt = EventSubmissionReceipt(
    event_id: 'event-001',
    correlation_id: 'correlation-001',
  );

  final committed_outcome = WorkflowCommittedOutcome(
    workflow_id: 'workflow-001',
    event_type: WorkflowStartedEvent.type_id,
    version: 1,
    sequence: 42,
  );

  const timestamp = 1795618800000;

  final pending_payload = <String, Object?>{
    'receipt': {
      'event_id': receipt.event_id,
      'correlation_id': receipt.correlation_id,
    },
    'state': 'pending',
  };

  final committed_payload = <String, Object?>{
    'workflow_id': committed_outcome.workflow_id,
    'event_type': committed_outcome.event_type,
    'version': committed_outcome.version,
    'sequence': committed_outcome.sequence,
  };

  final completed_payload = <String, Object?>{
    ...pending_payload,
    'state': 'completed',
    'committed_outcome': committed_payload,
  };

  final rejected_payload = <String, Object?>{
    ...pending_payload,
    'state': 'rejected',
    'rejection_code': 'ownership_conflict',
    'rejected_at_unix_ms': timestamp,
  };

  final quarantined_payload = <String, Object?>{
    ...pending_payload,
    'state': 'quarantined',
    'quarantine_code': 'undecodable_command',
    'quarantined_at_unix_ms': timestamp,
  };

  group('durable processing states', () {
    test('round-trips a pending submission', () {
      final resolution = WorkflowSubmissionResolution(
        receipt: receipt,
        state: WorkflowSubmissionState.pending,
      );

      expect(codec.encode(resolution), pending_payload);

      final restored = codec.decode(jsonDecode(jsonEncode(pending_payload)));

      expect(restored.state, WorkflowSubmissionState.pending);
      expect(restored.receipt.event_id, receipt.event_id);
      expect(restored.receipt.correlation_id, receipt.correlation_id);

      expect(restored.committed_outcome, isNull);
      expect(restored.rejection_code, isNull);
      expect(restored.quarantine_code, isNull);
    });

    test('round-trips a completed submission', () {
      final resolution = WorkflowSubmissionResolution(
        receipt: receipt,
        state: WorkflowSubmissionState.completed,
        committed_outcome: committed_outcome,
      );

      expect(codec.encode(resolution), completed_payload);

      final restored = codec.decode(jsonDecode(jsonEncode(completed_payload)));

      expect(restored.state, WorkflowSubmissionState.completed);

      final outcome = restored.committed_outcome!;

      expect(outcome.workflow_id, committed_outcome.workflow_id);
      expect(outcome.event_type, committed_outcome.event_type);
      expect(outcome.version, committed_outcome.version);
      expect(outcome.sequence, committed_outcome.sequence);

      expect(codec.encode(restored), completed_payload);
    });

    test('round-trips every registered rejection classification', () {
      for (final code in WorkflowRejectionCode.values) {
        final resolution = WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.rejected,
          rejection_code: code,
          rejected_at_unix_ms: timestamp,
        );

        final payload = codec.encode(resolution);

        expect(payload, {...rejected_payload, 'rejection_code': code.name});

        final restored = codec.decode(jsonDecode(jsonEncode(payload)));

        expect(restored.state, WorkflowSubmissionState.rejected);
        expect(restored.rejection_code, code);
        expect(restored.rejected_at_unix_ms, timestamp);
        expect(codec.encode(restored), payload);
      }
    });

    test('round-trips every registered quarantine classification', () {
      for (final code in WorkflowQuarantineCode.values) {
        final resolution = WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.quarantined,
          quarantine_code: code,
          quarantined_at_unix_ms: timestamp,
        );

        final payload = codec.encode(resolution);

        expect(payload, {...quarantined_payload, 'quarantine_code': code.name});

        final restored = codec.decode(jsonDecode(jsonEncode(payload)));

        expect(restored.state, WorkflowSubmissionState.quarantined);

        expect(restored.quarantine_code, code);
        expect(restored.quarantined_at_unix_ms, timestamp);
        expect(restored.quarantine_diagnostic, isNull);
        expect(codec.encode(restored), payload);
      }
    });

    test('preserves feature-owned committed outcome identifiers', () {
      final resolution = WorkflowSubmissionResolution(
        receipt: receipt,
        state: WorkflowSubmissionState.completed,
        committed_outcome: WorkflowCommittedOutcome(
          workflow_id: 'workflow-001',
          event_type: 'example.feature.completed',
          version: 5,
          sequence: 73,
        ),
      );

      final restored = codec.decode(codec.encode(resolution));

      expect(
        restored.committed_outcome!.event_type,
        'example.feature.completed',
      );

      expect(restored.committed_outcome!.version, 5);
      expect(restored.committed_outcome!.sequence, 73);
    });
  });

  group('decoding integrity', () {
    test('rejects malformed resolution representations', () {
      final invalid_payloads = <Object?>[
        null,
        [],
        'pending',
        <String, Object?>{},
        {'state': 'pending'},
        {...pending_payload, 'receipt': null},
        {...pending_payload, 'state': 42},
        {...pending_payload, 'state': 'unsupported'},
        {...pending_payload, 'unexpected': true},
      ];

      for (final payload in invalid_payloads) {
        expect(
          () => codec.decode(payload),
          throwsA(isA<FormatException>()),
          reason: 'Invalid resolution payload: $payload',
        );
      }
    });

    test('rejects missing state-specific metadata', () {
      final invalid_payloads = [
        {...pending_payload, 'state': 'completed'},
        {
          ...pending_payload,
          'state': 'rejected',
          'rejection_code': 'ownership_conflict',
        },
        {
          ...pending_payload,
          'state': 'quarantined',
          'quarantine_code': 'undecodable_command',
        },
      ];

      for (final payload in invalid_payloads) {
        expect(() => codec.decode(payload), throwsA(isA<FormatException>()));
      }
    });

    test('rejects contradictory or unexpected metadata', () {
      final invalid_payloads = [
        {...pending_payload, 'committed_outcome': committed_payload},
        {...pending_payload, 'committed_outcome': null},
        {...completed_payload, 'rejection_code': 'ownership_conflict'},
        {...rejected_payload, 'committed_outcome': committed_payload},
        {
          ...quarantined_payload,
          'rejection_code': 'ownership_conflict',
          'rejected_at_unix_ms': timestamp,
        },
      ];

      for (final payload in invalid_payloads) {
        expect(() => codec.decode(payload), throwsA(isA<FormatException>()));
      }
    });

    test('rejects invalid committed outcome references', () {
      final invalid_outcomes = <Object?>[
        null,
        [],
        <String, Object?>{},
        {...committed_payload, 'workflow_id': ''},
        {...committed_payload, 'event_type': ' '},
        {...committed_payload, 'version': 0},
        {...committed_payload, 'version': 1.5},
        {...committed_payload, 'sequence': -1},
        {...committed_payload, 'sequence': '42'},
        {...committed_payload, 'unexpected': true},
      ];

      for (final outcome in invalid_outcomes) {
        expect(
          () => codec.decode({
            ...completed_payload,
            'committed_outcome': outcome,
          }),
          throwsA(isA<FormatException>()),
          reason: 'Invalid committed outcome: $outcome',
        );
      }
    });

    test('rejects unsupported resolution classifications', () {
      final invalid_payloads = [
        {...rejected_payload, 'rejection_code': 'unsupported'},
        {...quarantined_payload, 'quarantine_code': 'unsupported'},
        {...rejected_payload, 'rejection_code': null},
        {...quarantined_payload, 'quarantine_code': 42},
      ];

      for (final payload in invalid_payloads) {
        expect(() => codec.decode(payload), throwsA(isA<FormatException>()));
      }
    });

    test('rejects invalid resolution timestamp representations', () {
      final invalid_timestamps = <Object?>[null, '1795618800000', 1.5, true];

      for (final value in invalid_timestamps) {
        expect(
          () =>
              codec.decode({...rejected_payload, 'rejected_at_unix_ms': value}),
          throwsA(isA<FormatException>()),
        );

        expect(
          () => codec.decode({
            ...quarantined_payload,
            'quarantined_at_unix_ms': value,
          }),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });

  group('quarantine diagnostic boundary', () {
    test('excludes internal diagnostics from serialized resolutions', () {
      const diagnostic = 'Internal persistence diagnostic.';

      final resolution = WorkflowSubmissionResolution(
        receipt: receipt,
        state: WorkflowSubmissionState.quarantined,
        quarantine_code: WorkflowQuarantineCode.undecodable_command,
        quarantine_diagnostic: diagnostic,
        quarantined_at_unix_ms: timestamp,
      );

      final payload = codec.encode(resolution);

      expect(payload, quarantined_payload);
      expect(payload.containsKey('quarantine_diagnostic'), isFalse);
      expect(jsonEncode(payload), isNot(contains(diagnostic)));

      final restored = codec.decode(payload);

      expect(restored.quarantine_diagnostic, isNull);
      expect(restored.quarantine_code, resolution.quarantine_code);

      // Serialization must not modify the internal resolution.
      expect(resolution.quarantine_diagnostic, diagnostic);
    });

    test('rejects transmitted internal diagnostics', () {
      expect(
        () => codec.decode({
          ...quarantined_payload,
          'quarantine_diagnostic': 'Unexpected diagnostic.',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
