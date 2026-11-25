import '../../processing/workflow_quarantine.dart';
import '../../processing/workflow_submission_resolution.dart';

import 'event_submission_receipt_codec.dart';

/// Serializes the durable processing resolution of a workflow submission.
///
/// Each processing state has an explicit payload representation.
/// Contradictory or incomplete resolution metadata is rejected.
///
/// Internal quarantine diagnostics are excluded from the
/// communication representation.
///
/// Example:
/// ```dart
/// const codec = WorkflowSubmissionResolutionCodec();
///
/// final payload = codec.encode(resolution);
/// final restored = codec.decode(payload);
///
/// print(restored.state);
/// ```
final class WorkflowSubmissionResolutionCodec {
  /// Creates the stateless resolution codec.
  const WorkflowSubmissionResolutionCodec();

  /// Codec responsible for nested submission receipt representations.
  static const _receipt_codec = EventSubmissionReceiptCodec();

  /// Converts [resolution] into its structured representation.
  ///
  /// Returns the submission receipt, processing state and
  /// validated metadata belonging exclusively to that state.
  ///
  /// Internal quarantine diagnostics are deliberately omitted.
  Map<String, Object?> encode(WorkflowSubmissionResolution resolution) {
    final outcome = resolution.committed_outcome;

    return {
      'receipt': _receipt_codec.encode(resolution.receipt),
      'state': resolution.state.name,
      if (outcome != null)
        'committed_outcome': {
          'workflow_id': outcome.workflow_id,
          'event_type': outcome.event_type,
          'version': outcome.version,
          'sequence': outcome.sequence,
        },
      if (resolution.state == WorkflowSubmissionState.rejected)
        'rejection_code': resolution.rejection_code!.name,
      if (resolution.state == WorkflowSubmissionState.rejected)
        'rejected_at_unix_ms': resolution.rejected_at_unix_ms,
      if (resolution.state == WorkflowSubmissionState.quarantined)
        'quarantine_code': resolution.quarantine_code!.name,
      if (resolution.state == WorkflowSubmissionState.quarantined)
        'quarantined_at_unix_ms': resolution.quarantined_at_unix_ms,
    };
  }

  /// Reconstructs a durable submission resolution from [payload].
  ///
  /// Returns the validated processing state and its corresponding
  /// resolution metadata. Internal quarantine diagnostics remain absent.
  ///
  /// Throws [FormatException] for malformed or contradictory
  /// representations, unknown processing states, unsupported
  /// classification codes or invalid committed outcome references.
  WorkflowSubmissionResolution decode(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const FormatException(
        'Invalid workflow submission resolution payload.',
      );
    }

    final receipt = _receipt_codec.decode(payload['receipt']);

    try {
      switch (payload['state']) {
        case 'pending':
          _require_fields(payload, const {'receipt', 'state'});

          return WorkflowSubmissionResolution(
            receipt: receipt,
            state: WorkflowSubmissionState.pending,
          );

        case 'completed':
          _require_fields(payload, const {
            'receipt',
            'state',
            'committed_outcome',
          });

          return WorkflowSubmissionResolution(
            receipt: receipt,
            state: WorkflowSubmissionState.completed,
            committed_outcome: _decode_committed_outcome(
              payload['committed_outcome'],
            ),
          );

        case 'rejected':
          _require_fields(payload, const {
            'receipt',
            'state',
            'rejection_code',
            'rejected_at_unix_ms',
          });

          final code = payload['rejection_code'];
          final timestamp = payload['rejected_at_unix_ms'];

          if (code is! String || timestamp is! int) {
            throw const FormatException('Invalid workflow rejection metadata.');
          }

          return WorkflowSubmissionResolution(
            receipt: receipt,
            state: WorkflowSubmissionState.rejected,
            rejection_code: WorkflowRejectionCode.values.byName(code),
            rejected_at_unix_ms: timestamp,
          );

        case 'quarantined':
          _require_fields(payload, const {
            'receipt',
            'state',
            'quarantine_code',
            'quarantined_at_unix_ms',
          });

          final code = payload['quarantine_code'];
          final timestamp = payload['quarantined_at_unix_ms'];

          if (code is! String || timestamp is! int) {
            throw const FormatException(
              'Invalid workflow quarantine metadata.',
            );
          }

          return WorkflowSubmissionResolution(
            receipt: receipt,
            state: WorkflowSubmissionState.quarantined,
            quarantine_code: WorkflowQuarantineCode.values.byName(code),
            quarantined_at_unix_ms: timestamp,
          );

        default:
          throw const FormatException(
            'Unsupported workflow submission processing state.',
          );
      }
    } on ArgumentError {
      throw const FormatException(
        'Invalid workflow submission resolution metadata.',
      );
    }
  }

  /// Verifies that [payload] contains exactly the [expected] fields.
  ///
  /// Throws [FormatException] when required fields are absent
  /// or unexpected fields are present.
  static void _require_fields(
    Map<String, Object?> payload,
    Set<String> expected,
  ) {
    if (payload.length != expected.length ||
        !expected.every(payload.containsKey)) {
      throw const FormatException(
        'Invalid workflow submission resolution fields.',
      );
    }
  }

  /// Reconstructs the committed journal reference from [payload].
  ///
  /// Returns a validated committed outcome without restoring
  /// or consulting the current workflow.
  ///
  /// Throws [FormatException] for malformed representations
  /// and [ArgumentError] for invalid domain values.
  static WorkflowCommittedOutcome _decode_committed_outcome(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const FormatException(
        'Invalid committed workflow outcome payload.',
      );
    }

    _require_fields(payload, const {
      'workflow_id',
      'event_type',
      'version',
      'sequence',
    });

    final workflow_id = payload['workflow_id'];
    final event_type = payload['event_type'];
    final version = payload['version'];
    final sequence = payload['sequence'];

    if (workflow_id is! String ||
        event_type is! String ||
        version is! int ||
        sequence is! int) {
      throw const FormatException(
        'Invalid committed workflow outcome metadata.',
      );
    }

    return WorkflowCommittedOutcome(
      workflow_id: workflow_id,
      event_type: event_type,
      version: version,
      sequence: sequence,
    );
  }
}
