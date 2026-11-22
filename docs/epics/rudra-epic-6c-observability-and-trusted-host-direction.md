# Rudra — Epic 6C: Observability and Future Trusted Host Direction

**Status:** Agreed architectural direction; 6C.2 implementation not started  
**Decision date:** 22 November 2026  
**Code inspected:** `dcf86f8e2457c636774c22e1cbfe97377d4019df`  
**Parent epic:** [Epic 6 — Architectural Realignment](rudra-epic-6-architectural-realignment.md)  
**Normative architecture:** [ADR 0006 — Event-Sourced Workflow Architecture](../decisions/0006-event-sourced-workflow-architecture.md)  
**Scope:** Detailed design and implementation boundaries for 6C.2–6C.3; future host as a separately planned milestone

## 1. Purpose and decision summary

This document resolves the observability discussion before implementation, so future slices do not repeatedly revisit architecture settled during 6A, 6B and 6C.1. It records both the **immediate SDK observation work** and the **future trusted-host topology**, while clearly separating agreed principles from interfaces and technologies not yet chosen.

**Decisions now:**

1. Build **reactive observation of authoritative SDK application state**. Reuse the existing `RudraState`, `WorkflowsState`, `WorkflowSnapshot`, transitions, reducers, replay and `WorkflowApplication`.
2. The **SDK defines the observation contracts**. The **persistence adapter supplies committed-change notifications**, using an adapter-specific mechanism. The SDK restores and publishes validated immutable state; persistence does not construct `RudraState`.
3. The change signal originates **after a successful atomic persistence commit**, never while a pure state-machine transition is being proposed. A committed processing result already exists, but is not a subscription event today.
4. **6C.2 delivers in-process observation** through the selected/shared persistence observation source. **6C.3 integrates Explorer**. Do not implement a background host or peer-to-peer IPC for 6C.
5. **Cross-process live fan-out, host/client reconnection and remote mobile/web subscriptions remain future requirements.** A durable journal enables later restoration but is not a cross-process push channel on its own.
6. The future **Rudra Trusted Host is another SDK-consuming application within the same monorepo**—not a new repository, alternate SDK, competing state machine or database authority.
7. **The SDK does not spawn or manage OS services.** A future macOS host is provisioned and activated by a platform-specific service lifecycle; frontends connect through application-facing contracts.

**Do not confuse a 6C milestone with completion of ADR 0006 §7.** That ADR continues to require visibility of other processes' commits, ordering and recovery in the eventual product. We are explicitly staging delivery rather than weakening it.

## 2. Established architecture — do not rebuild

### 2.1 What 6A implemented

- Feature-owned Explorer actions with explicit registration at composition.
- Physical key decoding independent of workflow-specific actions.
- Compositional stateless Explorer widgets and focused view models.
- Removal of frontend `WorkflowExplorerState.record_started` / `record_stopped` style lifecycle mutation.
- Separation of UI visibility from SDK processing authorization.
- Isolated generic infrastructure and feature tests.

The frontend consumes and presents confirmed SDK state; it must not maintain an authoritative domain state machine.

### 2.2 What 6B implemented

| Existing SDK contract | Purpose |
|---|---|
| `RudraState` | Immutable top-level application state |
| `WorkflowsState` | Owner-scoped workflow collection, with nullable `current_workflow` for **verified absence** |
| `WorkflowSnapshot` | Whole-workflow immutable identity, committed version, mandatory lifecycle and typed slices |
| `WorkflowSlice` / `WorkflowSliceKey<T>` | Feature-owned typed domain-state contributions |
| `WorkflowSliceReducer<T, E>` | Pure reducers; each reads the same prior snapshot and changes only its owned slice |
| `WorkflowRuntime` / module registry | Frozen registered behaviors, codecs, transitions, lifecycles, reducers |
| `WorkflowStateMachine.transition()` | Pure proposal of a next snapshot from a registered committed outcome |
| `WorkflowStateMachine.replay()` | Deterministic replay of committed outcomes |
| `WorkflowStateReader.current()` | Validated owner-scoped restoration from journal and projection evidence |

A snapshot is a **domain value**, not an event stream. Reducers and transitions do **not** broadcast notifications. The state machine intentionally has no persistence, network, terminal or UI dependencies.

