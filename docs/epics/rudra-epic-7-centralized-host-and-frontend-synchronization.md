# Rudra — Epic 7: Centralized Host and Frontend Synchronization

**Status:** Planned — architecture agreed, implementation not started  
**Created:** 24 November 2026  
**Repository:** https://github.com/ibrahimab/rudra  
**Baseline reviewed:** `98d43b6a6260cb85c1139b00d947ecd8bda73a3f` (23 November 2026)  
**Predecessors:** [Epic 6 — Architectural Realignment](rudra-epic-6-architectural-realignment.md) and [Epic 6C — Observability and Future Trusted Host Direction](rudra-epic-6c-observability-and-trusted-host-direction.md)  
**Architectural authority:** [ADR 0006 — Event-Sourced Workflow and Reactive SDK Architecture](../decisions/0006-event-sourced-workflow-architecture.md)

## 1. Purpose

Move Rudra's trusted application execution and persistence ownership out of independent frontend processes into **one per-user, long-running Rudra Host**. The host shall execute the existing SDK application machinery and distribute validated committed application state to connected frontends.

This is the next architectural foundation for CLI, interactive Explorer, and later desktop, mobile, and web clients. The immediate deliverable is a **small, working local macOS host**, not a generalized distributed-services framework.

### Acceptance scenario

1. Terminal A runs `./rudra explore` and displays the verified current workflow state.
2. Terminal B runs `./rudra workflow start`, or another Explorer presses **S**.
3. The host durably accepts and processes the requested command through the existing SDK, validates the transition, and commits through its owned SQLite persistence context.
4. Every connected Explorer receives a verified updated `RudraState` without needing a navigation key, manual reload, or process restart.
5. A simultaneous Start from two independent frontends cannot establish two unfinished workflows for the same trusted OS user. At most one distinct Start succeeds; the other receives the correct conflict/rejection outcome.
6. Stopping a workflow from either CLI or Explorer similarly updates all connected clients. Exiting Explorer leaves the committed workflow intact.

This epic is complete only when the scenario is proven with **separate operating-system processes**, not merely several observers in one test isolate.

## 2. Decision and ownership boundaries

### 2.1 One host owns the application runtime and persistence

For a given authenticated macOS user and Rudra persistence scope, one host process shall own:

- The composed `WorkflowRuntime` and `WorkflowApplication`.
- SDK command processing (`EventManager`, `WorkflowProcessor`, `WorkflowStateMachine`) through their existing contracts.
- The SQLite/Drift persistence adapter, database connection lifetime, transactional committer, journal, inbox, projections, and submission resolution.
- The existing post-commit `WorkflowCommitPublisher.publish()` and `WorkflowCommitSubscriber.watch()` context.
- SDK state restoration/observation and client subscription fan-out.

**The host is the sole intended writer for official Rudra frontend operations.** Production CLI/Explorer clients shall not open workflow SQLite connections, instantiate their own workflow processors, or persist workflow outcomes directly after cutover. No direct-SQLite fallback is permitted when the host is unavailable.

Host ownership is not a replacement for transactional safety. SQLite constraints, compare-and-set validation, workflow identity/version checks, durable idempotency, and ownership invariants remain authoritative even when a single host coordinates requests.

One host-owned persistence context is the architectural target; implementation must confirm actual Drift/SQLite connection behavior rather than claiming physical single-connection guarantees without verification.

### 2.2 Frontends remain thin consumers

A frontend may own navigation, terminal input, rendering, local selection, view models, and explicit user-action handling. It communicates with the host through an **application-facing client contract** for supported operations and state observation.

A frontend does **not** call `WorkflowStateMachine` directly. It requests `WorkflowApplication` operations **through the host**, which uses the existing state machine internally. The host does not reimplement lifecycle rules, outcome transitions, typed reducers, journal replay, or safety policy.

Explorer's **S** and **X** actions and `./rudra workflow start|stop` must converge on the same host-side application operations. Feature-specific frontend actions remain independently registered. Generic terminal key decoding remains unaware of workflow semantics.

### 2.3 Existing SDK observation remains the inner boundary

`WorkflowCommitPublisher.publish()` is a **post-commit signal**. It is not a command-submission bus and does not precede database writes. Within the host, the existing SDK observation path remains:

