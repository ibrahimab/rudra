# mac-cleaner — Architecture

**Status:** Accepted baseline (v1 architecture)  
**Date:** 2026-11-03  
**Initial delivery:** Local macOS CLI/TUI  
**Language:** Dart  
**Repository:** Monorepo using Dart Pub Workspaces

## 1. Purpose and product principles

mac-cleaner is a **user-directed, interactive filesystem inspection and cleanup wizard**. It helps a person navigate disk usage, inspect nested directories, understand potential cleanup candidates, explicitly select what to remove, review an execution plan, and authorize its execution.

It is **not** an autonomous cleanup utility or a background disk optimizer.

### Non-negotiable principles

1. **No automated actions.** The application must never independently select files for removal, schedule cleanup, start destructive work, or resume interrupted work. Scans and navigation are initiated by the user; read-only inspection may progress within a scope the user explicitly requested.
2. **The user decides.** No inferred classification, heuristic, or large directory size constitutes permission to delete anything.
3. **Explicit conflict resolution.** Conflicts between parent-directory selections and child-directory decisions always result in an explicit user prompt. Never silently convert a complete deletion into a partial one or override an exclusion.
4. **One persistent session.** Navigation contexts, directory decisions, and the cleanup list are different views of one persisted session, not independent wizards with independent state.
5. **Review before execution.** Marking a candidate is not approval to execute. Every destructive job requires a review and a final, explicit authorization.
6. **Target-specific execution behind contracts.** The SDK describes intent and enforces universal safety policy; target adapters implement filesystem and OS-specific inspection, validation, and operations.
7. **Auditable and recoverable.** Jobs and operation outcomes are durably recorded. Interrupted work is reconciled and may resume **only after renewed user authorization**.
8. **Fail closed.** Ambiguous scope, changed targets, unresolved selection conflicts, missing capabilities, or failed validations block the affected destructive operation.

These principles apply to **every** frontend and target adapter. UI dialogs are not the only enforcement point.

## 2. Chosen technology and delivery order

| Concern | Decision |
| --- | --- |
| Shared language | Dart |
| Initial frontend | Dart terminal UI (TUI) / CLI wizard |
| TUI framework | **Nocterm is the leading candidate**, subject to a small cross-terminal compatibility prototype; not yet a permanent dependency decision |
| Future graphical frontends | Flutter for desktop, mobile, and web as capabilities justify them |
| Shared application and domain code | Pure Dart, with **no Flutter or TUI-framework dependency** |
| Monorepo management | Dart Pub Workspaces, one workspace lockfile |
| Durable local data | SQLite, including session state, execution jobs, operation state, and audit events |
| First supported target | Local macOS filesystem |
| Later targets | Windows and Linux; user-context, protected, external-volume, and remote capabilities may be added later |
| Distribution | Native compiled CLI executable; graphical packaging later |

**Important boundary:** Flutter is the future **graphical** UI framework. Nocterm, if accepted, provides a **terminal** widget model inspired by Flutter. The two view trees are not interchangeable; they reuse the same SDK, workflows, state transitions, and target contracts.

Do not create a second application for each OS. `cli + macOS` and `desktop + macOS` use the same macOS target adapter. `cli + Windows` uses the same CLI frontend and the Windows target adapter.

### Delivery sequence

1. Monorepo setup, target contracts, and architecture tests.
2. macOS read-only target adapter and directory exploration.
3. Persistent wizard/session model and keyboard-driven TUI.
4. Central cleanup list, selection conflict prompts, and review workflow.
5. Safe execution-plan construction and read-only dry runs.
6. Explicit final authorization, durable worker, audit journal, interruption detection, and user-authorized recovery.
7. Further target adapters and Flutter frontends only when useful.

Destructive execution is **not** part of the first scanning prototype. It is enabled only after the invariants and failure-mode tests in this document are met.

## 3. Architectural overview

```text
                          APPLICATIONS / FRONTENDS
                +-------------------------------------+
                | CLI/TUI (Dart; initial)              |
                | Desktop / Mobile / Web (Flutter)     |
                +------------------+------------------+
                                   |
                        Application API / Commands
                                   |
                 +-----------------v------------------+
                 |          Pure-Dart SDK              |
                 |                                    |
                 |  Session and navigation             |
                 |  Inspection orchestration          |
                 |  Selection + conflict policy       |
                 |  Cleanup list + review             |
                 |  Plan construction + authorization  |
                 |  Job lifecycle + reconciliation     |
                 |  Audit/event definitions            |
                 +----------+---------------+---------+
                            |               |
                    Target contracts    Persistence ports
                            |               |
              +-------------+----------+    SQLite adapter
              |             |          |
           macOS          Windows     Linux
           adapter         adapter    adapter
              |
         Filesystem / OS
```

