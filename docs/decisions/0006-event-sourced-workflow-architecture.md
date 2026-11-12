# ADR 0006 — Event-Sourced Workflow and Reactive SDK Architecture

**Date:** 2026-11-12
**Status:** Accepted
**Implementation:** Pending — Block 5A

## 1. Context

Rudra is a cross-platform, safety-first filesystem inspection and cleanup platform.

Its initial implementation provides a pure-Dart SDK, platform-independent filesystem contracts, a macOS target adapter, and an interactive CLI Explorer.

Rudra's long-term functionality extends beyond read-only exploration. Users must be able to inspect filesystem content, select cleanup candidates, review intended changes, authorize execution, pause work, recover from failures, restore staged objects, and complete or cancel cleanup workflows.

These activities may span multiple application processes, operating-system users, application restarts, and frontend implementations.

The original persistent-session architecture established important safety requirements but treated the session as the primary domain abstraction.

Rudra requires a more comprehensive model that preserves the history of intentions, decisions, approvals, filesystem operations, and outcomes throughout the complete workflow.

The architecture must also support independent application frontends without requiring those frontends to implement workflow processing, filesystem safety policy, persistence, or event handling.

## 2. Decision

Rudra SHALL adopt an event-sourced, asynchronous workflow architecture within the existing `rudra_sdk` package.

One workflow SHALL represent the complete trajectory from initial inspection through final completion or cancellation.

The architecture SHALL distinguish:

1. Frontend interactions and presentation controllers.
2. Durable event submission through a public SDK EventManager.
3. Asynchronous event handlers and application processors.
4. A deterministic workflow state machine.
5. An authoritative, append-only event store.
6. Reactive SDK state projections and observation interfaces.
7. Cleanup planning and global candidate reservations.
8. Explicitly authorized execution tracks.
9. An execution gatekeeper and durable operation outbox.
10. Platform-specific filesystem operations and recovery.

These components shall be introduced incrementally.

Rudra SHALL NOT introduce a separate `rudra_core` package at this stage.

Future extraction into separate packages remains possible when justified by actual implementation requirements.

## 3. SDK-First Platform Architecture

### 3.1 RudraSdk as the application kernel

`RudraSdk` SHALL provide reusable application capabilities and domain behavior to independently implemented applications.

Its responsibilities include:

- Filesystem inspection.
- Directory traversal and inspection orchestration.
- Storage accounting.
- Persistent workflow management.
- Event submission and processing.
- Workflow state transitions.
- Cleanup candidate planning.
- Candidate reservations.
- Execution authorization.
- Filesystem operation coordination.
- Recovery and reconciliation.
- Reactive application state.

These capabilities must be accessible without depending on official Rudra presentation implementations.

### 3.2 Independent applications

Official CLI, desktop, mobile, and web applications SHALL consume the same SDK capabilities or a trusted host service exposing those capabilities.

Third-party applications may also consume the SDK.

Frontends own:

- User interaction.
- Presentation controllers.
- Rendering and layout.
- Input decoding.
- UI-specific navigation.
- Presentation-specific state.

Frontends must not independently implement:

- Persistent workflow lifecycle policy.
- Cleanup authorization rules.
- State-machine transition policy.
- Global candidate reservation rules.
- Filesystem mutation orchestration.
- Recovery policy.

A frontend may use a CLI command, button, gesture, or another interaction mechanism to trigger application events.

Remote frontends must communicate with a trusted host that possesses the required filesystem access and authority.

### 3.3 Dependency direction

The conceptual dependency direction is:

    CLI / Desktop / Mobile / Web / Third-party
                        |
                        v
                     RudraSdk
                        |
              Domain contracts
                        ^
                        |
             Platform adapters

Concrete persistence and filesystem adapters are supplied through application composition.

The SDK must not instantiate platform-specific adapters directly.

The SDK must not depend on CLI frameworks, Flutter widgets, browser presentation code, or concrete SQLite implementations.

## 4. Public EventManager

### 4.1 Event-driven application interaction

Rudra SHALL expose a public event-management interface.

Frontend controllers submit typed application events through this interface.

Conceptual usage:

```dart
final receipt = await sdk.events.trigger(
  WorkflowStartEvent(
    root: TargetPath('/Users/example/Downloads'),
  ),
);
```

The API shown is illustrative. Exact signatures will be established during implementation.

The EventManager SHALL be a primary interface for requesting state-changing application behavior.

Read-only queries and observations may remain directly accessible through SDK services.

Not every filesystem inspection or presentation operation needs to produce a domain event.

### 4.2 Typed application events

Application events SHALL implement a shared platform-independent event contract.

Conceptually:

```dart
abstract interface class EventInterface {}

final class WorkflowStartEvent implements EventInterface {
  const WorkflowStartEvent({
    required this.root,
  });

  final TargetPath root;
}
```

This example establishes the intended type relationship, not the final implementation.

Events should have stable type identities suitable for persistence, diagnostics, and future schema evolution.

Event names such as `workflow.start` may be defined centrally.

Frontend developers should not be required to repeatedly provide string event names when the event type already identifies the operation.

### 4.3 Durable submission before acknowledgment

Calling `EventManager.trigger()` SHALL durably persist the submitted event before acknowledging successful submission.

A successful acknowledgment establishes only that the event was accepted into durable processing infrastructure.

It does not establish that the requested domain operation succeeded.

The EventManager SHALL NOT wait for the corresponding application handler to finish before returning its durable submission acknowledgment.

The acknowledgment shall provide enough information to identify the submission, including a stable event identifier.

If durable persistence fails, the caller must receive an explicit submission failure.

Malformed event envelopes or unauthorized submissions may be rejected before persistence.

Business-level acceptance or rejection belongs to asynchronous event processing.

### 4.4 Asynchronous processing

After durable submission, registered SDK handlers process application events independently of the originating frontend interaction.

For example:

    WorkflowStartEvent
          |
          v
    WorkflowStartEventHandler
          |
          +---- WorkflowStartedEvent
          |
          +---- WorkflowStartFailedEvent

The handler applies the relevant domain rules and records the resulting outcome.

One submitted event may produce zero, one, or multiple subsequent events.

Long-running processing may generate intermediate progress or recovery events.

A submitted event is not proof that its requested operation occurred.

### 4.5 Correlation and causality

Every persisted event SHALL have a stable identity.

The event-processing architecture must support correlation between an initial submission and subsequent outcomes.

For example:

    WorkflowStartEvent
      event_id: 1001
      correlation_id: A

    WorkflowStartedEvent
      event_id: 1002
      causation_id: 1001
      correlation_id: A

Correlation identifiers support diagnostics, audit history, and optional frontend event subscriptions.

Correlation metadata must not be used as authorization evidence.

### 4.6 Idempotency

The event-processing architecture must account for repeated submissions, duplicate delivery, interrupted processing, and concurrent consumers.

A retry of the same logical submission must not unintentionally create duplicate domain effects.

Handlers must use stable event identities, idempotency guarantees, or equivalent transactional safeguards.

Exactly-once delivery must not be assumed.

## 5. Event Handlers and Processing

### 5.1 SDK-owned handlers

Event handlers SHALL reside in the SDK application/domain layer.

Handlers coordinate the processing required by submitted application events.

Depending on their responsibilities, handlers may:

- Validate workflow state.
- Inspect filesystem observations.
- Evaluate candidate selection rules.
- Coordinate persistent workflow transitions.
- Append outcome events.
- Create durable processing obligations.
- Coordinate authorized execution through the gatekeeper.

Handlers must not contain presentation logic.

### 5.2 State-machine authority

Handlers may propose workflow transitions, but the state machine determines whether those transitions are valid.

Invalid transitions must not silently modify authoritative workflow state.

A failed workflow action may produce a durable failure event containing a typed reason.

The failure must not be misrepresented as a successful state transition.

### 5.3 Event dispatch and subscribers

Rudra SHALL support event subscribers for informational or application-processing purposes.

Subscribers may receive notifications concerning committed events.

Event delivery must not be treated as the source of truth.

A listener may miss a transient notification, disconnect, or restart without corrupting the authoritative workflow state.

Subscribers must tolerate duplicate notifications.

State-changing consumers must use documented transactional and idempotency mechanisms.

### 5.4 Filesystem mutation restrictions