### 2.3 What 6C.1 implemented

`WorkflowApplication` offers:

```dart
Future<RudraState> read_state();
Future<EventSubmissionReceipt> submit_command(...);
Future<WorkflowSubmissionResolution?> status_for(...);
Future<WorkflowProcessingResult> process_next();
Future<WorkflowSnapshot> start(...);
Future<String> stop(...);
```

These are **existing responsibilities**, with signatures above abbreviated except for `read_state()`.

The current path:

```text
Frontend explicit action
      |
      v
WorkflowApplication / EventManager
      |
      v
Durably accepted command (receipt ≠ domain success)
      |
      v
WorkflowProcessor resolves registered behavior and outcome(s)
      |
      v
WorkflowStateMachine.transition() + feature-owned reducers
      |
      v
WorkflowCommitter.commit(plan)
      |
      v
SQLite transaction: outcome journal + ownership + submission resolution
      |
      v
WorkflowProcessingCommitted(plan) returned to the caller
```

The processor currently uses the successful `Future<void> WorkflowCommitter.commit(plan)` as proof that a transaction completed. `WorkflowProcessingCommitted` is an **immediate result**, not a published notification. This is the missing connection for 6C.2.

**Do not turn `WorkflowProcessingCommitted` into an authoritative event by itself.** Another process or an adapter could commit independently, and the SDK always relies on validated persistence evidence for its observed state.

## 3. Requirements inherited from Epic 6 and ADR 0006

### 3.1 Product-level behavior

ADR 0006 §7 and Epic 6 §3 require:

- An authoritative current snapshot and subsequent committed state changes without an **unreported observation gap**.
- Ordering/version information appropriate to scope, including replacement of one workflow by another.
- Recovery from disconnection/restart and visibility of commits originating in other processes.
- Loading, unavailable and integrity failure distinguished from proven absence.
- Reconciliation of notifications against the durable journal rather than trusting notification delivery.
- No frontend replay of domain outcome histories merely to keep UI state correct.
- Optional informational domain-event subscribers remain separate from authoritative state observation.

A workflow-local `version` cannot represent the global ordering of A → no unfinished workflow → B. The existing journal records a database-global `sequence` for committed outcomes, which may be useful, but is **not itself an approved notification cursor contract**. The exact observation handshake/cursor design is still open.

### 3.2 Staged implementation promise

| Behavior | In 6C.2/6C.3? | Eventual host milestone? |
|---|---|---|
| `read_state()` and validated restoration | Already implemented in 6C.1 | Reused |
| SDK subscription to initial authoritative state | **Yes — 6C.2** | Reused |
| React to commits from shared/local persistence notification source | **Yes — 6C.2** | Reused |
| Publish one coherent post-transaction snapshot | **Yes — 6C.2** | Reused |
| Local missed-signal reconciliation, initial handshake and explicit failure | **Yes — 6C.2** | Extended |
| Explorer UI follows an active subscription | **Yes — 6C.3** | Reused or adapted |
| Independent CLI processes receive live updates | **No** | **Yes, after host exists** |
| Host disconnection, client reconnection and live catch-up | **No** | **Yes** |
| Remote authenticated web/mobile subscriptions | **No** | **Yes, later** |
| Visibility of committed state after a fresh cross-process restore | **Already supported by persistence restoration** | Reused |

**Precise scope note:** “Same process” does not mean arbitrary independently constructed persistence contexts magically share notifications. The implementation must define the source/lifetime that local subscribers share. Separate OS processes require a real communication mechanism; no in-memory Dart stream crosses that boundary.

This is a documented interim scope. When closing 6C, do not label the original cross-process requirement or its tests as satisfied.

## 4. Agreed ownership: the right place for pub/sub

### 4.1 Responsibilities