Dependencies point **inward**: frontends depend on SDK APIs; SDK depends on contracts and persistence **interfaces**; platform and SQLite adapters implement those contracts. The SDK never imports platform implementations. Composition occurs in the application bootstrap.

**Host** is where the frontend/process runs; **target** is the filesystem environment being inspected. They coincide in v1 but are distinct concepts to allow remote targets later. Target capabilities and execution context (identity, permissions, volume boundaries) are part of the target contract, not frontend-specific special cases.

## 4. Repository structure

The following structure distinguishes **initial directories** from **planned modules**. Logical SDK submodules do not have to be separate Pub packages.

```text
mac-cleaner/
├── ARCHITECTURE.md
├── README.md                          # Add when bootstrapping
├── pubspec.yaml                        # Workspace root; add when bootstrapping
├── pubspec.lock                        # Generated; commit for reproducible apps
├── apps/
│   ├── cli/                            # Initial executable + TUI
│   ├── desktop/                        # Future Flutter app
│   ├── mobile/                         # Future Flutter app
│   └── web/                            # Future Flutter app
├── packages/
│   ├── sdk/                            # Pure Dart application/domain SDK
│   │   └── lib/src/
│   │       ├── core/                   # Domain types, policies, errors
│   │       ├── explorer/               # Inspection orchestration
│   │       ├── session/                # Navigation + session lifecycle
│   │       ├── selection/              # Explicit decisions + conflicts
│   │       ├── planning/               # Cleanup plans and validation
│   │       ├── execution/              # Job coordination + recovery
│   │       └── audit/                  # Audit contracts and event types
│   ├── targets/
│   │   ├── contracts/                  # Target ports and capability models
│   │   ├── macos/                      # First concrete target adapter
│   │   ├── windows/                    # Future
│   │   └── linux/                      # Future
│   └── persistence/
│       └── sqlite/                     # SQLite repository implementation
└── docs/                               # ADRs, operation semantics, test plans
```

**Create now:** `apps/cli`, `packages/sdk`, `packages/targets/contracts`, `packages/targets/macos`, `packages/persistence/sqlite`, and `docs`. The `lib/src/*` directories can be created when the corresponding code is introduced. Do not add nonfunctional placeholder apps/packages merely to mirror the diagram.

Each actual workspace member has a `pubspec.yaml` with `resolution: workspace`. The root workspace lists only actual members. Choose the minimum Dart SDK version according to the development toolchain; Pub Workspaces require Dart 3.6 or newer (workspace globs require Dart 3.11 or newer). Prefer explicit member paths initially.

## 5. Core domain and contract boundaries

### 5.1 SDK responsibilities

- Maintain a persistent exploration session and navigation stack.
- Orchestrate user-requested inspection; aggregate and display results without double counting selected ancestors and descendants.
- Store **explicit** user decisions and derive effective status for ancestors/descendants.
- Detect and surface incompatible selections; accept a change only after explicit conflict resolution.
- Maintain a single global cleanup list derived from session state.
- Separate selection from review, review from plan authorization, and authorization from execution.
- Produce an immutable, revisioned plan describing precise filesystem effects and explicit preserved paths.
- Coordinate job creation, journal-based reconciliation, and user-approved resumption.
- Enforce target-agnostic safety invariants even if a frontend or adapter is misused.

### 5.2 Target contracts

Model capabilities rather than only checking an operating-system enum. The eventual interfaces should cover:

- `TargetDescriptor`: target identity, OS/environment, current execution identity, filesystem context, and supported capabilities.
- `TargetInspector`: enumerate children, inspect metadata and permissions, inspect mount boundaries, calculate disk usage, and resolve stable target identity when supported.
- `TargetValidator`: check operation support, ownership/permission constraints, ancestor and mount safety, expected identity, exclusions, and execution preconditions.
- `TargetExecutor`: execute only operations from an authorized, validated plan, reporting structured outcomes and errors.
- `TargetCapabilities`: distinguish read-only, deletable, privileged/restricted, remote, and other context-specific behavior.

