import 'package:rudra_communication/rudra_communication.dart';

import '../../processing/workflow_submission_resolution.dart';

/// Application response to a durable submission resolution query.
///
/// Represents an accessible submission resolution or the absence
/// of a matching submission within the trusted scope.
///
/// Example:
/// ```dart
/// final response = WorkflowSubmissionResponse(
///   resolution: resolution,
/// );
///
/// print(response.resolution?.state);
/// ```
final class WorkflowSubmissionResponse implements Response {
  /// Creates a submission response containing [resolution].
  ///
  /// A null resolution represents the absence of an accessible
  /// matching submission.
  const WorkflowSubmissionResponse({required this.resolution});

  /// Durable resolution of the requested submission.
  ///
  /// Null indicates that no matching submission is accessible
  /// within the trusted scope.
  ///
  /// A pending submission is represented by a non-null resolution
  /// with its corresponding processing state.
  final WorkflowSubmissionResolution? resolution;
}