```text
Explicit client command
  → Host application endpoint
  → WorkflowApplication / durable inbox / WorkflowProcessor
  → WorkflowStateMachine proposal and validation
  → WorkflowCommitter → atomic SQLite transaction
  → WorkflowCommitPublisher.publish() (after success)
  → WorkflowCommitSubscriber.watch()
  → WorkflowStateObserver + validated journal restoration
  → immutable RudraState
  → Host state stream → connected frontends
```

The host sends **verified application state**, not uncommitted proposals, raw frontend-replayed domain events, or an accepted submission masquerading as a completed transition.

### 2.4 One process owner is not a new workflow lifecycle

A workflow persists independently of the host process, client connection, terminal, or frontend. Starting/stopping the host never implicitly starts/stops a workflow. A host restart reconstructs the current workflow from the authoritative journal.

One host per trusted user/scope is **process and resource ownership**, not a new domain session. The current one-unfinished-workflow-per-user rule continues to be enforced by SDK/persistence, not merely by the host's request queue.

## 3. Target topology

```text
Terminal A: ./rudra explore    Terminal B: ./rudra workflow start|stop
            |                             |
            +-----------+-----------------+
                        |
                 Local client API
            (commands, reads, subscriptions)
                        |
            Authenticated local IPC
                        |
                Rudra Host (apps/host)
                per trusted OS user
                        |
              WorkflowApplication
              /               \
       SDK processing      SDK observation
              |               ^
       WorkflowCommitter      | watch()
              |               |
      SQLite/Drift journal -- publish()

Future desktop/mobile/web frontends use the same application-facing
semantics through their appropriate authenticated transport adapters.
```

The host is a **new pure-Dart SDK-consuming application in the existing monorepo** (proposed location: `apps/host`). Do not put platform service management inside the SDK or create a new SDK/domain implementation for the host. Any shared client/transport package is justified by actual dependencies, not pre-created from a speculative diagram.

## 4. Local MVP boundaries

### Included

- One macOS per-user host and one configured local persistence scope.
- One deliberately managed host listener; initially runnable explicitly for development.
- Local IPC for multiple CLI processes (Unix-domain socket is the leading design; verify platform details before coding).
- Authenticated/trusted local owner resolution and socket/path permission controls.
- Application-facing **read current state**, **observe state**, **Start**, and **Stop** operations, with typed outcomes and errors.
- Shared host-side SDK processing/persistence and post-commit state distribution.
- Integration of both existing CLI workflow commands and Explorer action/display paths.
- Safe initial subscription, disconnect, cancellation, reconnection/re-synchronization, and host shutdown behavior.
- macOS-managed activation/lifecycle integration after the explicitly runnable host works (per-user `launchd` agent is the agreed direction; mechanics require platform verification).

### Deferred

- Network exposure, pairing, remote authorization, TLS/WebSocket delivery, and actual Android/web clients.
- Generalized background command scheduling, crash recovery workers, or automatic filesystem cleanup.
- New workflow domain states, Pause, candidate planning/execution, and destructive-operation gatekeeper changes.
- Durable cross-restart stream cursors or a full historical event-feed API; journal restoration remains authoritative.
- Multiple database backends or clustered/replicated hosts.
- Unrestricted arbitrary event submission from untrusted clients.

**Offline behavior:** Until an explicit offline-capable contract is designed, a client unable to reach the host reports the host as unavailable. It shall not silently open SQLite or invent a verified `Workflow: NONE` state.

## 5. Correctness, concurrency, and transport requirements

### 5.1 Competing Start requests

When two independent clients request Start at the same moment:

1. Both requests reach the host with distinct request identities/idempotency semantics.
2. Request execution is coordinated so the application can safely handle overlap; simple transport ordering is not itself the authority.
3. The SDK/persistence transaction and unique-owner constraints establish at most one unfinished workflow.
4. One distinct request may confirm a committed `WorkflowStartedEvent`; the competing request must produce the appropriate typed conflict/rejection, not a second workflow.
5. Both subscribed clients ultimately observe the same verified winner. Submission acceptance must never be rendered as committed Active.

A duplicate retry using the same idempotency identity must not create another workflow. Request loss near the commit boundary must be handled by checking durable resolution where supported, not by claiming failure or blindly resubmitting.

