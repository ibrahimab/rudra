# Rudra — Epic 6C: Observability and Future Trusted Host Direction

**Status:** 6C.1 and **6C.2 implemented; 6C.2 developer-verified green**. 6C.3 remains planned. Local in-process observation is available; cross-process delivery remains a future trusted-host requirement.  
**Decision dates:** 22 November 2026 (observation/host direction); 23 November 2026, Europe/Amsterdam (SDK publisher/subscriber ports agreed)  
**Code baseline inspected:** `d326fbda9232141ba807e54d5578a70292c40424` (23 November 2026)  
**Parent epic:** [Epic 6 — Architectural Realignment](rudra-epic-6-architectural-realignment.md)  
**Normative architecture:** [ADR 0006 — Event-Sourced Workflow Architecture](../decisions/0006-event-sourced-workflow-architecture.md)  
**Scope:** Detailed design and implementation boundaries for 6C.2–6C.3; future host as a separately planned milestone

## 1. Purpose and decision summary

This document records the agreed observation architecture, its **implemented local 6C.2 SDK/persistence boundary**, the planned **6C.3 Explorer adoption**, and the separate **future trusted-host topology**. It distinguishes existing code and verified scope from future capabilities and unsettled transport/recovery decisions.

**Decisions and implementation status:**

1. Build **reactive observation of authoritative SDK application state**. Reuse the existing `RudraState`, `WorkflowsState`, `WorkflowSnapshot`, transitions, reducers, replay and `WorkflowApplication`.
2. The **SDK defines two complementary persistence-notification ports**: `WorkflowCommitPublisher.publish()` and `WorkflowCommitSubscriber.watch()`. Persistence adapters (SQLite today, MySQL or others later) **consume the publisher port** and call `publish()` only after an authoritative atomic commit. SDK application observation consumes `watch()` from the paired, shared notification context; it restores and publishes validated immutable `RudraState`. The adapter does not construct domain/application state.
3. The state machine computes new immutable `WorkflowSnapshot` values through registered transitions and feature-owned reducers, but **does not own subscribers or publish state**. The persistence publisher signals **after** a successful commit; SDK observation reconciles through the same state machine via `WorkflowStateReader`. A returned `WorkflowProcessingCommitted(plan)` is not a subscription event.
4. **6C.2 delivers in-process observation** through the selected/shared persistence observation source. **6C.3 integrates Explorer**. Do not implement a background host or peer-to-peer IPC for 6C.
5. **Cross-process live fan-out, host/client reconnection and remote mobile/web subscriptions remain future requirements.** A durable journal enables later restoration but is not a cross-process push channel on its own.
6. The future **Rudra Trusted Host is another SDK-consuming application within the same monorepo**—not a new repository, alternate SDK, competing state machine or database authority.
7. **The SDK does not spawn or manage OS services.** A future macOS host is provisioned and activated by a platform-specific service lifecycle; frontends connect through application-facing contracts.
8. **6C.2 contracts are implemented:** `WorkflowCommitPublisher.publish({required String os_user_id})` signals completed commits; `WorkflowCommitSubscriber.watch({required String os_user_id})` exposes `Stream<void>` owner-scoped hints; `WorkflowApplication.observe_state()` exposes `Stream<RudraState>` validated application snapshots. This local protocol has no durable revision cursor.

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

A snapshot is a **domain value**, not an event stream. Reducers and transitions do **not** broadcast notifications. The state machine intentionally has no persistence, network, terminal or UI dependencies. Its existing `transition()` constructs each new immutable snapshot from the previous snapshot and event; `replay()` applies the same transformation to committed history. Observation reuses this engine through `WorkflowStateReader`, rather than building a second domain reducer.

### 2.3 What 6C.1 and 6C.2 implemented

`WorkflowApplication` offers:

```dart
Future<RudraState> read_state();
Stream<RudraState> observe_state();
Future<EventSubmissionReceipt> submit_command(...);
Future<WorkflowSubmissionResolution?> status_for(...);
Future<WorkflowProcessingResult> process_next();
Future<WorkflowSnapshot> start(...);
Future<String> stop(...);
```

These are **implemented responsibilities** as of 6C.2; signatures above are abbreviated except for `read_state()` and `observe_state()`.

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

