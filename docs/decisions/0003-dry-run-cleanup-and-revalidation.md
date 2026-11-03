# ADR — Stateful Dry-Run Cleanup Planning and Revalidation

**Date:** 2026-11-03  
**Status:** Accepted  
**Implementation:** Pending

## 1. Context

Rudra is a user-directed filesystem cleanup application.

Its principal workflow is an interactive wizard that allows users to explore filesystem contents, inspect storage consumption, and mark files or directories for potential cleanup.

This exploration may take considerable time and may continue across multiple application sessions.

During that interval, filesystem contents may change.

A file may be modified, replaced, deleted, or moved. A directory may acquire additional children. Symbolic links may change destinations.

Consequently, a cleanup decision made during an earlier inspection cannot automatically be considered valid at execution time.

Rudra requires an explicit separation between exploration, proposed cleanup intentions, final approval, and actual execution.

## 2. Decision

Rudra SHALL implement cleanup as a persistent, stateful, dry-run workflow followed by a separately authorized execution phase.

**The entire interactive wizard SHALL remain read-only with respect to the inspected filesystem.**

Marking a candidate records a proposed cleanup action. It does not authorize or execute deletion.

Actual cleanup may begin only after a complete plan has been reviewed, its relevant filesystem state has been verified, and the user has explicitly confirmed execution.

Every destructive operation must remain constrained to the approved plan and the validated filesystem objects.

### 2.1 Exploration phase

During exploration, Rudra MAY:

- Enumerate directories.
- Inspect filesystem entries.
- Collect metadata.
- Calculate and display storage estimates.
- Describe risks.
- Identify potential cleanup candidates.
- Navigate through directories.
- Save progress.
- Persist user selections and observations.

Rudra MUST NOT:

- Delete files.
- Remove directories.
- Truncate or modify inspected files.
- Move inspected content as part of cleanup.
- Execute automatically inferred cleanup actions.

Writing Rudra's own session and audit data is permitted.

### 2.2 Candidate marking

A user may mark a filesystem entry for cleanup.

This action records the user's intent within the session's cleanup plan.

The mark SHALL retain sufficient baseline evidence to support future validation.

Such evidence may include:

- Original target and path.
- Filesystem entry kind.
- Filesystem identity.
- Relevant size observations.
- Relevant timestamps.
- Symbolic-link information.
- Directory membership and subtree observations.
- Inspection completeness.
- Selection timestamp.
- Associated plan revision.

The exact evidence model is deferred to cleanup-plan implementation.

A selection MUST NOT be treated as execution authorization.

Users MUST be able to revisit and remove candidates from the cleanup plan.

### 2.3 Global cleanup plan

All marked candidates contribute to one session-wide cleanup plan.

The plan SHALL distinguish proposed actions from executed actions.

The plan MUST account for overlapping selections, such as a selected directory and a separately selected child.

Overlapping selections MUST NOT cause duplicate execution or misleading storage-recovery estimates.

Directory selections require special care because directory membership may change between selection and execution.

A newly introduced directory child MUST NOT inherit cleanup approval from an earlier selection.

If Rudra cannot establish the relevant contents and scope of a selected directory, that directory MUST remain ineligible for execution until sufficient current evidence and explicit approval exist.

### 2.4 Persistent planning

The cleanup plan and wizard decisions SHALL survive pauses and process restarts.

Restoration MUST NOT:

- Execute pending actions.
- Convert marked candidates into approved candidates.
- Assume saved filesystem observations remain current.
- Silently expand a candidate's cleanup scope.

The domain state SHALL remain independent of terminal UI presentation details.

### 2.5 Plan revisions

Every relevant change to the cleanup plan SHALL create a new logical revision.

Relevant changes include:

- Marking an additional candidate.
- Unmarking a candidate.
- Changing a candidate's scope.
- Replacing stale baseline observations following review.
- Reapproving a changed candidate.
- Resolving overlapping selections.

Approval applies only to the complete plan revision presented to the user.

A prior approval MUST NOT authorize a different revision.

## 3. Final Review and Verification

The user may initiate final review after completing the desired exploration.

Final review SHALL present the complete proposed cleanup plan, including available risk and storage information.

Before the plan is eligible for final confirmation, Rudra MUST conduct a global pre-execution validation.

### 3.1 Global preflight barrier

Every candidate MUST be re-inspected and validated against the evidence on which its current selection or renewed review is based.

If any candidate cannot be validated, no cleanup operation may begin.

The entire execution SHALL remain blocked until unresolved issues have been addressed.

Rudra MUST NOT begin deleting validated candidates while other candidates are still awaiting preflight review.

### 3.2 Filesystem change detection

Relevant changes include:

- A path referring to a different filesystem object.
- Changed filesystem identity.
- Changed entry type.
- Modified or replaced file contents.
- Changed symbolic-link destinations.
- Added or removed directory entries.
- Replaced directory children.
- Changed cleanup scope.
- Unavailable or contradictory metadata.
- Incomplete inspection.
- Unavailable target storage.
- A relevant filesystem boundary change.

Identity comparisons and metadata checks must be interpreted conservatively.

Identical paths, equal timestamps, or matching sizes do not independently prove that the underlying object is unchanged.

A directory's own metadata does not prove that its entire subtree remains unchanged.

### 3.3 Unknown or unverifiable state

Rudra MUST distinguish between:

- Verified unchanged.
- Verified changed.
- Unverifiable.

An unverifiable candidate MUST NOT be treated as unchanged.

Missing identity information, incomplete inspection, or unsupported required safeguards must never be silently replaced by assumptions.

The SDK shall determine whether the available evidence is sufficient for the requested operation.

When sufficient verification cannot be established, cleanup MUST remain blocked.

### 3.4 Change notification

If relevant filesystem changes are detected, Rudra SHALL explicitly inform the user.

The message should communicate the following:

> The filesystem has changed since you marked these items for cleanup. Here is what you originally selected and what Rudra observes now. Review the affected items again before confirming cleanup. No cleanup has started.

The interface SHALL present, where reliably available:

- The original selected path and entry type.
- The previous inspection observations.
- The current inspection observations.
- Detected differences.
- Unverifiable information.
- The reason execution is blocked.

The interface MUST NOT silently update the plan and continue.

### 3.5 Renewed inspection

Affected candidates SHALL return to a review-required state.

The user must inspect the current filesystem state and explicitly decide whether the updated candidate should remain selected.

Rudra MUST NOT automatically treat the new state of an old path as approved.

If a previously marked file has been replaced, the replacement requires a new explicit user decision.

If a directory has gained additional children, those children must not inherit the previous cleanup approval.

The review must address the complete proposed deletion scope.

### 3.6 Renewed plan confirmation

Following any change requiring review, Rudra SHALL produce an updated cleanup-plan revision.

The complete updated plan MUST be presented to the user.

The user MUST explicitly confirm the complete plan before execution can begin.

No earlier confirmation remains valid for a changed plan revision.

## 4. Execution Authorization

Cleanup execution SHALL be separate from the inspection and planning workflow.

A candidate's presence in the plan does not authorize its deletion.

Execution requires all of the following:

1. A complete cleanup plan.
2. Resolved overlapping selections and scope conflicts.
3. Sufficient current verification evidence.
4. Successful global preflight.
5. No unresolved changed or unverifiable candidates.
6. An explicitly approved, immutable plan revision.
7. A platform execution mechanism capable of enforcing the required safeguards.

Final execution confirmation must be a deliberate user action.

Rudra MUST NOT automatically execute cleanup based on a saved plan, scheduled event, application restart, or wizard completion.

## 5. Protection Against Concurrent Changes

Successful preflight does not guarantee that the filesystem remains unchanged until execution.

A file can change after validation and before the destructive operation.

This is a time-of-check/time-of-use problem.

### 5.1 Operation-boundary validation

Immediately before a destructive operation, the executor MUST verify that the operation still addresses the intended, approved filesystem object.

The executor must use appropriate platform-supported mechanisms to guard against path replacement and other relevant races.

Simple path-based inspect-then-delete logic is not sufficient when another process can replace the path between those operations.

If the necessary guarantees cannot be established, execution MUST refuse the affected operation.

### 5.2 Changed objects

Approval MUST NOT transfer automatically to:

- Replacement files.
- New directory children.
- Different filesystem objects with similar metadata.
- Changed symbolic-link destinations.
- Other target environments.
- Other inspection sessions.
- Different cleanup-plan revisions.

### 5.3 Changes during execution

If a relevant filesystem change is discovered after execution begins, Rudra MUST stop further affected cleanup operations and enter a state requiring reconciliation.

Depending on what has already succeeded, partial execution may have occurred.

Rudra MUST report the actual results accurately.

It MUST NOT claim that the entire cleanup succeeded when some operations were interrupted, blocked, skipped, or failed.

A new or revised cleanup plan requires fresh validation and explicit user confirmation before further destructive work.

## 6. Execution Journaling and Recovery

Cleanup execution is not assumed to be atomic across multiple filesystem objects.

Rudra SHALL preserve an execution journal containing sufficient information to distinguish:

- Approved actions.
- Attempted actions.
- Successful operations.
- Failed operations.
- Skipped operations.
- Unattempted operations.
- Interrupted operations.

The journal must distinguish intention from outcome.

An interrupted execution MUST NOT automatically restart.

Recovery SHALL require reconciliation against the current filesystem state.

