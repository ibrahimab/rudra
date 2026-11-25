import 'package:rudra_communication/rudra_communication.dart';

import '../../outcomes/workflow_operation_outcome_codec.dart';

import '../workflow_stop_response.dart';

/// Serializes application responses to workflow termination requests.
///
/// Delegates operation outcome representation to the shared
/// workflow operation outcome codec.
final class WorkflowStopResponseCodec
    implements MessageCodec<WorkflowStopResponse> {
  /// Creates the stateless Stop response codec.
  const WorkflowStopResponseCodec();

  /// Shared serializer for durable workflow operation outcomes.
  static const _outcome_codec = WorkflowOperationOutcomeCodec();

  /// Stable wire identifier of the version 1 Stop response.
  @override
  String get type_id => 'rudra.workflow.stop.response.v1';

  /// Converts [message] into its operation outcome representation.
  ///
  /// Returns the structured application response payload.
  ///
  /// Throws [ArgumentError] for invalid resolution metadata.
  @override
  Map<String, Object?> encode(WorkflowStopResponse message) {
    return _outcome_codec.encode(message.outcome);
  }

  /// Reconstructs a Stop response from [payload].
  ///
  /// Returns the response containing its decoded application outcome.
  ///
  /// Throws [FormatException] for malformed or unsupported outcomes.
  @override
  WorkflowStopResponse decode(Object? payload) {
    return WorkflowStopResponse(outcome: _outcome_codec.decode(payload));
  }
}
