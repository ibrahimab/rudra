import 'package:rudra_communication/rudra_communication.dart';

import '../../serialization/event_submission_receipt_codec.dart';

import '../workflow_submission_request.dart';

/// Serializes durable workflow submission resolution queries.
///
/// Delegates the nested receipt representation to the shared
/// event submission receipt codec.
final class WorkflowSubmissionRequestCodec
    implements MessageCodec<WorkflowSubmissionRequest> {
  /// Creates the stateless submission request codec.
  const WorkflowSubmissionRequestCodec();

  /// Shared serializer for durable submission receipts.
  static const _receipt_codec = EventSubmissionReceiptCodec();

  /// Stable wire identifier of the version 1 submission request.
  @override
  String get type_id => 'rudra.workflow.submission.request.v1';

  /// Converts [message] into its structured query representation.
  ///
  /// Returns the original submission receipt as a nested payload.
  @override
  Map<String, Object?> encode(WorkflowSubmissionRequest message) {
    return {'receipt': _receipt_codec.encode(message.receipt)};
  }

  /// Reconstructs a submission resolution query from [payload].
  ///
  /// Returns a query containing its validated submission receipt.
  ///
  /// Throws [FormatException] for malformed representations,
  /// unexpected fields or invalid receipt metadata.
  @override
  WorkflowSubmissionRequest decode(Object? payload) {
    if (payload is! Map<String, Object?> ||
        payload.length != 1 ||
        !payload.containsKey('receipt')) {
      throw const FormatException(
        'Invalid workflow submission request payload.',
      );
    }

    return WorkflowSubmissionRequest(
      receipt: _receipt_codec.decode(payload['receipt']),
    );
  }
}
