import 'workflow_processing_models.dart';

/// Read boundary for accepted workflow commands.
///
/// Implementations select pending commands in durable
/// submission order and decode their persisted payloads.
///
/// Reading a command does not claim or complete it.
abstract interface class WorkflowInbox {
  /// Returns the next pending command, or null if empty.
  Future<PendingWorkflowCommand?> next_pending();
}
