import '../workflow_identity.dart';

/// Base contract for a workflow-related command or domain outcome.
///
/// [event_type] identifies the event's stable semantic contract.
/// The SDK uses concrete Dart types for behavior and transition
/// dispatch, never an untrusted string supplied by an event.
///
/// Command events represent requested operations and are stored
/// in the durable submission infrastructure.
///
/// Outcome events represent established domain facts and form
/// the authoritative workflow journal after successful commitment.
///
/// Implementing this interface does not authorize persistence,
/// workflow transitions, or filesystem operations.
abstract interface class WorkflowEvent {
  /// Stable semantic identifier of the event contract.
  ///
  /// The identifier is used for serialization and diagnostics.
  /// It does not determine which transition may execute.
  String get event_type;
}

/// A durable request submitted to the SDK workflow application.
///
/// Commands express intent rather than established domain state.
///
/// Only command events may be submitted through EventManager.
/// The application processor evaluates them through registered
/// command behaviors and proposes corresponding domain outcomes.
///
/// Accepted commands remain independently tracked by the durable
/// submission infrastructure, including processing and rejection.
///
/// A command does not increment the committed workflow version.
abstract interface class WorkflowCommandEvent implements WorkflowEvent {}

/// An established workflow-domain outcome.
///
/// Outcomes are proposed by trusted SDK processing, validated
/// against registered domain transitions, and committed atomically.
///
/// Only committed outcomes belong to the authoritative workflow
/// journal. Each committed outcome advances its workflow version
/// exactly once.
///
/// An outcome object is not authoritative merely because it exists.
/// Persistence and replay validation establish authoritative state.
abstract interface class WorkflowOutcomeEvent implements WorkflowEvent {}

/// A domain outcome that establishes a new workflow identity.
///
/// The first committed event of a workflow must satisfy this
/// contract. It supplies the immutable identity and original
/// bindings required to construct the first `WorkflowSnapshot`.
///
/// The state machine uses this interface rather than depending
/// on a concrete lifecycle feature or event implementation.
///
/// [identity] must originate from trusted SDK processing.
/// Before commitment, the processor and persistence boundary
/// must validate its consistency with the accepted command
/// and authenticated operating-system user.
///
/// Subsequent domain outcomes must preserve the established
/// workflow identity and cannot establish a replacement identity.
///
/// Example:
/// ```dart
/// final WorkflowEstablishmentOutcomeEvent outcome =
///     WorkflowStartedEvent(identity: identity);
///
/// print(outcome.identity.workflow_id);
/// ```
abstract interface class WorkflowEstablishmentOutcomeEvent
    implements WorkflowOutcomeEvent {
  /// Original identity and bindings of the established workflow.
  ///
  /// These values remain unchanged throughout the workflow's
  /// lifetime, including after a terminal outcome.
  WorkflowIdentity get identity;
}