| Component | Current / future responsibility |
|---|---|
| `WorkflowStateMachine` | **Unchanged.** Pure deterministic transitions, version advancement and slice projection. No notifications or I/O. |
| `WorkflowProcessor` | **Unchanged unless justified.** Orchestrates commands; returns `WorkflowProcessingCommitted` only after commit. No second event bus. |
| `WorkflowCommitter` | Atomic commit authority. Successful completion is the **durability boundary**; rejection/rollback publishes no committed-state success. |
| Persistence change-source contract | SDK-owned interface; concrete adapter reports committed changes and handles its own notification/reconciliation mechanism. |
| SQLite/Drift adapter | Emits local notifications **after** successful transaction, not inside it; never constructs SDK state snapshots. |
| `WorkflowStateReader` | Reused to restore validated owner-scoped state from consistent journal/projection evidence. |
| SDK observation coordinator | Turns change signals into validated coherent `RudraState` values; coordinates local consumers and subscription lifecycle. |
| `WorkflowApplication` | Public application-facing state read/observe contract. |
| Explorer and future frontends | Subscribe and update focused view models; do not process outcome events as a competing reducer. |

**Why the persistence boundary?** `WorkflowStateMachine.transition()` may succeed but `WorkflowCommitter.commit()` can later reject the plan or roll back. Publishing during transition would announce a nonexistent domain state. The committer has transactional authority, while the SDK owns domain reconstruction and publication.

**Why not only notify from `WorkflowProcessor`?** That would cover successful processing performed through one local processor, but make notification depend on a particular call path. A persistence change source also supports future host-wide observation and avoids pretending an immediate processing result is a durable broadcast protocol.

### 4.2 Intended data flow

```text
                                Frontend subscribers
                                        ^
                          immutable, validated RudraState
                                        |
                               SDK observation coordinator
                                        |
                      WorkflowStateReader / journal validation
                                        ^
                         persistence committed-change signal
                                        ^
                      successful atomic WorkflowCommitter.commit
                                        ^
                      WorkflowProcessor / state-machine proposal
```

A persistence signal means **“authoritative evidence might have changed; reconcile it.”** It does not carry authority to mutate the SDK snapshot and need not contain a `RudraState` value. The SDK publishes only validated states.

The adapter may support change signals with metadata, but a bare callback is not automatically a complete lossless protocol. The contract must define a reliable way to detect or report gaps and reconcile committed evidence with current state.

### 4.3 API direction, not finalized signatures

Existing:

```dart
Future<RudraState> read_state();
```

Candidate application-facing API:

```dart
Stream<RudraState> observe_state();
```

Candidate persistence abstraction:

```dart
abstract interface class WorkflowChangeSource {
  Stream<void> watch_changes({required String os_user_id});
}
```

Both observation signatures are **illustrative only**. We have **not agreed** that `Stream<void>` has sufficient ordering, subscription-race or recovery semantics; an explicit revision or a combined subscribe/read protocol may prove necessary. Likewise, status/error/loading contract and disposal/lifetime still require design. Do not implement these examples mechanically or add an observation-specific domain-state hierarchy by default.

### 4.4 Commit and publication semantics

1. A successful command submission alone does not produce a domain-state notification.
2. An unsuccessful transaction emits **no committed-state success** signal.
3. A successful transaction containing multiple outcome events yields a **coherent post-transaction state**, not independently visible intermediate proposals.
4. Publishing occurs after commit success. Listener exceptions and slow/disposed subscribers must not retroactively cause a successful transaction to be reported as failed.
5. Subscribe + initial state read must not silently lose a commit that occurs between them; register/reconcile ordering or a cursor/checkpoint protocol must make any gap detectable/recoverable.
6. The SDK may fan out the same verified state to several **local** consumers. Do not rerun full journal restoration separately for every local listener without justification.
7. Corruption, ownership mismatch or unavailable persistence is an explicit failure, not `current_workflow == null`. Define whether failures terminate observation or allow a controlled retry; do not silently swallow them.
8. Observer registration, notifications and cancellation **never** cause command processing, database initialization or target filesystem mutation.
9. A commit followed immediately by process termination may prevent an in-memory callback from running. On next observation startup, durable restoration must recover committed state. The future host will add active-client reconnect/catch-up guarantees.
10. A live subscriber may receive a coalesced latest snapshot, if the contract allows it; do not promise every intermediate committed outcome unless tested and designed. The journal remains the complete audit trail.

### 4.5 What 6C does not implement

- A daemon, background worker, service discovery or launch-on-demand mechanism.
- Unix sockets, WebSockets, peer-to-peer CLI IPC or an SDK networking dependency.
- Cross-process realtime fan-out or a claim that two running `rudra explore` processes remain synchronized.
- A replacement event journal, second frontend domain state machine or new state aggregate hierarchy.
- Generic SDK periodic polling that assumes SQLite behavior; each persistence adapter owns its notification strategy.
- Direct access by a mobile device to filesystem cleanup capabilities.

