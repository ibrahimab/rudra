import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies durable resolution invariants independently of serialization
/// and persistence implementations.
void main() {
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

  const rejection_code = WorkflowRejectionCode.ownership_conflict;
  const quarantine_code = WorkflowQuarantineCode.undecodable_command;
  const diagnostic = 'Internal persistence diagnostic.';

  group('valid durable resolutions', () {
    test('preserves pending acceptance', () {
      final resolution = WorkflowSubmissionResolution(
        receipt: receipt,
        state: WorkflowSubmissionState.pending,
      );

      expect(resolution.receipt, same(receipt));
      expect(resolution.state, WorkflowSubmissionState.pending);
      expect(resolution.committed_outcome, isNull);
    });

    test('preserves the original committed outcome', () {
      final resolution = WorkflowSubmissionResolution(
        receipt: receipt,
        state: WorkflowSubmissionState.completed,
        committed_outcome: committed_outcome,
      );

      expect(resolution.receipt, same(receipt));
      expect(resolution.committed_outcome, same(committed_outcome));
    });

    test('preserves business rejection metadata', () {
      final resolution = WorkflowSubmissionResolution(
        receipt: receipt,
        state: WorkflowSubmissionState.rejected,
        rejection_code: rejection_code,
        rejected_at_unix_ms: timestamp,
      );

      expect(resolution.rejection_code, rejection_code);
      expect(resolution.rejected_at_unix_ms, timestamp);
    });

    test('permits quarantine with or without an internal diagnostic', () {
      for (final value in [null, diagnostic]) {
        final resolution = WorkflowSubmissionResolution(
          receipt: receipt,
          state: WorkflowSubmissionState.quarantined,
          quarantine_code: quarantine_code,
          quarantined_at_unix_ms: timestamp,
          quarantine_diagnostic: value,
        );

        expect(resolution.quarantine_code, quarantine_code);
        expect(resolution.quarantined_at_unix_ms, timestamp);
        expect(resolution.quarantine_diagnostic, value);
      }
    });
  });

  group('exclusive resolution metadata', () {
    // Here's 256 metadata combinations tried, 251 are invalid combinations
    // and 5 are valid combinations across the four processing states.
    for (final state in WorkflowSubmissionState.values) {
      test('validates every metadata combination for ${state.name}', () {
        // Exercise all optional-field combinations, including
        // incomplete terminal metadata and contradictory classifications.
        for (final committed in [null, committed_outcome]) {
          for (final rejection in [null, rejection_code]) {
            for (final rejected_at in [null, timestamp]) {
              for (final quarantine in [null, quarantine_code]) {
                for (final quarantined_at in [null, timestamp]) {
                  for (final detail in [null, diagnostic]) {
                    final valid = switch (state) {
                      WorkflowSubmissionState.pending =>
                        committed == null &&
                            rejection == null &&
                            rejected_at == null &&
                            quarantine == null &&
                            quarantined_at == null &&
                            detail == null,
                      WorkflowSubmissionState.completed =>
                        committed != null &&
                            rejection == null &&
                            rejected_at == null &&
                            quarantine == null &&
                            quarantined_at == null &&
                            detail == null,
                      WorkflowSubmissionState.rejected =>
                        committed == null &&
                            rejection != null &&
                            rejected_at != null &&
                            quarantine == null &&
                            quarantined_at == null &&
                            detail == null,
                      WorkflowSubmissionState.quarantined =>
                        committed == null &&
                            rejection == null &&
                            rejected_at == null &&
                            quarantine != null &&
                            quarantined_at != null,
                    };

                    WorkflowSubmissionResolution construct() {
                      return WorkflowSubmissionResolution(
                        receipt: receipt,
                        state: state,
                        committed_outcome: committed,
                        rejection_code: rejection,
                        rejected_at_unix_ms: rejected_at,
                        quarantine_code: quarantine,
                        quarantined_at_unix_ms: quarantined_at,
                        quarantine_diagnostic: detail,
                      );
                    }

                    if (valid) {
                      expect(construct().state, state);
                    } else {
                      expect(construct, throwsArgumentError);
                    }
                  }
                }
              }
            }
          }
        }
      });
    }
  });
}
