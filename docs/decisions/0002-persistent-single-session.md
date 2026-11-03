# ADR — Persistent Single-Session Lifecycle

**Date:** 2026-11-03  
**Status:** Accepted  
**Implementation:** Pending

## 1. Context

Rudra provides an interactive filesystem inspection wizard through which users explore directories, inspect storage consumption, and mark candidates for potential cleanup.

Exploration may take multiple sessions across terminal invocations or application restarts.

The user's inspection progress, selected cleanup candidates, and decisions must persist independently of the currently running CLI process.

Allowing multiple unfinished inspection sessions would introduce unnecessary complexity and create ambiguity about which cleanup plan the user is modifying or approving.

For the initial architecture, Rudra will permit one unfinished inspection session per Rudra user profile.

## 2. Decision

Rudra SHALL enforce a persistent single-active-session model.

A user profile may have at most one unfinished inspection session.

Each session is permanently associated with the target environment and original root selected when the session was created.

The original root SHALL remain immutable throughout the session's lifetime.

A new invocation MUST NOT silently replace an existing session, switch its root, or create a parallel unfinished session.

### 2.1 Session creation

When Rudra starts, it SHALL inspect the persisted session state before creating a new inspection session.

If no unfinished session exists, Rudra may create one using the explicitly requested target and root.

Session creation and the enforcement of single-session uniqueness MUST be atomic with respect to concurrent invocations.

### 2.2 Existing session detection

Suppose a user originally started Rudra with:

`./rudra "/Users/Application Support"`

The user later invokes:

`./rudra "/Users/Downloads"`

Rudra SHALL detect the existing unfinished session and present the following choices:

1. **Continue existing session:** Restore the wizard at `/Users/Application Support`, including its persisted state and selections.
2. **Cancel existing session:** Explicitly terminate the existing inspection session, preserve its historical audit records, and proceed with creating a new session at `/Users/Downloads`.

The user's new path MUST NOT replace the previous session's original root.

Neither choice authorizes cleanup.

If the existing session is currently owned by another live process, Rudra MUST NOT permit conflicting interaction. Process ownership must be resolved safely before the session can be continued or cancelled.

An interrupted cleanup execution requires its own recovery workflow and MUST NOT be treated as an ordinary cancellable dry-run session.

### 2.3 Session lifecycle

The conceptual lifecycle includes:

- `created`: The session has been established.
- `active`: The user is interacting with the inspection wizard.
- `paused`: No interactive process currently owns the session, but progress is retained.
- `awaitingReview`: The user has pending cleanup selections requiring review.
- `awaitingConfirmation`: The current plan is ready for final user approval.
- `blocked`: Validation or another safety condition prevents progression.
- `executing`: An explicitly approved cleanup is in progress.
- `interrupted`: An execution requires reconciliation before further work.
- `completed`: The session has reached a terminal successful outcome.
- `cancelled`: The session was explicitly terminated without treating unexecuted selections as approved actions.

These states are conceptual. Their exact representation and transitions will be specified when the session domain model is implemented.

A terminal session MUST NOT be silently reopened as an active session.

An interrupted execution MUST NOT automatically resume.

### 2.4 Persistent state

The session SHALL persist enough information to restore the user's workflow, including:

- Session identity.
- Original target binding.
- Original root path.
- Current lifecycle state.
- Current wizard step.
- Navigation position.
- Marked cleanup candidates.
- Relevant inspection observations.
- Cleanup-plan revisions.
- Explicit user decisions.
- Validation status.
- Relevant audit history.

Domain decisions MUST be stored independently of CLI-specific presentation state.

This allows future Flutter interfaces to use the same session and cleanup-planning model.

### 2.5 Session ownership

One unfinished session and one active process owner are distinct constraints.

A paused session may exist without an active process.

A live process may acquire exclusive ownership to modify an unfinished session.

The persistence and coordination layers MUST prevent two processes from modifying the same session simultaneously.

The system MUST account for process crashes, stale ownership, and interrupted writes.

Recovering a stale ownership claim MUST NOT implicitly resume cleanup execution or restore an earlier execution authorization.