Generic event listeners must not independently perform destructive filesystem operations.

An event such as `CandidateMarkedEvent` must never trigger deletion.

Only the execution gatekeeper may orchestrate filesystem mutations under the established authorization and recovery protocol.

## 6. Authoritative Event Store

### 6.1 Append-only history

Rudra SHALL maintain a durable, append-only event history.

Events must be persisted in a stable order appropriate to their workflow and processing scope.

The event store must support:

- Durable append operations.
- Event identities.
- Event ordering and sequence numbers.
- Expected-version concurrency control.
- Replay and reconstruction.
- Event schema evolution.
- Correlation and causation metadata.
- Transactional consistency.
- Safe recovery after interrupted processing.

Historical events must not be silently overwritten or deleted.

Corrections and subsequent decisions are represented by additional events.

### 6.2 Submitted events and outcome events

The event store must distinguish requests for domain changes from established domain outcomes.

For example:

`WorkflowStartEvent` represents a durably submitted request.

`WorkflowStartedEvent` represents successful workflow creation.

`WorkflowStartFailedEvent` represents a known failure or rejection.

Persisting the initial request must not prematurely establish the resulting workflow state.

### 6.3 Deterministic replay

The workflow state machine SHALL reconstruct state deterministically from committed event history.

Given the same valid initial state and ordered event sequence, replay must produce the same derived state.

Replay must never:

- Modify filesystem content.
- Repeat destructive operations.
- Dispatch new execution requests as a side effect.
- Reauthorize old cleanup plans.
- Depend on frontend presentation state.

Invalid or contradictory histories must produce explicit integrity failures rather than silent correction.

### 6.4 Derived projections

Materialized state projections may be maintained to improve read performance.

Such projections are derived from authoritative event history.

They are not independent sources of domain truth.

A corrupted or stale projection must be detectable and rebuildable from valid committed history.

## 7. Reactive SDK State

### 7.1 State observation as a first-class SDK capability

RudraSdk SHALL provide platform-independent interfaces through which applications can obtain and reactively observe current application state.

Frontends must not be required to subscribe to domain events to keep their views correct.

For example, a frontend displaying the current workflow status should observe the SDK's workflow state.

It should not maintain its own authoritative workflow status by manually processing `WorkflowStartedEvent` and `WorkflowCancelledEvent` notifications.

### 7.2 Current state and subsequent changes

Reactive state interfaces SHALL provide:

- An authoritative current snapshot.
- Subsequent committed changes.
- Consistent ordering or version information.
- Explicit loading and failure states where appropriate.
- Recovery after temporary disconnection.
- Visibility of changes committed by other processes.

The initial snapshot and subsequent updates must form a consistent observation sequence without an unreported gap.

Implementations may use versioned snapshots, change streams, or equivalent mechanisms.

The precise Dart API will be established when this functionality is implemented.

### 7.3 Frontend integration

A Flutter widget may rebuild when an observed SDK state changes.

A CLI renderer may update its header when its workflow-state observation changes.

A web application may observe a corresponding remote state interface.

These implementations must not need to understand the event history that produced the current state.

The SDK provides the authoritative application state; each frontend determines how to render it.

### 7.4 Informational event subscriptions

Direct domain-event subscriptions remain optional capabilities.

They may be useful for:

- Notifications.
- Diagnostics.
- Activity timelines.
- Audit displays.
- Third-party integrations.

They must not be required for basic frontend correctness.

An application that missed earlier notifications must still be able to obtain the correct current state.

### 7.5 Asynchronous operation state

A frontend may need to observe the processing status of a submitted event.

The SDK may expose reactive operation-state projections associated with submission identifiers.

These projections may distinguish pending, processing, successful, failed, and recovery-required outcomes.

Their final shape is deferred.

Such projections do not replace the authoritative workflow state.

## 8. Workflow Domain

### 8.1 One workflow per complete trajectory

One workflow SHALL represent the complete inspection and cleanup trajectory.

A workflow has:

- A stable workflow identifier.
- An operating-system user owner.
- An immutable original filesystem target.
- An immutable original inspection root.
- An authoritative ordered history.
- A deterministic derived state.
- A monotonically increasing stream version.