## 5. Epic 6C implementation progression

### 6C.1 — Portable operations — IMPLEMENTED

`WorkflowApplication` now owns reusable state reads, durable submission/resolution and confirmed Start/Stop; CLI host composition owns trusted identity, path/permissions and SQLite adapter lifecycle. Tests were reported green at the latest documentation commit.

### 6C.2 — Persistence-backed SDK observation — NEXT

**Cohesive responsibility:** A consumer of a portable SDK application can subscribe to initial verified state and subsequent committed local changes without implementing its own workflow reducer.

**Work to design and implement together:**

- Exact persistence change-source API and who owns its lifecycle.
- Post-transaction signal wiring in the SQLite adapter.
- Subscribe/read handshake and reconciliation guarantees, including A → none → B ordering within supported scope.
- SDK publication/fan-out from existing `WorkflowStateReader` into `RudraState`.
- Explicit errors, cancellation, disposal and trusted owner scope.
- Tests with pure fake contracts and real SQLite/Drift commit/rollback behavior.

**Acceptance tests:** verified initial state, active/absent restoration, commit-induced local update, multiple local consumers, no premature acceptance update, multi-outcome transaction coherence, failed commit/rollback silence, initial race, absent database read-only behavior, corrupt evidence failure, owner isolation and safe cancellation. Only claim guarantees the implementation actually proves.

**Boundary:** No Explorer modifications, host service, IPC or unrelated persistence-generalization refactor in this slice. Preserve pure transitions and reducers.

### 6C.3 — Explorer subscribes to state — PLANNED

**Cohesive responsibility:** Replace action-only refresh with the SDK subscription where Explorer is running against a supported local application/persistence context.

- Preserve feature-owned Explorer actions, physical key decoding, small view models and widgets.
- Render state updates safely alongside input without terminal races or broken restoration.
- Keep stale-action execution guarded by SDK processing and persistence.
- Cancel/dispose observation when Explorer exits or fails.
- Retain no implicit writes and no creation of an absent database during read/observation.
- Test initial presentation, local updates, input-vs-observation races, errors and Quit.

### Closing 6C

6C is locally complete when 6C.1–6C.3 are implemented and verified, and another embedded consumer can use equivalent SDK operations and live **local** observation without importing `rudra_cli` or reproducing domain rules. Documentation must state that cross-process live delivery is **not yet supported**. ADR 0006's full reactive product capability remains pending a host milestone.

## 6. Future trusted host — another SDK-consuming application

### 6.1 Architectural role and placement

The future Rudra host is a **long-running application inside the existing Rudra monorepo**, conceptually `apps/host`. It consumes the same SDK domain/application contracts, target contracts and persistence adapters as other applications. It is not a separate repository or independent source of domain truth.

Its responsibilities are trusted composition, long-lived application/processing ownership, client connection handling, authorization and **fan-out of validated SDK state** over transports. It must not reimplement workflows, invent another event journal, perform domain reducers in transport code or treat connected clients' snapshots as authority.

A possible layout (illustrative, no immediate package creation):

```text
rudra/
  packages/
    sdk/                    # Existing domain/operations/observation contracts
    persistence/sqlite/     # Existing journal and adapter
    targets/...             # Platform target access
    host-contracts/         # Optional if shared transport contracts justify extraction
  apps/
    cli/                    # Existing frontend
    host/                   # Future long-lived SDK consumer, likely pure Dart
    desktop/                # Future Flutter frontend
    mobile/                 # Future Flutter frontend
```

Transport-facing interfaces may ultimately live in `packages/sdk` or a small sibling package. **No package boundary is preapproved merely because it appears in this diagram.** Keep SDK domain dependencies free of platform-specific IPC/server libraries.

### 6.2 Desired client topology

```text
Terminal A — rudra explore ─┐
Terminal B — rudra explore ─┤
Flutter desktop ────────────┼── portable application-facing client contracts
Web browser ────────────────┤                      |
Future mobile app ──────────┘              trusted IPC/network transport
                                                  |
                                       Rudra Host (apps/host)
                                                  |
                              WorkflowApplication + SDK state observation
                                                  |
                                SDK runtime, processor, target adapters
                                                  |
                                authoritative persistent outcome journal
```