Further destructive work MUST require fresh authorization.

Cancelling a dry-run inspection session MUST NOT invoke cleanup or discard the distinction between previously proposed and actually executed operations.

## 7. Architectural Responsibilities

### TargetInspector

`TargetInspector` remains strictly read-only.

It supplies filesystem observations and typed errors.

It does not decide cleanup eligibility or perform deletion.

### Rudra SDK

The SDK owns:

- Cleanup-plan construction.
- Candidate selection state.
- Plan revisions.
- Validation policy.
- Change detection.
- Conflict handling.
- Authorization rules.
- Cleanup execution orchestration.

### Persistence

Persistence stores:

- Candidate baselines.
- Plan revisions.
- User decisions.
- Validation outcomes.
- Confirmation records.
- Execution journal entries.
- Audit history.

Persistence does not independently authorize cleanup.

### CLI and future Flutter UI

The presentation layer owns:

- Displaying cleanup candidates.
- Showing filesystem differences.
- Presenting warnings.
- Collecting renewed decisions.
- Collecting explicit final confirmation.
- Showing execution outcomes.

Presentation code must not implement an alternative cleanup safety policy.

### Platform execution adapters

Future execution adapters shall implement the platform-specific mutation mechanisms needed to carry out explicitly approved actions safely.

Their interfaces and safeguards must be specified separately from `TargetInspector`.

No destructive adapter is introduced by this ADR.

## 8. Alternatives Considered

### Immediate deletion when an item is marked

**Rejected.**

This eliminates the user's opportunity to review the complete cleanup plan and makes exploration destructive.

### Executing persisted selections without revalidation

**Rejected.**

Persisted observations can become stale and cannot establish the current state of the filesystem.

### Automatically accepting filesystem changes

**Rejected.**

This would allow new or replacement objects to inherit cleanup approval without an explicit decision.

### Checking only paths and timestamps

**Rejected as a sufficient safety mechanism.**

Paths can be reused, metadata can collide, and filesystem objects can change between checking and execution.

### Executing validated items while other candidates have unresolved preflight failures

**Rejected.**

Rudra SHALL use a global preflight barrier before the first destructive operation.

### Resuming an interrupted cleanup automatically

**Rejected.**

Recovery requires reconciliation and fresh user authorization.

## 9. Consequences

### Benefits

- Exploration remains safe and reversible.
- Cleanup intent is recorded without immediate side effects.
- Users can assemble and review complete cleanup plans.
- Persisted sessions do not imply persisted execution authority.
- Changed filesystem state requires renewed user decisions.
- Replacement objects cannot silently inherit approval.
- Execution results can be audited independently of user intent.
- CLI and Flutter applications share identical safety policy.

### Costs

- Requires persistent candidate baselines.
- Requires additional filesystem inspections.
- Requires explicit plan revisions and confirmation records.
- Requires careful handling of large directory trees.
- Requires race-resistant platform execution mechanisms.
- Requires execution journals and recovery workflows.
- Some cleanup operations may be refused when sufficient safety guarantees are unavailable.

These costs are accepted.

Correctness and explicit user authority take precedence over execution speed or convenience.

## 10. Required Verification

Implementation tests MUST demonstrate that:

1. Exploration never performs cleanup.
2. Marking and unmarking never perform cleanup.
3. Pausing, resuming, or cancelling an inspection session never performs cleanup.
4. Only explicitly marked and approved candidates are eligible for execution.
5. New plan revisions invalidate old approvals.
6. Changed file identities block execution.
7. Replacement objects do not inherit approval.
8. Added directory children do not inherit approval.
9. Changed symbolic links require renewed review.
10. Incomplete or unverifiable observations cannot be treated as unchanged.
11. Any unresolved preflight failure prevents all destructive operations from starting.
12. Updated plans require a new complete review and final confirmation.
13. Filesystem changes after preflight cannot bypass operation-boundary safeguards.
14. Partial execution is recorded accurately.
15. Interrupted execution never resumes automatically.
16. Missing platform safeguards prevent unsafe execution.
17. Audit records distinguish user intent, approval, attempts, and outcomes.

Destructive integration tests MUST use explicitly owned, disposable filesystem fixtures and must never operate on real user data.

## 11. Related Decisions

- `docs/ARCHITECTURE.md`
- `docs/DEVELOPMENT.md`
- `docs/decisions/0003-persistent-single-session.md`

## 12. Implementation Status

The dry-run wizard, cleanup plan, validation coordinator, persistent session state, and destructive execution framework are not yet implemented.

This ADR establishes the safety requirements that those future components MUST satisfy.

The existing `TargetInspector` contracts remain unchanged and read-only.

Implementation will proceed incrementally, with documented APIs, tests, and full repository verification.