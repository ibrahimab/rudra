import 'package:rudra_sdk/rudra_sdk.dart';

/// Indicates that an Explorer workflow action did not complete.
///
/// Preserves the original typed application outcome so the presentation
/// boundary can distinguish business rejection, quarantine, pending
/// acceptance and idempotency conflict.
///
/// Infrastructure failures are propagated separately.
final class WorkflowExplorerOperationException implements Exception {
  /// Creates an unsuccessful action result containing [outcome].
  ///
  /// Throws [ArgumentError] if [outcome] represents successful completion.
  WorkflowExplorerOperationException({required this.outcome}) {
    final result = outcome;

    if (result is WorkflowOperationResolved &&
        result.resolution.state == WorkflowSubmissionState.completed) {
      throw ArgumentError.value(
        outcome,
        'outcome',
        'A completed operation is not an Explorer action failure.',
      );
    }
  }

  /// Original application outcome associated with the unsuccessful action.
  final WorkflowOperationOutcome outcome;

  /// Formats the stable application failure classification for diagnostics.
  @override
  String toString() {
    return switch (outcome) {
      WorkflowOperationIdempotencyConflict() =>
        'Workflow operation idempotency conflict.',
      WorkflowOperationResolved(:final resolution) =>
        'Workflow operation ${resolution.state.name}'
            ' (${resolution.rejection_code?.name ?? resolution.quarantine_code?.name ?? resolution.receipt.event_id}).',
    };
  }
}