The processor uses successful `Future<void> WorkflowCommitter.commit(plan)` as confirmation of durable commitment. As of 6C.2, SQLite composition wraps the transactional committer in `PublishingWorkflowCommitter`, invoking `publish()` on the shared local channel **after** commitment. SDK observation consumes `watch()` and reconstructs state through validated persistence evidence. `WorkflowProcessingCommitted` remains an immediate result, not the subscription event.

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

A workflow-local `version` cannot represent the global ordering of A → no unfinished workflow → B. 6C.2 uses a subscription-local change counter to detect notifications overlapping an authoritative read; it is **not a durable revision token**. The journal records a database-global `sequence`, but no durable observation cursor/reconnect handshake is defined. Those remain future host-protocol design requirements.

### 3.2 Staged implementation promise

| Behavior | In 6C.2/6C.3? | Eventual host milestone? |
|---|---|---|
| `read_state()` and validated restoration | Already implemented in 6C.1 | Reused |
| SDK subscription to initial authoritative state | **Yes — 6C.2** | Reused |
| React to commits from shared/local persistence notification source | **Yes — 6C.2** | Reused |
| Reconcile and emit coherent post-transaction snapshots | **Yes — 6C.2, coalescing allowed** | Reused |
| Local missed-signal reconciliation, initial handshake and explicit failure | **Yes — 6C.2** | Extended |
| Explorer UI follows an active subscription | **Yes — 6C.3** | Reused or adapted |
| Independent CLI processes receive live updates | **No** | **Yes, after host exists** |
| Host disconnection, client reconnection and live catch-up | **No** | **Yes** |
| Remote authenticated web/mobile subscriptions | **No** | **Yes, later** |
| Visibility of committed state after a fresh cross-process restore | **Already supported by persistence restoration** | Reused |

**Precise scope note:** “Same process” does not mean arbitrary independently constructed persistence contexts magically share notifications. The implementation must define the source/lifetime that local subscribers share. Separate OS processes require a real communication mechanism; no in-memory Dart stream crosses that boundary.

This is a documented interim scope. When closing 6C, do not label the original cross-process requirement or its tests as satisfied.

## 4. Agreed ownership: SDK-defined `publish()` / `watch()` ports

### 4.1 Why the state machine is central but not the publisher

`WorkflowStateMachine.transition(previous, outcome)` constructs an **entirely new immutable `WorkflowSnapshot`** using the registered lifecycle transition and feature-slice reducers; it does not retain or broadcast a mutable "current state". `WorkflowStateMachine.replay()` reuses these transformations to reconstruct history deterministically. Keep that pure design.

A valid transition is only a **proposal** until persistence independently validates and commits the corresponding outcome events. A transaction may fail after the processor calculates `WorkflowProcessingPlan.resulting_state`. Publishing from the state machine would expose a workflow that may not exist durably.

There is also a distinction between a committed **workflow** snapshot and the observable **application** snapshot: Stop commits a terminal `WorkflowSnapshot`, whereas `RudraState.workflows.current_workflow` then becomes `null` (verified absence of an unfinished workflow). Additional domain collections may later join `RudraState`.

**Decision:** Use the existing state machine to compute and restore domain values; use the persistence commit boundary to trigger observation; use `WorkflowApplication` to expose current authoritative application state. No parallel reducer, lifecycle model or event journal.

### 4.2 Paired ports and ownership

The **SDK owns the two interface contracts**. They are complementary sides of one change-notification channel, not independent sources of truth:

| Contract / component | Responsibility |
|---|---|
| `WorkflowCommitPublisher` | Persistence-facing SDK port. A SQLite/MySQL/other adapter invokes **`publish()` only after its authoritative transaction succeeds**. It reports a change hint, not a domain state object. |
| `WorkflowCommitSubscriber` | SDK-observation-facing SDK port. The SDK consumes **`watch()`** to receive change hints for its trusted owner scope. |
| Shared notification implementation | One explicitly composed instance/bus joins publisher and subscriber for the supported application/persistence lifetime. Its underlying mechanism may be in-memory for 6C or adapter-specific later. |
| `WorkflowCommitter` | Revalidates proposal, owner, expected version, journal and projection, then atomically commits. It triggers the publisher **after** transaction completion, not within the transaction. |
| `WorkflowStateMachine` | Pure transition and reducer engine, reused for deterministic journal replay; legitimate future implementation changes are not prohibited. |
| `WorkflowStateReader` | Revalidates committed evidence, replays outcomes and reconstructs the trusted owner's unfinished state or verified absence. |
| SDK application observation | `WorkflowStateObserver` consumes `watch()`, serializes per-subscriber reconciliation, and exposes immutable `RudraState`. Multiple local listeners receive independently reconstructed states. |
| Frontend / future trusted host | Consumes validated SDK application snapshots; never derives lifecycle authority from notification hints. |

