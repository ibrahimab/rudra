import 'package:rudra_sdk/rudra_sdk.dart' show WorkflowRejectionCode;

/// An explicit stop request cannot complete because the
/// required active workflow is unavailable or has changed.
///
/// Represents an expected lifecycle conflict, not a
/// persistence or filesystem failure.
final class WorkflowStopRejectedException implements Exception {
  /// Creates an expected stop failure.
  const WorkflowStopRejectedException({required this.code});

  /// Durable SDK rejection classification, or the equivalent
  /// pre-submission absence of an active workflow.
  final WorkflowRejectionCode code;

  @override
  String toString() => 'WorkflowStopRejectedException(code: ${code.name})';
}
