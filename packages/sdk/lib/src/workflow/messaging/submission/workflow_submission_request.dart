import 'package:rudra_communication/rudra_communication.dart';

import '../../event_submission_receipt.dart';

import 'workflow_submission_response.dart';

/// Requests the durable resolution of an accepted workflow submission.
///
/// The original receipt identifies the submission. The host determines
/// the trusted scope within which that submission may be accessed.
///
/// Example:
/// ```dart
/// final request = WorkflowSubmissionRequest(
///   receipt: receipt,
/// );
/// ```
final class WorkflowSubmissionRequest
    implements Request<WorkflowSubmissionResponse> {
  /// Creates a resolution query for the supplied [receipt].
  const WorkflowSubmissionRequest({required this.receipt});

  /// Original durable submission receipt.
  ///
  /// Possession of a receipt does not establish authorization
  /// to access the corresponding submission.
  final EventSubmissionReceipt receipt;
}
