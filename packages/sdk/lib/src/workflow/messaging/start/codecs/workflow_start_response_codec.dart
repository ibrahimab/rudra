import 'package:rudra_communication/rudra_communication.dart';

import '../../outcomes/workflow_operation_outcome_codec.dart';

import '../workflow_start_response.dart';

/// Serializes application responses to workflow establishment requests.
///
/// Delegates operation outcome representation to the shared
/// workflow operation outcome codec.
final class WorkflowStartResponseCodec
    implements MessageCodec<WorkflowStartResponse> {
  /// Creates the stateless Start response codec.
  const WorkflowStartResponseCodec();

  /// Shared serializer for durable workflow operation outcomes.
  static const _outcome_codec = WorkflowOperationOutcomeCodec();

  /// Stable wire identifier of the version 1 Start response.
  @override
  String get type_id => 'rudra.workflow.start.response.v1';

  /// Converts [message] into its operation outcome representation.
  ///
  /// Returns the structured application response payload.
  @override
  Map<String, Object?> encode(WorkflowStartResponse message) {
    return _outcome_codec.encode(message.outcome);
  }

  /// Reconstructs a Start response from [payload].
  ///
  /// Returns the response containing its decoded application outcome.
  ///
  /// Throws [FormatException] for malformed or unsupported outcomes.
  @override
  WorkflowStartResponse decode(Object? payload) {
    return WorkflowStartResponse(outcome: _outcome_codec.decode(payload));
  }
}