Its original target and root must not change after successful creation.

### 8.2 One unfinished workflow per OS user

Rudra SHALL allow at most one unfinished workflow per operating-system user on a host.

The operating-system user identity must be resolved by a trusted platform-specific boundary.

Frontend-supplied identifiers cannot independently establish user authority.

Workflow creation must enforce this constraint atomically across concurrent processes.

A request to start a second workflow may be durably accepted as an event submission, but processing must reject workflow creation when the user already has an unfinished workflow.

The rejected request must not create a competing workflow.

Cancelled and completed workflows remain in historical storage without occupying the unfinished-workflow slot.

### 8.3 Immutable original bindings

The workflow's original target and root are permanent domain bindings.

A subsequent invocation requesting a different root must not silently replace them.

The user may resume the existing workflow or explicitly initiate a valid cancellation process before starting another.

Filesystem paths retain target-native syntax.

String equality alone does not establish filesystem-object identity.

### 8.4 Workflow versus process ownership

Workflow existence is independent of a currently running application.

A workflow may remain unfinished while no process is attached.

Process ownership must be coordinated separately from workflow lifecycle.

Stale process owners must be prevented from committing new state changes after ownership has been reclaimed.

Process ownership does not authorize cleanup.

### 8.5 Workflow lifecycle

The state machine must eventually distinguish:

- Initial inspection.
- Cleanup planning.
- Review.
- Validation.
- Execution authorization.
- Quarantine staging.
- Final commit.
- Cancellation and restoration.
- Recovery-required conditions.
- Terminal completion or cancellation.

The exact initial phase representation is deferred to the first implementation slice.

Lifecycle state must distinguish pending work from established outcomes.

A recovery-required workflow remains unfinished until its unresolved obligations are safely reconciled.

## 9. Cleanup Planning and Candidate Reservations

### 9.1 Persistent cleanup intentions

Marking a candidate SHALL create a persistent domain intention.

It must not modify the inspected filesystem.

All candidates belong to a workflow-wide cleanup plan.

Plan revisions must distinguish current intentions from previous decisions.

A prior approval must not authorize a changed plan revision.

### 9.2 Global candidate reservations

Rudra SHALL prevent conflicting candidate reservations between different workflows and operating-system users on the same host.

Reservations must be associated with the relevant target, filesystem identity, and protected scope.

The system must account for:

- Path aliases.
- Hard links where applicable.
- Overlapping parent and child directories.
- Mount boundaries.
- Uncertain object identity.
- Concurrent reservation attempts.

Reservation acquisition and the corresponding accepted marking outcome must be transactionally consistent.

A failed reservation must not produce a successful candidate-marking outcome.

### 9.3 Shared coordination

A machine-wide reservation invariant cannot be guaranteed by unrelated per-user databases.

Rudra will require a trusted shared coordination authority for cross-user reservations.

The implementation of this authority is deferred.

If required reservation guarantees cannot be established, the relevant operation must fail closed.

Reservations coordinate participating Rudra instances. They do not prevent unrelated applications from modifying filesystem content.

Filesystem revalidation remains mandatory.

## 10. Execution Tracks and Gatekeeper

### 10.1 Deferred filesystem operations

Cleanup selection and filesystem mutation SHALL be separate activities.

Pending intentions are not executable operations.

After complete review and validation, the SDK may produce an immutable execution track.

An execution track binds:

- The workflow.
- The approved cleanup-plan revision.
- The intended filesystem operations.
- Their validated targets and scopes.
- Required ordering and dependencies.
- The applicable explicit user authorization.

### 10.2 Global preflight

Every candidate in an execution track must satisfy the required validation policy before the track becomes eligible for mutation.

Unresolved conflicts, incomplete inspection, changed identities, or unverifiable objects block execution.

No candidate may inherit authorization from an earlier inspection merely because its path still matches.

### 10.3 Execution gatekeeper

The gatekeeper is the only SDK component authorized to orchestrate filesystem mutations.

It SHALL:

- Verify approved execution-track authority.
- Enforce current workflow-state requirements.
- Verify relevant candidate reservations.
- Coordinate required revalidation.
- Persist operation intentions.
- Invoke narrowly scoped filesystem mutation adapters.
- Reconcile outcomes.
- Record verified results and failures.