### 2.6 Cancellation

Cancelling a session SHALL:

1. Require an explicit user decision.
2. Terminate the dry-run session through a valid lifecycle transition.
3. Preserve appropriate historical observations and audit records.
4. Release its claim to the unfinished-session slot.
5. Permit a new session to be created.

Cancellation MUST NOT invoke filesystem cleanup.

Execution cancellation is a separate capability and must be designed independently.

### 2.7 Session isolation

A session belongs to one target environment and one original inspection root.

The SDK MUST NOT combine cleanup plans from unrelated target environments into a single session.

Filesystem identity comparison is meaningful only within the relevant target identity namespace.

A session's original root does not itself establish a secure traversal boundary. Symbolic-link traversal, path replacement, and mounted-filesystem policies require separate enforcement.

## 3. Architectural Ownership

### Rudra SDK

Owns:

- Session lifecycle rules.
- Valid state transitions.
- Original-root immutability.
- Single-session enforcement policy.
- Wizard state orchestration.
- Session cancellation and restoration.

### Persistence contracts and adapters

Own:

- Durable storage and retrieval.
- Transactional consistency.
- Persistent uniqueness enforcement.
- Atomic state transitions and associated audit records.
- Process-ownership coordination where applicable.

SQLite is the initial persistence implementation.

### CLI and future Flutter UI

Own:

- Presenting existing-session information.
- Offering continuation or cancellation.
- Collecting explicit user decisions.
- Restoring the appropriate wizard presentation.

The interface MUST NOT implement independent session lifecycle rules.

## 4. Alternatives Considered

### Multiple simultaneous unfinished sessions

**Rejected for the initial architecture.**

This would require additional cleanup-plan selection, target switching, conflict handling, and concurrency rules.

It would also increase the risk of users confusing selections or approvals between sessions.

### Ephemeral sessions

**Rejected.**

Losing selections and wizard progress whenever the process exits is incompatible with Rudra's interactive exploration workflow.

### Automatically replacing an existing session

**Rejected.**

This would discard or invalidate existing user decisions without explicit authorization.

### Automatically resuming every existing session

**Rejected as a universal rule.**

When the user explicitly requests a different location, Rudra must explain that another session exists and offer a decision rather than silently ignoring the requested location.

## 5. Consequences

### Benefits

- Predictable session ownership.
- Persistent wizard progress.
- No accidental creation of competing cleanup plans.
- Clear user decisions when switching locations.
- Centralized domain lifecycle rules.
- Compatibility with CLI and Flutter interfaces.
- Simplified initial persistence and orchestration design.

### Costs

- Requires persistent session management.
- Requires transactional uniqueness guarantees.
- Requires process-ownership coordination.
- Requires crash and stale-lock recovery.
- Prevents simultaneous independent inspection sessions within one profile.

These costs are accepted because the resulting lifecycle is easier to reason about and audit.

## 6. Required Verification

The implementation MUST provide automated tests demonstrating that:

1. Creating a session succeeds when no unfinished session exists.
2. Creating a second unfinished session is rejected.
3. A session's original root cannot be changed.
4. A different requested path triggers an existing-session decision.
5. Continuing restores the original root and saved wizard state.
6. Cancelling a dry-run session does not modify inspected filesystem content.
7. Creating a new session after cancellation succeeds.
8. Concurrent creation attempts cannot violate single-session uniqueness.
9. Concurrent processes cannot modify the same session simultaneously.
10. A crashed process can be recovered without silently authorizing cleanup.
11. Completed and cancelled sessions cannot be silently reactivated.
12. An interrupted execution cannot automatically resume.

## 7. Related Decisions

- `docs/ARCHITECTURE.md`
- `docs/DEVELOPMENT.md`
- `docs/decisions/0003-dry-run-cleanup-and-revalidation.md`

## 8. Implementation Status

This ADR defines mandatory behavior for future session orchestration and persistence work.

It does not introduce session-management APIs or SQLite schemas.

Those implementations will be developed incrementally, documented, and verified against these requirements.