### 5.2 Initial state and update ordering

A newly connected client must receive an authoritative current `RudraState` followed by coherent committed updates **without a silent gap**. The host must coordinate subscription registration and initial restoration to avoid missing commits between the two.

Do not use `WorkflowSnapshot.version` as a global change counter: version is local to a workflow and cannot order **workflow A → none → workflow B**. If transport ordering needs a revision, use an explicit host-stream sequence and host instance/generation identity or another justified equivalent. Do not describe a volatile sequence as a durable journal cursor.

Rapid notifications may coalesce into a latest validated state; there is no guarantee that clients see every intermediate state. The durable journal remains the audit record.

### 5.3 Transport framing and extensible state representation

Define the minimal wire contract for correlation, operation results, typed errors, state snapshots, stream completion, and protocol version/compatibility. Use bounded messages and explicit backpressure/error behavior.

The transport represents **SDK application semantics** and must accommodate registered feature-owned state slices later. Do not hardcode a permanent Start/Stop-only state model, transfer unchecked dynamic domain bags, or make frontend clients reimplement the event replay engine. Decide codec ownership/registration at the appropriate composition boundary **before** implementation.

### 5.4 Disconnect, reconnect, and failure

- A disconnected client releases its subscription resources; it does not stop a workflow.
- On reconnect or host restart, the client obtains **fresh validated state** before resuming updates. Old host generations/streams must not overwrite newer state.
- A failed read, broken stream, missing host, or corrupted journal is an explicit unavailable/error condition, not verified absence.
- Errors during Explorer interaction must not leave terminal modes or cursor state unrestored.
- A host crash may leave durable accepted submissions unresolved; do not claim background processing or automatic recovery until implemented and tested.

### 5.5 Trust and process exclusivity

Trusted identity comes from the host's OS context and authenticated local transport, **not** a client-supplied `os_user_id`. Validate IPC peer identity where supported and secure socket/database directories. Do not expose the local service on a network interface by default.

Use an explicit single-owner strategy for host startup and database access. Multiple competing host instances must fail closed or resolve to the same authorized owner; do not assume a socket filename alone solves races. Official clients must use host transport after migration, including workflow commands as well as Explorer. An unrelated process deliberately opening the same database under the same OS account is outside the cooperative single-writer guarantee unless stronger OS isolation is introduced; preserve SQLite safety validation regardless.

### 5.6 Read-only and destructive-operation safety

Connecting, observing, rendering, navigating, quitting, cancelling, and reading verified absence must not create an absent database or submit/process commands. Only explicit authorized Start may initialize workflow storage as currently designed. No filesystem cleanup occurs from host startup or subscription notifications. Existing append-only journal, quarantine, outbox, revalidation and execution-gatekeeper requirements from ADR 0006 remain intact.

## 6. Implementation slices

Slices are defined by **coherent responsibilities**, not file counts. Agree on interfaces and failure semantics before editing, verify each slice, then inspect the pushed commit.

### 7A — Host foundation and trusted composition

**Goal:** A pure-Dart host process owns one long-lived SDK application/persistence context and can be started/stopped explicitly for development.

- Add the host application and its composition root, reusing existing SDK/persistence packages.
- Resolve trusted user/scope and storage location once at the host boundary.
- Establish safe host lifecycle and deterministic resource disposal.
- Introduce a local IPC listener and a single-owner strategy; validate startup/security failures.
- Preserve read-only missing-database behavior.

**Gate:** One host can serve multiple local connections while owning the application context; no frontend database usage has been migrated yet. Host startup/shutdown and ownership are testable without altering domain code.

### 7B — Host application command contract

**Goal:** Independent clients can invoke the same SDK operations through the host.

- Establish minimal request/response framing and typed error/correlation semantics.
- Expose current-state read, Start, and Stop through the existing `WorkflowApplication`.
- Coordinate concurrent host requests without weakening transaction-level checks.
- Preserve durable acceptance versus confirmed commitment and idempotency behavior.
- Test simultaneous competing Starts from separate client connections.

**Gate:** Concurrent Start yields at most one unfinished workflow and correct per-request outcomes, verified against real SQLite journal evidence.

### 7C — Host state subscriptions and reconnection