The gatekeeper must not infer approval from ordinary event delivery.

An event listener cannot bypass the gatekeeper.

## 11. Transactional Outbox and Quarantine

### 11.1 Durable operation outbox

Approved filesystem work SHALL be represented by durable outbox operations.

An operation must be identifiable independently of the process that executes it.

The outbox must support:

- Durable pending operations.
- Stable operation identities.
- Idempotent processing.
- Recovery after crashes.
- Outcome reconciliation.
- Safe handling of uncertain results.

Relevant authorization events and their initial outbox obligations must be transactionally consistent.

### 11.2 Quarantine-first strategy

Rudra SHALL prefer recoverable quarantine staging before irreversible filesystem removal.

Quarantine is a controlled storage area whose contents and metadata can be correlated with the originating workflow.

Quarantine records must identify:

- Original target and path.
- Original filesystem-object identity and evidence.
- Quarantine destination.
- Workflow identity.
- Approved execution-track operation.
- Actual observed operation outcome.

The initial design must not treat the operating system's ordinary Trash as authoritative Rudra quarantine.

### 11.3 Filesystem constraints

Atomic relocation is not guaranteed across arbitrary filesystem boundaries.

Where reliable atomic quarantine is required, Rudra must use compatible same-filesystem operations and appropriate collision protections.

Unsupported guarantees must cause explicit failure rather than an unsafe fallback disguised as equivalent behavior.

Quarantine security must account for permissions, other users, volume availability, and external modification.

### 11.4 Quarantine is not permanent deletion

Moving an object into quarantine does not mean it has been permanently removed.

Quarantined content continues consuming storage until its data is actually reclaimed.

The workflow must distinguish:

- Quarantine requested.
- Quarantine completed.
- Restoration requested.
- Restoration completed.
- Purge requested.
- Purge completed.
- Failed operations.
- Indeterminate operations.

Exact status types will be defined during implementation.

### 11.5 Explicit final commit

Permanent removal requires a distinct, explicit final commit decision.

The final commit applies only to the authorized and validated quarantine contents.

A successful database operation must not be treated as proof of successful physical deletion.

Irreversible outcomes must be recorded only when supported by adequate evidence.

## 12. Cancellation and Restoration

### 12.1 Cancellation at workflow boundaries

Users must be able to request cancellation throughout a nonterminal workflow.

A cancellation request is not necessarily immediate terminal cancellation.

The SDK must determine whether outstanding operations require stopping, restoration, or reconciliation.

No further work that conflicts with an accepted cancellation may be scheduled.

### 12.2 Restoration before irreversible commit

Quarantined objects that have not been irreversibly purged may be eligible for restoration.

Restoration creates new forward events and outbox operations.

Historical events are never deleted or reversed.

### 12.3 Restoration conflicts

Rudra must never overwrite an object occupying the original path during restoration.

Where safe, the original object may be restored under a conflict-free recovered filename.

For example:

    report.pdf
    report (recovered).pdf

The actual destination must be recorded.

If safe restoration is impossible, the object remains protected in quarantine and the workflow enters a recovery-required condition.

### 12.4 Irreversible operations

A successfully purged object cannot be restored through the quarantine mechanism.

Cancellation must not claim to reverse irreversible filesystem effects.

Partial execution must be recorded accurately.

An in-progress operation may need to reach a safe stopping boundary before cancellation can complete.

## 13. Crash Recovery and Consistency

### 13.1 No false atomicity

SQLite persistence and filesystem operations are separate transaction domains.

Rudra must not claim that updating the database and modifying the filesystem form one indivisible transaction.

### 13.2 Intent before external effect

Before a filesystem mutation, Rudra must durably record the authorized operation and enough recovery evidence to identify its intended effect.

After attempting the operation, Rudra records the verified outcome.

A process crash may occur between the physical operation and the corresponding outcome event.

Such operations remain identifiable as unresolved.

### 13.3 Indeterminate outcomes

Recovery must distinguish:

- Not attempted.
- Verified successful.
- Verified failed.
- Partially completed.
- Indeterminate.

An absent path does not independently prove successful deletion.