The publisher is **defined by the SDK and consumed by persistence**, not a SQLite-defined dependency that the SDK imports. The **same SDK ports** are reused if `packages/persistence/mysql` is introduced. There is no change to SDK domain transitions, reducers or observation semantics merely because the database adapter changes.

**Implemented composition:** Each `RudraSqlitePersistence` owns one `LocalWorkflowCommitChannel`, shared by its `PublishingWorkflowCommitter` and `WorkflowApplicationPersistence.workflow_commit_subscriber`. `WorkflowApplication` passes that subscriber to the SDK observer. Distinct SQLite persistence instances do **not** implicitly share the channel, even inside one OS process. Notification owner scope comes from trusted `os_user_id`, not submission scope or an untrusted frontend parameter. Future adapters can implement the same SDK ports with a different shared mechanism.

### 4.3 Implemented SDK contract signatures and local semantics

The SDK defines the following **implemented** contract signatures in `workflow_commit_channel.dart`. The `Stream<void>` contains change hints only; it does not represent a durable sequence or guarantee recovery from signals lost outside the shared channel lifetime:

```dart
/// Persistence-facing SDK port for successful workflow commitments.
abstract interface class WorkflowCommitPublisher {
  /// Signals a successfully committed change for trusted [os_user_id].
  /// Invoked only after the authoritative transaction has completed.
  void publish({required String os_user_id});
}

/// SDK observation-facing port for committed-change hints.
abstract interface class WorkflowCommitSubscriber {
  /// Watches changes associated with trusted [os_user_id].
  /// Watching has no persistence or workflow side effects.
  Stream<void> watch({required String os_user_id});
}
```

The SDK observer subscribes before the initial read and uses a local change counter to reconcile overlapping reads. Rapid local commits may be coalesced into the latest validated application state. A durable generation/revision token or reconnect handshake remains a **future cross-process requirement**; a workflow-local version cannot serve as an application-wide revision.

Existing application API:

```dart
Future<RudraState> read_state();
```

Implemented application-facing API:

```dart
Stream<RudraState> observe_state();
```

A frontend sees `RudraState`, not `Stream<WorkflowSnapshot>` or raw domain events. The frontend never calls `publish()` or `watch()` directly to implement its own state machine. `WorkflowApplication` or a narrow SDK-owned internal collaborator coordinates observation.

### 4.4 Implemented local committed-state data flow

```text
Explicit user action
    |
    v
SDK command behavior → WorkflowStateMachine.transition()
    |                  produces immutable proposed WorkflowSnapshot
    v
WorkflowProcessor → WorkflowCommitter
    |                  independently validates and atomically persists outcomes
    v
Successful transaction completion
    |
    +--> SDK WorkflowCommitPublisher.publish()   [called by persistence adapter]
    |                 |
    |                 v
    |         shared commit-notification channel
    |                 |
    |                 v
    |         SDK WorkflowCommitSubscriber.watch()
    |                 |
    |                 v
    |         SDK observation coordinator
    |                 |
    |                 v
    |         WorkflowStateReader → WorkflowStateMachine.replay()
    |                 |
    |                 v
    |         validated immutable RudraState → frontend / future host
    |
    +--> WorkflowProcessingCommitted(plan) to processor caller
```

The two branches are different: **processing returns a durable command result**; **observation publishes the latest validated application state**. A submission receipt, processing proposal, or notification payload does not itself establish authoritative state.