**Goal:** The host distributes validated SDK application state to multiple clients.

- Reuse `WorkflowApplication.observe_state()` and the host-owned `publish()`/`watch()` context.
- Provide initial verified snapshot + subsequent committed updates with no unreported startup gap.
- Define stream generation/ordering, bounded fan-out, cancellation, errors, and reconnect re-synchronization.
- Keep transport representation extensible for future registered state slices.

**Gate:** Multiple independent client connections observe committed Start/Stop without manual refresh, including overlap with initial subscription and a reconnect after host restart.

### 7D — CLI and Explorer host-client cutover

**Goal:** Official frontend entry points all use the host as the sole workflow application/persistence owner.

- Route `./rudra workflow start|stop` through a host client adapter.
- Route Explorer **S/X** through the same client operations; use the host state stream for header/actions.
- Preserve physical input decoding, feature action registry, focused view models, and stateless widgets.
- Serialize interactive input and observation-triggered renders to avoid redraw races.
- Cancel subscriptions and release connections on Q, EOF, interrupt, error, and terminal restoration.
- Remove production frontend-local workflow SQLite/processor composition rather than retaining a hidden fallback.

**Gate:** Two independently running Explorers and a CLI command share one host, render committed changes correctly, and never open workflow persistence in their own processes.

### 7E — Managed macOS host and end-to-end verification

**Goal:** Finish the smallest usable local service lifecycle and prove the cross-process acceptance scenario.

- Verify and implement the per-user macOS `launchd` installation/activation contract; keep explicit setup under user control.
- Make service-unavailable and startup-conflict behavior explicit. SDK constructors do not launch daemons.
- Run multi-process concurrency, lifecycle, restart/reconnect, permission, terminal-restoration, and missing-storage tests.
- Update architecture and usage documentation only after implementation evidence is available.

**Gate:** A fresh macOS installation with the host deliberately configured can run the two-terminal acceptance scenario; disconnects and host restarts restore truthful state without duplicate workflow commitments.

## 7. Test architecture and acceptance checklist

Test at the feature's owning boundary. Prefer separate unit, contract, real-persistence integration, and process-level tests. Do not expand generic terminal decoder tests for new workflow actions.

- **Host unit/contract:** request routing, identity scope, message validation, typed errors, registration/codec behavior, resource ownership, graceful shutdown.
- **SDK/persistence regression:** existing state-machine replay, atomic commit, owner uniqueness, expected identity/version, idempotency, rejected/quarantined submission semantics, no publication on rollback.
- **Real host integration:** two simultaneous Start requests with barriers (not timing sleeps), Start-vs-Stop races, committed change fan-out, failed commit silence, and reconnect to verified journal state.
- **Actual process integration:** separate host, CLI commands, and at least two Explorer processes; process termination, competing host startup, socket permission/identity enforcement, and no accidental frontend SQLite usage.
- **Explorer integration:** initial verified display, external live Start/Stop, navigation-vs-notification ordering, stale displayed workflow ID guard, no phantom Active, terminal restoration and subscription cleanup on every exit path.
- **No-write checks:** absent database stays absent after host/client construction, read, observe, navigation and Quit; Start is the explicit initialization path.

At every completed slice, run formatting, affected tests, full `./rudra verify all`, `git diff --check`, and inspect the resulting commit. Do not mark a behavior implemented or green without the corresponding execution evidence.

## 8. Architectural safeguards and change-impact test

- **SDK first:** Domain semantics, transitions, reducers, journal validation, processing and application operations remain implemented once in the SDK.
- **One persistence owner:** Host composition owns SQLite and its notification channel; frontends use transport clients.
- **Feature isolation:** A new future operation such as Pause primarily adds a domain feature, its host-exposed application operation/registration, its frontend feature contribution, and isolated tests—not workflow branches throughout generic runners or transport decoders.
- **No premature framework:** Implement only contracts required for the local MVP. Avoid general-purpose RPC, event buses, entity repositories, or a second application state hierarchy without concrete need.
- **No hidden policy:** The host coordinates application access and transport; it does not introduce business transition rules or weaken SDK persistence guards.
- **Safety first:** Client visibility never grants permission for cleanup. Destructive actions remain behind the independent authorization and execution gatekeeper.