Names above are **conceptual contracts**, not frozen Dart class names or signatures. Contracts must not expose an unrestricted `rm(path)` method to the frontend.

### 5.3 Persistence ports

The SDK depends on interfaces for `SessionRepository`, `JobRepository`, and `AuditEventRepository`; SQLite implements them. The CLI and workers do not bypass those interfaces to mutate shared state ad hoc.

### 5.4 Dependency rules

- No `dart:io` OS assumptions inside domain policies; platform effects go through ports. Portable Dart data structures, algorithms, and pure validation belong in the SDK.
- No imports from Flutter/Nocterm into SDK or target contracts.
- No SQL in UI event handlers.
- No direct filesystem deletion from UI callbacks.
- Application bootstrap is responsible for selecting and injecting platform/persistence adapters.
- Platform-specific native APIs, FFI, and controlled subprocesses are implementation details of target adapters or the execution worker.

## 6. User workflow — v1

The user drives the sequence; changing views does not discard session state.

1. **Launch CLI**: open a new session or explicitly choose to inspect an existing session/interrupted job. Never auto-resume execution.
2. **Choose starting directory**: prompt for the root directory; verify that the current target can inspect it. No silent escalation or forced access.
3. **Explore recursively**: enter directories as nested navigation contexts. Offer choices such as inspect/scan, mark, ignore, exclude, defer, return to parent, and jump to another previously visited context. A user-requested scan may enumerate descendants, but it cannot select or delete them.
4. **Inspect global cleanup list**: accessible from any directory through a shortcut; navigate to an item's original context; amend selections; view estimated size and warnings.
5. **Review wizard**: explicitly walk through the proposed deletions and exclusions, with the ability to unmark or revisit an item. No hidden or implied approval.
6. **Dry run and final confirmation**: offer a read-only dry run showing operations, preserved paths, permissions, expected failures, and scope. A completed dry run does **not** authorize real deletion. Request a separate explicit final confirmation before any execution; if the plan changes, review/authorization becomes stale.
7. **Execute approved plan**: persist the plan and authorization, then hand it to a separate worker. The TUI can exit without signaling cancellation of the authorized worker. Report what actually completed, failed, was skipped, or remains unresolved.

The UI should be a **stateful terminal application**, not a series of independent linear command-line prompts. The design is inspired by k9s: contextual header, keyboard navigation, visible statuses, global shortcuts, and a persistent session behind every view. Shortcuts and visual details are to be validated in a TUI prototype, not treated as locked API.

## 7. Selection model and conflict resolution

Separate the following **orthogonal state dimensions**:

- **Inspection**: not scanned, scanning, scanned, inaccessible, stale.
- **Explicit user directive**: unset, mark for deletion, ignore for this session, explicitly preserve/exclude, defer.
- **Effective cleanup status** (derived): unselected, selected, partially selected, protected, unresolved conflict, blocked.
- **Review/authorization**: pending review, reviewed, authorized for a specific immutable plan revision.
- **Execution**: tracked per job/operation, not as a mutable directory-selection flag.

Parent status is **derived** from explicit decisions and child relationships; a displayed `PARTIAL` label must never be treated as an additional silent user decision.

### Required conflict prompt

Example:

```text
Google/                [MARKED FOR DELETION]
├── Chrome/            [new request: PRESERVE]
├── DriveFS/
└── SoftwareUpdate/

Conflict: Google is marked for deletion, but Chrome is to be preserved.

1. Delete the other selected contents of Google; preserve Chrome AND
   the necessary parent directories.
2. Unmark Google for deletion; preserve its contents unless there are
   separately and explicitly selected child operations.
3. Cancel this change and keep the previous selection.
```

The wizard **must prompt in both directions**: preserving a child beneath a marked parent, and marking a parent containing preserved/ignored/deferred descendants. Treat ignored content conservatively as protected unless the user explicitly resolves the conflict. Never interpret “ignore” as permission to delete an uninspected subtree.

If the user chooses option 1, the resulting operation is **not** a recursive deletion of `Google/`; it is a precise deletion plan for selected content that leaves `Chrome/` and the necessary ancestors intact. Option 2 requires a clear UI definition of what happens to separately selected descendants; do not silently erase explicit child choices. Unresolved ambiguity blocks plan authorization.