`WorkflowProcessingPlan.resulting_state` is attractive as an optimization because it was already computed, but **do not broadcast it as authoritative in 6C.2**. The current SQLite committer's snapshot comparison does not establish equality of every feature-owned slice; deeper persistence generalization and validation belong to 6D. Even when fully verified later, terminal workflow state needs correct composition into `WorkflowsState`.

### 4.5 Commit and observation correctness

1. **Publish after durability:** `PublishingWorkflowCommitter` calls `publish()` once after a successful `commit(plan)`, never inside the SQLite transaction or from a pure transition. Start/Stop currently each commit one outcome; multi-outcome generic commit handling remains 6D work.
2. **No invented success:** a failed/rolled-back transaction produces no committed-state signal. Durable command acceptance, business rejection and quarantine are distinct from committed workflow-state changes.
3. **Notification cannot undo commitment:** the decorator logs publisher exceptions after a successful transaction instead of propagating a false commit failure. `LocalWorkflowCommitChannel` ignores publication after close. An undelivered hint can leave a live observer stale; recovery uses fresh authoritative restoration rather than an automatic unsafe retry.
4. **Authoritative reconciliation:** `watch()` signals that evidence *may have changed*. SDK observation reads and validates that evidence via `WorkflowStateReader` and the state machine before emitting `RudraState`; inconsistent/foreign/corrupt history fails closed rather than becoming `current_workflow == null`.
5. **Gap-aware initial read:** the observer registers `watch()` before the first authoritative read and reconciles signals that overlap that read. This closes the supported local registration/read race, not gaps from an unrelated process, disposed channel or failed publication.
6. **Ordering and coalescing:** serialize reconciliation so a slower earlier read cannot overwrite newer state; multiple rapid commits may be coalesced to a validated latest snapshot *only if* the contract does not promise every intermediate snapshot. For a complete change log, use the journal.
7. **Scoped shared lifetime:** committers and watchers share one local notification context, survive for the intended application session, and isolate trusted OS users. Closing the persistence owner or cancelling observation releases resources without publishing phantom changes.
8. **No implicit writes:** constructing observers, calling `watch()`, reading initial state, Explorer navigation/rendering and cancellation cannot submit/process commands, initialize an absent database or touch the target filesystem.
9. **Explicit failure:** restoration corruption and notification-source errors/shutdown terminate the subscription with an error rather than emitting verified absence. The current observer does not attempt automatic resubscription/recovery. Missing SQLite storage that has never been initialized is handled as verified absence without creating it.
10. **Process boundaries remain honest:** an in-memory watch cannot see commits from another OS process or an unrelated, unshared notifier. Restore from the journal on startup/reconnect. A future host adds IPC/network fan-out and must address out-of-band writers separately.

### 4.6 6C exclusions

- Preserve a pure SDK-owned `WorkflowStateMachine` transition/replay engine and avoid SDK polling; justified implementation changes to the state machine are allowed.
- No alternative mutable authoritative state, unvalidated publication of `plan.resulting_state`, or frontend replay of raw events.
- No background daemon, peer-to-peer IPC, WebSocket server, network permissions or platform service management.
- No assertion that distinct concurrently running `rudra explore` processes are automatically synchronized yet.
- No automatic command processing, recovery action or filesystem mutation just because a subscriber is connected.

## 5. Epic 6C implementation progression

### 6C.1 — Portable operations — IMPLEMENTED

`WorkflowApplication` now owns reusable state reads, durable submission/resolution and confirmed Start/Stop; CLI host composition owns trusted identity, path/permissions and SQLite adapter lifecycle. Tests were reported green at the latest documentation commit.

### 6C.2 — SDK `publish()` / `watch()` ports and observable application state — IMPLEMENTED; DEVELOPER-VERIFIED

**Cohesive responsibility:** Deliver validated initial `RudraState` and reconciled local committed changes through the portable SDK, independently of frontend event replay.

**Implemented components:**