Every connected frontend observes **the same host-owned authoritative application state**. Two terminal tabs, desktop and web no longer depend on independent in-process callbacks. Mobile over IP becomes another subscriber, subject to explicit security and permission rules.

The host is a deployment/communication layer **around** Rudra's established SDK. Its role is to reuse the SDK, not replace it.

### 6.3 Who starts the host, and when?

**Decision:** The **portable SDK must never launch/check/enable/disable OS daemons as an incidental side effect**. A client connects through a portable host-client contract. Native installation/lifecycle management belongs to the platform-specific product composition.

For macOS, the leading direction is a **per-user `launchd` agent** with explicit setup/registration and on-demand activation, subject to platform and distribution constraints:

1. Installation/setup registers/enables the service in a deliberate, authorized step.
2. A frontend attempts to connect to the known local host endpoint.
3. Where supported and configured, OS-managed activation starts the registered host when requested.
4. Subsequent CLI/desktop instances connect to the same running host.
5. Closing one frontend does not automatically terminate other clients' shared host.
6. A disabled/unavailable host yields an explicit connection outcome; the SDK does not silently re-enable it.

**Not yet decided:** exact `launchd` registration mechanism, socket activation behavior, idle timeout, fallback if unregistered, restart policy and supported login/session lifecycle. Avoid promising a service survives user logout or always operates before login. Platform-specific setup can have its own installer/adapter package when justified.

We reject duplicated `if (!running) spawn_host()` logic in every frontend. Process races and service ownership belong to the system lifecycle manager, not SDK constructors.

### 6.4 Transports and Flutter/Dart roles

- **In-process subscriptions:** normal Dart streams.
- **Future local cross-process clients:** Unix domain sockets or another OS-appropriate authenticated IPC; exact protocol deferred.
- **Future web/mobile clients:** explicit authenticated/encrypted endpoint, potentially HTTP/WebSocket, and bounded authorization; no default direct Internet exposure.
- **Host implementation:** a pure-Dart headless application is favored to avoid requiring a Flutter rendering engine for a service that draws no UI.
- **Flutter frontends:** consume Dart streams and application contracts. Flutter platform channels / `EventChannel` are useful for Flutter-to-native interop, **not an automatic IPC bridge** between independent CLI processes.

Transport changes should not require edits to state-machine transitions, reducers or feature-owned domain slices. Remote and embedded clients may eventually implement the same application-facing interface through different composition.

### 6.5 Trust, safety and remote management

- The host authenticates connections and establishes the trusted OS identity; remote clients never supply an authoritative `os_user_id`.
- Local IPC and remote transport require distinct authentication, authorization and exposure rules.
- Remote devices should be paired/enabled explicitly; traffic must be encrypted and access scoped to authorized operations.
- A subscription grants visibility, not permission to mutate state or execute cleanup.
- Processing and persistence retain identity/version/replay/owner checks, durable submission resolution and idempotency.
- Destructive operations still pass through the separate execution gatekeeper, revalidation, quarantine/outbox and audit contracts in ADR 0006.
- Host restarts restore journal-backed state and reconcile clients. Memory-only broadcasts cannot become authority.
- Workflow existence is independent of host process lifetime; process ownership and stale-worker fencing are separate concerns (ADR 0006 §8.4).
- A future design must decide how **out-of-band commits by other processes** are detected or prevented; a single host can fan out its own commits, but cannot automatically detect arbitrary external writers merely by existing.

### 6.6 Background command processing

Today `WorkflowApplication.start()` and `stop()` can drive `process_next()` while awaiting a committed outcome. A future long-lived host is a natural place for an independent processor/worker, consistent with ADR 0006 §4.4.

**This is not a 6C.2/6C.3 task.** Worker scheduling, crash recovery, fencing, idle behavior and process ownership need a separately reviewed design. A host subscription server must not be mistaken for automatic safe background processing.

## 7. Decisions versus open work

### 7.1 Agreed and binding for 6C