Do not double-count disk sizes when parent and child both appear in navigation or selections. Report approximate reclaimable bytes separately from logical directory sizes; hard links, APFS clones, sparse files, shared caches, and metadata may make them differ.

## 8. Execution design and safety

### 8.1 Immutable plan

Before execution, freeze a plan containing:

- Plan ID and revision/hash; originating session; target and adapter identity.
- Explicit operation types, ordered dependencies, canonical scope/parent relationships, and protected exclusions.
- Expected file/directory identities and relevant metadata captured during validation.
- Capability/permission checks, boundary checks, expected outcomes, and warnings.
- Exact user approvals for that plan revision, with timestamp.

Approval is invalid if the plan changes. Prior paths alone are not sufficient authority to delete whatever is later found at the same location.

### 8.2 Dry run

Dry run is **read-only**: inspect, validate, report, and journal the result. It must never invoke destructive operations. It does not claim that later execution will succeed or that nothing can change between validation and execution.

### 8.3 Detached execution worker

After the explicit final confirmation, a **separate process** owns execution. This prevents Ctrl+C in the interactive frontend from unintentionally signaling the running cleanup. Detachment **does not make deletion atomic** and cannot guarantee completion after a shutdown, crash, or kill signal.

A target adapter may use safe native filesystem APIs or tightly controlled subprocesses. The initial design must **not** rely on a single unrestricted `rm -rf` for a tree that may contain exclusions. If `rm` is used for an approved operation, the adapter must constrain its arguments and targets and still enforce the same preconditions and journal semantics.

The worker:

1. Claims the job under an exclusive lease/lock to prevent concurrent workers.
2. Reads only the immutable, explicitly approved plan.
3. Revalidates the current target, mount/ancestor boundary, permissions, identity, and operation preconditions.
4. Journals the operation as started, performs it, verifies postconditions, and journals the outcome.
5. Skips and reports any operation whose safe preconditions are no longer satisfied.
6. Produces a final report without claiming all-or-nothing transactionality.

**Path and symlink safety:** do not follow symlinks into a different subtree; do not traverse mount boundaries without a specific, reviewed authorization. Protect system-critical locations. Avoid time-of-check/time-of-use races using handle-relative/native APIs where appropriate; a simple `stat` followed by `rm` is not a sufficient guarantee for arbitrary directories. Permanent deletion must be blocked until this safety design is implemented and tested. No implicit `sudo` or privilege escalation.

### 8.4 Interruption and recovery

Filesystem mutations and SQLite transactions are not one atomic transaction. A file might be gone even if the worker crashed before writing `OPERATION_COMPLETED`.

On restart:

1. Detect incomplete or stale jobs; **do not execute** them.
2. Offer the user read-only inspection of the job and audit trail.
3. Reconcile each unfinished operation against the actual filesystem; statuses may be `COMPLETED`, `PENDING`, `FAILED`, `SKIPPED`, or `UNKNOWN / NEEDS_REVIEW`.
4. Revalidate remaining targets, regenerate any necessary execution plan, and surface changed scope or identities.
5. Ask the user to review and explicitly authorize a new attempt/resumption.
6. Resume only the confirmed, still-safe remaining operations, never blindly replaying a stale path deletion.

The goal is **recoverability and idempotent reconciliation where possible**, not a promise that disk deletion can be rolled back or made atomic. An already absent path must not cause deletion of a different file recreated at that path.

## 9. Persistence and event/audit journal

SQLite is the initial durable storage implementation. Conceptual tables:

| Entity | Purpose |
| --- | --- |
| `sessions` | Session identity, target, current navigation context, lifecycle |
| `session_decisions` | Explicit directory/user decisions and their revisions |
| `inspection_results` | Observed filesystem metadata, scan progress, staleness |
| `cleanup_jobs` | Immutable approved plan reference, job state, authorization |
| `job_operations` | Per-operation state, preconditions, attempts, outcome |
| `audit_events` | Append-only record of user commands and worker events |

Persist a plan snapshot (or normalized immutable operation records) plus a stable content hash. Database transactions keep state updates and corresponding audit entries consistent **within SQLite**; they do not make external filesystem mutations transactional.

