import 'event_submission_receipt.dart';
import 'event_submission_store.dart';
import 'events/workflow_event.dart';

/// Public SDK entry point for submitting workflow commands.
///
/// Submission is delegated to the injected durable store.
///
/// A returned receipt confirms durable acceptance only.
/// It does not confirm workflow creation or domain success.
///
/// Processing, outcome generation, and workflow observation
/// are separate SDK responsibilities.
///
/// Example:
/// ```dart
/// final manager = EventManager(store: durable_store);
///
/// final receipt = await manager.trigger(
///   WorkflowStartEvent(
///     target_id: 'local-macos',
///     root: TargetPath('/workspace'),
///   ),
/// );
///
/// print(receipt.event_id);
/// ```
final class EventManager {
  /// Creates an event manager using a durable submission store.
  ///
  /// The store must guarantee committed persistence before
  /// returning a successful receipt.
  ///
  /// Construction does not access persistence or the filesystem.
  const EventManager({
    required EventSubmissionStore store,
  }) : _store = store;

  /// Durable submission boundary.
  final EventSubmissionStore _store;

  /// Submits a typed workflow command for later processing.
  ///
  /// [event] describes an intention, not an established outcome.
  ///
  /// [idempotency_key] optionally identifies a logical retry.
  /// The durable store enforces the key's identity and scope.
  ///
  /// Returns the receipt produced by the durable store.
  ///
  /// Submission failures propagate without being interpreted
  /// as successful domain operations.
  ///
  /// This method does not invoke workflow handlers, apply
  /// state transitions, or perform filesystem operations.
  Future<EventSubmissionReceipt> trigger(
    WorkflowCommandEvent event, {
    String? idempotency_key,
  }) {
    return _store.accept(
      event,
      idempotency_key: idempotency_key,
    );
  }
}
