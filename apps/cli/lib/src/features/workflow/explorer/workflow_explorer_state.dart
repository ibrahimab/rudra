import 'package:rudra_sdk/rudra_sdk.dart'
    show WorkflowActiveState, EventSubmissionReceipt;

/// Holds the workflow snapshot displayed by one Explorer.
///
/// This is interaction-local application state, not an
/// authoritative workflow repository.
///
/// An active workflow is supplied by read-only restoration
/// or by a successfully committed application operation.
///
/// An accepted submission must never be represented as an
/// established workflow. Pending and active representations
/// are mutually exclusive.
///
/// This component does not:
/// - Create or submit workflow events.
/// - Open persistence connections.
/// - Infer workflow success from submission acceptance.
/// - Perform ownership or concurrency authorization.
/// - Change the authoritative event journal.
///
/// The backend must independently validate every submitted
/// operation using trusted identity and persisted state.
///
/// Start and Stop actions share this object so availability
/// and header status use the same interaction snapshot.
///
/// Example:
/// ```dart
/// final state = WorkflowExplorerState();
///
/// assert(state.can_start);
/// assert(!state.can_stop);
/// ```
final class WorkflowExplorerState {
  /// Creates one Explorer workflow snapshot.
  ///
  /// [active_workflow] must represent an already committed
  /// and authoritatively restored active workflow.
  ///
  /// [pending_submission] identifies an accepted request
  /// whose outcome has not yet been established.
  ///
  /// Supplying both representations is invalid.
  WorkflowExplorerState({
    WorkflowActiveState? active_workflow,
    this.pending_submission,
  }) : _active_workflow = active_workflow {
    if (active_workflow != null && pending_submission != null) {
      throw ArgumentError(
        'A workflow cannot be active and pending simultaneously.',
      );
    }
  }

  /// Last confirmed active workflow displayed by Explorer.
  WorkflowActiveState? _active_workflow;

  /// Accepted but unresolved workflow submission.
  ///
  /// This value is never treated as a committed workflow.
  final EventSubmissionReceipt? pending_submission;

  /// Last confirmed active workflow, or null when absent.
  WorkflowActiveState? get active_workflow => _active_workflow;

  /// Whether a new workflow may be offered to the user.
  ///
  /// This is a presentation and dispatch condition only.
  /// The application operation must revalidate persisted
  /// state and ownership before committing a new workflow.
  bool get can_start => _active_workflow == null && pending_submission == null;

  /// Whether stopping the loaded workflow may be offered.
  ///
  /// An active workflow must have been confirmed.
  /// A pending submission makes Stop unavailable.
  ///
  /// Backend execution still requires exact workflow
  /// identity and authoritative persistence checks.
  bool get can_stop => _active_workflow != null && pending_submission == null;

  /// Updates the snapshot after successful workflow creation.
  ///
  /// [committed] must come from a completed application
  /// operation returning authoritative workflow state.
  ///
  /// A merely accepted submission receipt is insufficient.
  ///
  /// Throws [StateError] if Start was not available.
  /// The existing snapshot is not modified on failure.
  void record_started(WorkflowActiveState committed) {
    if (!can_start) {
      throw StateError('Workflow Start is not available.');
    }

    _active_workflow = committed;
  }

  /// Clears the displayed workflow after confirmed termination.
  ///
  /// [expected_workflow_id] is captured from the workflow
  /// snapshot displayed before the Stop operation starts.
  ///
  /// [stopped_workflow_id] identifies the workflow the
  /// backend reports as durably terminated.
  ///
  /// Both identifiers must agree with the currently loaded
  /// workflow. This prevents a stale result from clearing
  /// an unrelated or replacement workflow.
  ///
  /// Throws [StateError] on missing state or ID mismatch.
  /// Failure leaves the displayed snapshot unchanged.
  void record_stopped({
    required String expected_workflow_id,
    required String stopped_workflow_id,
  }) {
    if (!can_stop ||
        _active_workflow!.identity.workflow_id != expected_workflow_id ||
        stopped_workflow_id != expected_workflow_id) {
      throw StateError(
        'Committed stop result differs from the loaded workflow.',
      );
    }

    _active_workflow = null;
  }
}