## 9. Existing work retained and superseded plans

**Implemented baseline retained:** Epic 6A feature-owned Explorer action registration; Epic 6B immutable composite `RudraState`/`WorkflowSnapshot`, typed slices and state-machine replay; Epic 6C.1 `WorkflowApplication` operations; Epic 6C.2 post-commit publisher/subscriber, local observation, validated read-only restoration, and associated tests.

**Plan superseded:** Epic 6's planned **6C.3 Explorer-only local observation wiring** is replaced by Epic 7's host-owned application/persistence model and eventual Explorer host-client integration. The earlier host design is promoted from *future direction* to the scope of this epic.

**Historical documents:** Preserve both Epic 6 Markdown files **unchanged** as records of the earlier decisions and implementation status. Their prior “6C.3 planned” and “host deferred” statements are historical, not current execution instructions. For new host work, this Epic 7 plan takes precedence; ADR 0006 continues to govern domain and safety invariants. Epic 6's unrelated 6D–6F work remains separate and can be revisited after the host cutover as appropriate.

## 10. Working procedure and documentation rules

1. Inspect the latest pushed repository state before each slice; do not implement from stale examples.
2. Agree on public contract ownership, lifecycle, and failure behavior before editing code.
3. Work collaboratively with exact file paths and focused BEFORE/AFTER changes by default. Produce bulk apply scripts or ZIPs **only when explicitly requested**.
4. Keep each slice coherent, independently testable, and scoped to its responsibility; avoid arbitrary file-by-file micro-slices or broad rewrites.
5. Favor additive feature ownership and explicit composition over modifications to generic infrastructure. Break pre-release interfaces cleanly when required; do not add temporary compatibility machinery without a reason.
6. Write purposeful DartDocs for public types, constructors and methods: describe responsibility, parameters, return values, meaningful exceptions, ownership/lifetime and side effects where relevant. Avoid filler and documentation that only narrates syntax.
7. Keep SDK contract tests synthetic, component tests feature-local, persistence safety tests backed by real SQLite/Drift, and cross-process guarantees proven with actual OS processes.
8. Verify locally, commit, push, then review the updated repository before calling a slice complete.

## 11. Open decisions to resolve within the relevant slice

These are **design checkpoints**, not permission to replace the agreed host ownership model:

- **7A:** Exact local socket placement, ownership/locking mechanism, trusted peer identity verification, and explicit development launch command.
- **7B:** Minimal message envelope, protocol evolution, idempotency-key handling across lost responses, and whether command handling is queued or otherwise safely serialized.
- **7C:** Host-stream generation/revision representation, bounded subscriber queues, and registered serialization of future typed SDK state slices.
- **7D:** Reusable client interface location and Explorer's serialized input/observation event loop.
- **7E:** Concrete `launchd` registration and activation flow, service packaging, restart policy, and treatment of an unavailable/disabled host.

Decide these from inspected code and real platform constraints immediately before implementation. Do not present proposed wire APIs or service mechanics as existing capabilities.

## 12. Reference points

- [Epic 6 — Architectural Realignment](rudra-epic-6-architectural-realignment.md)
- [Epic 6C — Observability and Future Trusted Host Direction](rudra-epic-6c-observability-and-trusted-host-direction.md)
- [ADR 0006 — Event-Sourced Workflow and Reactive SDK Architecture](../decisions/0006-event-sourced-workflow-architecture.md)
- [`WorkflowApplication`](../../packages/sdk/lib/src/workflow/application/workflow_application.dart)
- [`WorkflowStateObserver`](../../packages/sdk/lib/src/workflow/observation/workflow_state_observer.dart)
- [`RudraState`](../../packages/sdk/lib/src/state/rudra_state.dart)
- [`RudraSqlitePersistence`](../../packages/persistence/sqlite/lib/src/sqlite_persistence.dart)
- [`ProductWorkflowComposition`](../../apps/cli/lib/src/composition/product_workflow_composition.dart)
- [`ExplorerRunner`](../../apps/cli/lib/src/features/explorer/application/explorer_runner.dart)

**Guiding acceptance criterion:** The host is the one trusted home for workflow application execution and persistence; independent frontends issue the same SDK-backed operations and react to the same verified committed state, without creating competing application/persistence stacks.