An unresolved destructive operation must not be blindly repeated.

### 13.4 Recovery coordination

Recovery coordinators inspect pending durable obligations and relevant current filesystem evidence.

Recovery may reconcile previously attempted operations but must not silently initiate new destructive work without the required authorization.

Reclaiming a stale process lock must not renew expired authorization.

Unknown or unverifiable outcomes must remain explicit.

### 13.5 Fail-closed behavior

Uncertain filesystem identity, missing evidence, unsupported safeguards, storage failures, and contradictory history must not be interpreted as successful or safe operation outcomes.

## 14. Concurrency and Transactional Integrity

Rudra SHALL enforce three separate coordination requirements:

1. One unfinished workflow per operating-system user.
2. Exclusive ownership of workflow advancement where required.
3. Machine-wide conflicting candidate-reservation prevention.

These must not rely solely on in-memory checks.

The persistence architecture must support guarded event appends, expected versions, atomic workflow uniqueness, and appropriate fencing against stale owners.

Any operation requiring consistency between a workflow event and a reservation or outbox record must use a transactional boundary or an explicitly justified equivalent protocol.

Independent databases must not be assumed to share atomic transactions.

## 15. Architectural Ownership

### RudraSdk

Owns:

- Public event-management contracts.
- SDK event handlers.
- Workflow state machines.
- Domain models and rules.
- Reactive state interfaces.
- Cleanup planning and validation.
- Authorization policy.
- Gatekeeper orchestration.
- Recovery coordination.

### Persistence adapters

Own:

- Durable event storage.
- Transactional indexes and projections.
- Event delivery infrastructure.
- Persistent outbox records.
- Concurrency guarantees.
- Recovery-oriented storage operations.

SQLite is the initial persistence implementation.

### Platform adapters

Own:

- Filesystem inspection primitives.
- Platform-specific filesystem operations.
- Native identity interpretation.
- Supported quarantine, restoration, and purge mechanisms.

Read-only `TargetInspector` contracts remain separate from future mutation contracts.

### Frontends

Own:

- Interaction mechanisms.
- Presentation controllers.
- Views and rendering.
- UI-specific state.

They submit application events and observe SDK state without reimplementing shared domain behavior.

## 16. Incremental Implementation

The initial implementation shall proceed through coherent, testable slices.

### Block 5A.1 — Workflow domain and pure state machine

Establish:

- Immutable workflow identity and bindings.
- Minimal lifecycle state.
- Typed workflow events.
- Deterministic state transitions.
- Replay and invariant tests.

No persistence or filesystem mutations.

### Block 5A.2 — EventManager contracts

Establish:

- Typed event submission.
- Durable acknowledgment semantics.
- Handler registration and processing contracts.
- Event identity, correlation, and idempotency requirements.
- Processing and outcome contracts.

Avoid speculative event-bus infrastructure.

### Block 5A.3 — Event persistence

Implement:

- SQLite-backed durable event history.
- Event ordering and guarded appends.
- Atomic workflow uniqueness.
- Recovery of pending submitted events.
- Transactional projection requirements.

### Subsequent blocks

Incrementally implement:

- Reactive SDK state projections and observers.
- Event processing and dispatch.
- Workflow coordination and ownership.
- Global candidate reservations.
- Cleanup planning.
- Execution-track authorization.
- Gatekeeper and transactional outbox.
- Quarantine and restoration.
- Final commit and purge.
- Recovery and reconciliation.
- Official application integration.

The sequence may be refined as implementation reveals actual dependencies.

No destructive filesystem operations are introduced by Block 5A.1.

## 17. Pre-Production Compatibility Policy

Rudra is not yet in production.

Architectural correctness, testability, and clear responsibility boundaries take precedence over backward compatibility with experimental implementations.

Existing CLI Explorer, SDK, controller, and application-composition implementations may be refactored or replaced when justified by the accepted architecture.

Compatibility shims, deprecated forwarding libraries, and duplicate implementations must not be introduced merely to preserve pre-production behavior.

Working functionality should still be reused when appropriate.

Safety invariants must never be weakened for convenience.

## 18. Verification Requirements

Implementations must provide automated evidence for relevant guarantees, including:

- Durable event submission before acknowledgment.
- Independent asynchronous event processing.
- Correct correlation between submissions and outcomes.
- Deterministic state reconstruction.
- No filesystem mutation during replay.
- Accurate reactive state after application reconnect.
- No missed state changes between initial observation and subsequent updates.
- Visibility of relevant cross-process state changes.
- One unfinished workflow per OS user.
- Atomic concurrent workflow creation.
- Immutable workflow target and root.
- Rejection of invalid state transitions.
- Idempotent processing of repeated events.
- Global reservation conflict enforcement.
- No mutation from candidate marking.
- No execution without explicit authorization.
- Plan-revision validation.
- Durable outbox processing.
- Quarantine and restoration safety.
- Explicit irreversible commit.
- Crash recovery with uncertain outcomes.
- No blind repetition of unresolved destructive operations.
- Accurate partial-execution and cancellation reporting.

Destructive integration tests must use explicitly owned disposable filesystem fixtures.

## 19. Alternatives Considered

### Mutable sessions as the authoritative domain model

Rejected as the primary abstraction.

An append-only workflow history offers stronger representation of decisions, processing, and recovery.

### Synchronous request/response processing for state-changing actions

Rejected as the primary application-interaction model.

Frontend event submission acknowledges durable acceptance, while actual processing occurs independently.

### Frontends maintaining state through domain-event listeners

Rejected.

Reactive SDK state is the authoritative interface for current application state.

Event subscriptions remain optional informational capabilities.

### Ephemeral event dispatch without persistence

Rejected because submissions and processing obligations could be lost on crashes.

### Automatic filesystem execution from event listeners

Rejected because event delivery is not filesystem authorization.

### Separate RudraCore package immediately

Deferred to avoid unnecessary package boundaries.

### Ordinary operating-system Trash as authoritative quarantine

Rejected as the initial recovery-storage strategy.

### Independent per-user reservation databases

Rejected for machine-wide exclusivity enforcement.

### Generic distributed event-sourcing framework

Deferred until actual implementation requirements justify one.

## 20. Consequences

### Benefits

- One reusable SDK serving independent applications.
- Durable asynchronous event-driven application behavior.
- Frontends decoupled from processing internals.
- Reactive application state without frontend-managed event histories.
- Deterministic workflow replay.
- Explicit intention, authorization, and outcome separation.
- Crash-recoverable processing.
- Controlled quarantine and restoration.
- Centralized filesystem safety policy.
- Machine-wide workflow and candidate coordination.

### Costs

- Greater persistence and processing complexity.
- Event schema evolution requirements.
- Durable processing and idempotency requirements.
- State projection and observation infrastructure.
- Cross-process and cross-user coordination.
- Quarantine storage overhead.
- Recovery and failure-injection testing.

These costs are accepted because safety, recoverability, platform independence, and predictable state are fundamental requirements.

## 21. Relationship to Existing Decisions

### ADR 0002 — Persistent Single-Session Lifecycle

Partially superseded.

The primary domain abstraction is now a persistent, event-sourced workflow.

The unfinished-workflow uniqueness scope is the operating-system user on the host.

Its immutable-root, durable-state, cancellation, and recovery requirements remain applicable.

### ADR 0003 — Dry-Run Cleanup and Revalidation

Retained and extended.

The execution gatekeeper, outbox, quarantine, final commit, and recovery model provide the architecture for implementing its safety requirements.

### ADR 0004 — SDK-First Application Architecture

Retained and extended.

`RudraSdk` remains the authoritative application and domain layer.

### ADR 0005 — CLI Feature-First Structure

Retained as the organization baseline for the official CLI.

The CLI may be refactored during implementation as responsibility boundaries evolve.

### docs/ARCHITECTURE.md

Remains the architectural baseline subject to updates reflecting this ADR.

Where older session-oriented or synchronous workflow assumptions conflict with this decision, ADR 0006 governs until the architecture document is updated.

## 22. Implementation Status

**Accepted.**

This ADR establishes the architecture but introduces no runtime implementation.

The next implementation milestone is:

**Block 5A.1 — Workflow Domain and Pure State Machine.**

Development shall follow the existing incremental implementation, documentation, testing, and verification standards.