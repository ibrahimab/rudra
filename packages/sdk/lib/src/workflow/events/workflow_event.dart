/// Platform-independent event consumed by a workflow state machine.
///
/// Events represent submitted requests or established outcomes.
/// They cannot mutate state or authorize filesystem operations.
///
/// [event_type] provides a stable semantic identifier for future
/// persistence and diagnostics. It is not used for runtime
/// transition dispatch, which matches exact Dart types.
///
/// Durable event IDs, correlation metadata, and serialization
/// are introduced by later event infrastructure.
///
/// Example:
/// ```dart
/// final WorkflowEvent event = WorkflowStartEvent(
///   target_id: 'local-macos',
///   root: TargetPath('/tmp'),
/// );
///
/// print(event.event_type);
/// // workflow.start
/// ```
abstract interface class WorkflowEvent {
  /// Stable, implementation-independent event type identifier.
  String get event_type;
}
