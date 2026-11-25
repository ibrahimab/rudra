import '../serialization/workflow_submission_resolution_codec.dart';

import 'workflow_operation_outcome.dart';

/// Serializes application outcomes of workflow operations.
///
/// The representation distinguishes accepted durable submissions
/// from conflicting reuse of an idempotency key.
///
/// Concrete response message codecs delegate to this codec
/// when representing their application outcomes.
///
/// Example:
/// ```dart
/// const codec = WorkflowOperationOutcomeCodec();
///
/// final payload = codec.encode(
///   const WorkflowOperationIdempotencyConflict(),
/// );
///
/// final outcome = codec.decode(payload);
/// ```
final class WorkflowOperationOutcomeCodec {
  /// Creates the stateless operation outcome codec.
  const WorkflowOperationOutcomeCodec();

  /// Codec responsible for nested durable submission resolutions.
  static const _resolution_codec = WorkflowSubmissionResolutionCodec();

  /// Converts [outcome] into its structured representation.
  ///
  /// Returns the outcome discriminator and, when applicable,
  /// the associated durable submission resolution.
  ///
  /// Throws [ArgumentError] for invalid resolution metadata.
  Map<String, Object?> encode(WorkflowOperationOutcome outcome) {
    return switch (outcome) {
      WorkflowOperationResolved(:final resolution) => {
        'kind': 'resolved',
        'resolution': _resolution_codec.encode(resolution),
      },
      WorkflowOperationIdempotencyConflict() => {
        'kind': 'idempotency_conflict',
      },
    };
  }

  /// Reconstructs a workflow operation outcome from [payload].
  ///
  /// Returns the concrete outcome represented by the supplied
  /// discriminator and its associated metadata.
  ///
  /// Throws [FormatException] for malformed payloads,
  /// unknown outcome kinds or contradictory metadata.
  WorkflowOperationOutcome decode(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const FormatException(
        'Invalid workflow operation outcome payload.',
      );
    }

    switch (payload['kind']) {
      case 'resolved':
        if (payload.length != 2 || !payload.containsKey('resolution')) {
          throw const FormatException(
            'Invalid resolved workflow operation payload.',
          );
        }

        return WorkflowOperationResolved(
          resolution: _resolution_codec.decode(payload['resolution']),
        );

      case 'idempotency_conflict':
        if (payload.length != 1) {
          throw const FormatException(
            'Invalid workflow idempotency conflict payload.',
          );
        }

        return const WorkflowOperationIdempotencyConflict();

      default:
        throw const FormatException(
          'Unsupported workflow operation outcome kind.',
        );
    }
  }
}