- `WorkflowCommitPublisher.publish({required String os_user_id})` and `WorkflowCommitSubscriber.watch({required String os_user_id})` in the SDK; `LocalWorkflowCommitChannel` provides shared owner-scoped in-process hints.
- `PublishingWorkflowCommitter` wraps SQLite commits. A successful commit triggers one hint; delegate failure publishes nothing. Publication exceptions are logged without changing the durable result.
- `WorkflowApplication.observe_state()` delegates to `WorkflowStateObserver`, which uses authoritative `read_state()` / `WorkflowStateReader` / `WorkflowStateMachine.replay()` rather than trusting proposed `resulting_state`.
- The observer subscribes before initial restoration, discards reads overtaken by notifications, serializes reconciliation, coalesces rapid changes, independently serves multiple subscribers, and terminates on source/restoration errors.
- Lazy SQLite opening and `NonInitializingWorkflowHistoryStore` permit initial observation without creating missing storage; explicit Start may initialize storage, and existing observers then receive the committed change.

**Tests and evidence:** `0439b29`–`d326fbd` implement the ports, SQLite adapter, observer, end-to-end integration, missing-storage guard and lifecycle coverage. SDK synthetic tests exercise owner isolation, initial race, overlapping/replacement workflows, cancellation and failure. Real SQLite tests cover committed Start/Stop, multiple subscribers, accepted-but-pending silence and read-only missing storage. Separate Drift tests cover transaction rollback; separate decorator tests cover silence when the delegate fails and truthful commitment despite publisher exceptions. **A combined real SQLite rollback-plus-notification test and generalized multi-outcome commit integration are not separately established.** The developer reported `./rudra verify all` green on 23 November 2026; this document does not claim independent execution.

**Supported guarantee:** Shared, per-persistence-context in-process notification and validated application-state reconciliation; intermediate committed states may be coalesced. Notification hints carry no durable cursor. A delivery failure can leave a live observer stale until another signal or fresh restoration.

**Excluded:** Explorer wiring (6C.3), cross-process fan-out and reconnect/catch-up, host, IPC, remote clients and generalized continuation persistence (6D). ADR 0006's wider product guarantees remain future obligations.

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

The future Rudra host is a **long-running application inside the existing Rudra monorepo**, conceptually `apps/host`. It consumes the same SDK domain/application contracts, including the `publish()` / `watch()` observation pathway, target contracts and persistence adapters as other applications. It is not a separate repository or independent source of domain truth. Other storage backends (e.g. MySQL) call the same SDK publisher port; the host exposes validated SDK application state rather than database-specific notifications.

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
- SDK-defined `WorkflowCommitPublisher.publish()` and `WorkflowCommitSubscriber.watch()` ports, with one shared composition-owned notification context. Persistence adapters consume the publisher after successful transactions; SDK application observation consumes the watcher.
- SDK-owned read/reconstruction/fan-out through existing `WorkflowStateReader` / `WorkflowStateMachine`; frontend does not replay domain events. Do not directly broadcast an unverified proposed `WorkflowSnapshot`.
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

**6C.2 implemented:** SDK port signatures, wiring through `WorkflowApplicationPersistence`, shared local SQLite notifier lifetime, watch-before-read race reconciliation, serialized coalescing, cancellation and stream-error behavior, post-commit publication safety, and missing-storage read-only behavior. **Still open beyond 6C.2:** durable revision/cursor semantics, lost-hint recovery, cross-process live delivery, out-of-band writer detection and reconnection/transport ordering.

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
- [`WorkflowCommitPublisher` / `WorkflowCommitSubscriber`](../../packages/sdk/lib/src/workflow/observation/workflow_commit_channel.dart)
- [`WorkflowStateObserver`](../../packages/sdk/lib/src/workflow/observation/workflow_state_observer.dart)
- [`PublishingWorkflowCommitter`](../../packages/persistence/sqlite/lib/src/features/workflow/observation/publishing_workflow_committer.dart)
- [`NonInitializingWorkflowHistoryStore`](../../packages/persistence/sqlite/lib/src/features/workflow/history/non_initializing_workflow_history_store.dart)
- [`ProductWorkflowComposition`](../../apps/cli/lib/src/composition/product_workflow_composition.dart)

**Guiding constraint:** Reuse the implemented **state-machine proposal → validated persistence commit → SDK `publish()` → SDK `watch()` → state-machine-backed restoration → immutable `RudraState` → frontend** path without making the state machine stateful. 6C.3 will adopt local observation in Explorer; live multi-process and remote subscriptions remain a separately designed trusted SDK-consuming host milestone.