- Use the already implemented SDK state model and reducers.
- Publish authoritative **post-commit state**, not transition proposals or submission receipts.
- SDK-defined observation interfaces; persistence-adapter-owned change delivery.
- SDK-owned read/reconstruction/fan-out; frontend does not replay domain events.
- No SDK polling framework, new state hierarchy, peer-to-peer sockets or host in 6C.
- Scope 6C to validated local observation and Explorer adoption; do not claim cross-process push.
- Maintain ADR 0006's future cross-process, recovery and ordering requirements.
- Preserve no-implicit-write, fail-closed restoration, transaction and owner-safety invariants.

### 7.2 Agreed direction for the future host

- New long-running SDK-consuming app **inside** Rudra's monorepo.
- Platform-specific OS service management rather than SDK-side daemon spawning.
- Multiple terminal/desktop/web/mobile frontends share one trusted application state via host transport.
- Local IPC and remote network access have different security requirements.
- Host remains a client/adapter of SDK authority and must not implement a competing workflow engine.

### 7.3 Still open — design before coding

**For 6C.2:** exact observation API, persistence change-source shape, registration/read race protocol, shared notifier lifecycle, revision/cursor semantics, error/terminal behavior, local notification failure recovery, coalescing/deduplication and SQLite transaction callback integration.

**For the host milestone:** service registration, real IPC choice, host/client protocol, auth and pairing, process lifetime, reconnect/catch-up and ordering, multi-client/subscription resource limits, remote exposure, background worker scheduling and treatment of other processes that access the same journal directly.

Do not describe these choices as implemented or settled in code examples.

## 8. Working procedure and acceptance rules

- Inspect newest pushed repository state before each slice. The implementation, not a dated illustration, determines exact code edits.
- Discuss and agree on public interface ownership and failure behavior **before** implementation.
- Work by **coherent architectural responsibility**, not single-file increments or arbitrary three-file batches.
- Default to manual collaboration with exact paths and BEFORE/AFTER replacements. Generated apply scripts and ZIPs are requested explicitly if needed.
- Keep public DartDocs clear about purpose, parameters, returns, exceptions, side effects and ownership without drowning simple code in commentary.
- Keep generic SDK contract tests synthetic, feature action tests separate, and persistence safety integration tests on real Drift/SQLite.
- Run format, affected tests, full verification and `git diff --check`; inspect the pushed commit after each completed slice.
- Mark only genuinely verified capabilities done. Deferred cross-process tests are not a reason to conceal scope or a reason to fake green coverage.

## 9. Repository reference points

- [Parent Epic 6](rudra-epic-6-architectural-realignment.md)
- [ADR 0006](../decisions/0006-event-sourced-workflow-architecture.md) — §§4.4, 7 and 8.4
- [`RudraState`](../../packages/sdk/lib/src/state/rudra_state.dart)
- [`WorkflowsState`](../../packages/sdk/lib/src/workflow/states/workflows_state.dart)
- [`WorkflowSnapshot`](../../packages/sdk/lib/src/workflow/states/workflow_snapshot.dart)
- [`WorkflowStateMachine`](../../packages/sdk/lib/src/workflow/workflow_state_machine.dart)
- [`WorkflowRuntime`](../../packages/sdk/lib/src/workflow/workflow_runtime.dart)
- [`WorkflowProcessor`](../../packages/sdk/lib/src/workflow/processing/workflow_processor.dart)
- [`WorkflowCommitter`](../../packages/sdk/lib/src/workflow/processing/workflow_committer.dart)
- [`WorkflowStateReader`](../../packages/sdk/lib/src/workflow/reading/workflow_state_reader.dart)
- [`WorkflowApplication`](../../packages/sdk/lib/src/workflow/application/workflow_application.dart)
- [`WorkflowApplicationPersistence`](../../packages/sdk/lib/src/workflow/application/workflow_application_persistence.dart)
- [`DriftWorkflowCommitter`](../../packages/persistence/sqlite/lib/src/features/workflow/history/drift_workflow_committer.dart)
- [`ProductWorkflowComposition`](../../apps/cli/lib/src/composition/product_workflow_composition.dart)

**Guiding constraint:** Extend the existing **validated commit → SDK state → subscriber** path, not the state machine. Finish 6C's local observation honestly; implement multi-process and remote subscriptions later through a separately designed trusted SDK-consuming host.
