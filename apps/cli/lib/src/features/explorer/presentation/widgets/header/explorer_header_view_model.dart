/// Immutable presentation data for the Explorer header.
///
/// A header may display an active workflow, a submitted
/// command awaiting processing, or no loaded workflow.
///
/// These values are projections supplied by the Explorer
/// presenter. The header itself has no workflow authority.
///
/// Paths and identifiers retain their original spelling.
/// Terminal sanitization belongs to the rendering backend.
final class ExplorerHeaderViewModel {
  /// Creates a header presentation snapshot.
  ///
  /// [current_directory] is always required.
  ///
  /// Workflow metadata is supplied only when a committed
  /// active workflow has been loaded.
  ///
  /// [pending_submission_id] identifies an accepted
  /// workflow-start request, not an established workflow.
  ///
  /// The active and pending representations are mutually
  /// exclusive.
  ExplorerHeaderViewModel({
    required this.current_directory,
    this.workflow_id,
    this.workflow_version,
    this.workflow_target_id,
    this.pending_submission_id,
  }) {
    if (current_directory.isEmpty) {
      throw ArgumentError.value(
        current_directory,
        'current_directory',
        'The current directory cannot be empty.',
      );
    }

    final has_active_workflow = workflow_id != null;
    final has_active_metadata =
        workflow_version != null || workflow_target_id != null;

    if (has_active_workflow != has_active_metadata) {
      throw ArgumentError(
        'Active workflow metadata must be supplied together.',
      );
    }

    if (has_active_workflow &&
        (workflow_version == null || workflow_target_id == null)) {
      throw ArgumentError('An active workflow requires a version and target.');
    }

    if (workflow_version != null && workflow_version! <= 0) {
      throw ArgumentError.value(workflow_version, 'workflow_version');
    }

    if (has_active_workflow && pending_submission_id != null) {
      throw ArgumentError('A workflow cannot be both pending and active.');
    }
  }

  /// Directory currently displayed by Explorer.
  final String current_directory;

  /// Established workflow identity, if loaded.
  final String? workflow_id;

  /// Authoritative committed workflow version, if loaded.
  final int? workflow_version;

  /// Target associated with the established workflow.
  final String? workflow_target_id;

  /// Accepted submission ID that has not yet been resolved.
  final String? pending_submission_id;

  /// Whether this snapshot represents an established workflow.
  bool get has_active_workflow => workflow_id != null;

  /// Whether a start request is awaiting processing.
  bool get has_pending_workflow => pending_submission_id != null;

  /// Human-readable workflow status.
  String get workflow_status {
    if (has_active_workflow) {
      return 'ACTIVE';
    }

    if (has_pending_workflow) {
      return 'PENDING';
    }

    return 'NOT LOADED';
  }
}