Examples of auditable events: `SESSION_CREATED`, `DIRECTORY_SCANNED`, `SELECTION_CHANGED`, `CONFLICT_RESOLVED`, `PLAN_REVIEWED`, `DRY_RUN_COMPLETED`, `PLAN_AUTHORIZED`, `JOB_STARTED`, `OPERATION_STARTED`, `OPERATION_COMPLETED`, `OPERATION_FAILED`, `OPERATION_SKIPPED`, `JOB_RECONCILED`, `RESUME_AUTHORIZED`, `JOB_COMPLETED`.

Each event records timestamp, originating actor (user vs. worker), session/job/operation IDs as appropriate, target/plan identity, and structured outcome. Protect logs against inadvertent disclosure: local restrictive permissions, no credentials/secrets in events, careful handling of paths and error output. An app-level append-only journal provides traceability; it is **not** by itself a tamper-proof security audit system.

## 10. Version-one operating boundaries

**In scope:** local macOS, one interactive user, explicitly chosen scan root, recursive exploration, persistent session and selections, conflict prompts, cleanup list, review, dry run, and eventually explicitly approved audited execution with interrupted-job recovery.

**Out of scope initially:** autonomous cleanup recommendations that become selections, scheduled jobs, automatic resumption, silent elevated privileges, a continuously running daemon, network/remote execution, Windows/Linux adapters, and full Flutter applications.

Read-only guidance may classify known SDKs or caches and explain potential risks, but must never infer approval from that classification. Protected or unsupported paths remain inspectable only to the extent allowed by target capabilities.

## 11. Test and acceptance invariants

No destructive release until tests demonstrate the following:

- All destructive paths require a persisted, current, explicit authorization and accepted review.
- No inspect, navigation, scan, dry-run, or startup path can invoke deletion.
- Parent/child selection conflicts prompt explicitly in both directions.
- Excluded and ignored descendants, and their necessary ancestors, remain untouched.
- Pressing a cleanup-list shortcut cannot lose or mutate exploration context.
- Persisted sessions survive restart and correctly rebuild effective selection state.
- Symlinks, mount boundaries, inaccessible paths, protected locations, and changed/replaced target identities are handled conservatively.
- Ctrl+C in the frontend does not cancel an already authorized detached worker; crashes and shutdowns are not misreported as completed jobs.
- No interrupted job automatically resumes; reconciliation can identify uncertain operations and requires new approval before further deletion.
- Duplicate worker startup cannot race the same job; repeated reconciliation cannot delete a replacement target.
- Unit tests exercise SDK and selection policy without an actual filesystem; adapter integration tests use isolated temporary directories; failure injection covers interrupted operations and database write failures.

## 12. Decisions locked vs. decisions deferred

### Locked

- Monorepo with Dart Pub Workspaces.
- Dart-first, pure-Dart SDK with ports-and-adapters architecture.
- CLI/TUI first; macOS target first.
- Flutter is the approach for later graphical applications.
- Host/frontend and target/OS capabilities are independent dimensions.
- Stateful, keyboard-driven, persistent exploration wizard and global cleanup list.
- No automated actions; explicit decisions and selection-conflict prompts.
- Separate marking, review, dry run, final authorization, and execution stages.
- SQLite persistence, durable audit/events, detached worker, and explicit recovery authorization.
- Universal safety policy enforced below the UI and target-specific enforcement through adapters.

### Deferred / requires prototype or ADR

- Nocterm acceptance after a macOS/Windows/Linux terminal rendering, keyboard, resize, and packaging spike.
- Exact public SDK class names, operation schema, and event schema.
- Precise shortcut map and layout behavior.
- Granular filesystem operation strategy and native handle APIs needed for safe deletion.
- Whether a reversible Trash/recycle-bin mode should be added alongside permanent deletion.
- SQLite migration policy, retention/redaction settings, and multi-process locking implementation.
- Future Windows/Linux, remote/privileged targets, and mobile/web deployment model.

Document significant deviations in `docs/adr/` before implementation changes the accepted baseline.

## 13. Reference documentation

- [Dart Pub Workspaces](https://dart.dev/tools/pub/workspaces)
- [Dart package layout](https://dart.dev/tools/pub/package-layout)
- [Dart native compilation](https://dart.dev/tools/dart-compile)
- [Flutter supported platforms](https://docs.flutter.dev/reference/supported-platforms)
- [Nocterm package](https://pub.dev/packages/nocterm)
