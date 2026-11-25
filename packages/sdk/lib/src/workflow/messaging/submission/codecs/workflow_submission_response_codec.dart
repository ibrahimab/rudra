import 'package:rudra_communication/rudra_communication.dart';

import '../../serialization/workflow_submission_resolution_codec.dart';

import '../workflow_submission_response.dart';

/// Serializes durable workflow submission resolution responses.
///
/// Distinguishes accessible submission resolutions from the
/// absence of a matching submission.
final class WorkflowSubmissionResponseCodec
    implements MessageCodec<WorkflowSubmissionResponse> {
  /// Creates the stateless submission response codec.
  const WorkflowSubmissionResponseCodec();

  /// Shared serializer for durable submission resolutions.
  static const _resolution_codec = WorkflowSubmissionResolutionCodec();

  /// Stable wire identifier of the version 1 submission response.
  @override
  String get type_id => 'rudra.workflow.submission.response.v1';

  /// Converts [message] into its structured query result.
  ///
  /// Returns an explicit found or not-found representation.
  @override
  Map<String, Object?> encode(WorkflowSubmissionResponse message) {
    final resolution = message.resolution;

    if (resolution == null) {
      return {'kind': 'not_found'};
    }

    return {
      'kind': 'found',
      'resolution': _resolution_codec.encode(resolution),
    };
  }

  /// Reconstructs a submission resolution response from [payload].
  ///
  /// Returns an accessible resolution or an explicit absence.
  ///
  /// Throws [FormatException] for malformed representations,
  /// unknown result kinds or contradictory resolution metadata.
  @override
  WorkflowSubmissionResponse decode(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const FormatException(
        'Invalid workflow submission response payload.',
      );
    }

    switch (payload['kind']) {
      case 'found':
        if (payload.length != 2 || !payload.containsKey('resolution')) {
          throw const FormatException(
            'Invalid found submission response payload.',
          );
        }

        return WorkflowSubmissionResponse(
          resolution: _resolution_codec.decode(payload['resolution']),
        );

      case 'not_found':
        if (payload.length != 1) {
          throw const FormatException(
            'Invalid not-found submission response payload.',
          );
        }

        return const WorkflowSubmissionResponse(resolution: null);

      default:
        throw const FormatException(
          'Unsupported workflow submission response kind.',
        );
    }
  }
}
