# Rudra — Epic 6: Architectural Realignment

**Status:** In progress. **6A, 6B, 6C.1 and 6C.2 are implemented; 6C.2 developer-verified green.** 6C.3 and 6D–6F remain open. 6C.2 supports local, persistence-backed observation, not live cross-process delivery.  
**Original title:** Feature Isolation, Extensibility & Test Architecture  
**Canonical repository:** https://github.com/ibrahimab/rudra  
**Original audit baseline:** `ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513` (20 November 2026)  
**Latest code inspected for this revision:** `d326fbda9232141ba807e54d5578a70292c40424` (23 November 2026)  
**Previous milestone:** Block 5C — persistent Start → Active → Stop → Ended, SDK state machine, SQLite/Drift, CLI and Explorer  
**Companion design:** [Epic 6C — Observability and Future Trusted Host Direction](rudra-epic-6c-observability-and-trusted-host-direction.md)  
**Architectural authority:** [ADR 0006 — Event-Sourced Workflow Architecture](../decisions/0006-event-sourced-workflow-architecture.md)

## 1. Purpose and change-impact test

Rudra is an SDK-first, event-sourced, safety-first filesystem application. Workflow behavior and authoritative domain state are implemented once in the portable SDK and consumed by independent frontends. Adding a capability should primarily add feature-owned code, contracts, tests and explicit registration—not expand unrelated input decoders, central constructors, state holders or generic tests.

The hypothetical addition of **Pause** remains Epic 6's architectural acceptance test. Examine the changes required across SDK behavior, typed state slices, lifecycle transitions, safe persistence, application operations, observation, CLI, Explorer and tests. The architecture passes when changes are localized to the feature, explicit composition points and legitimately affected UI. Editing an Actions widget to display `P Pause` is an appropriate UI change; editing a generic terminal key decoder to understand Pause is not.

This epic is the implementation plan and architecture baseline for **6A–6F**. Its companion document is the detailed source of truth for the **agreed 6C observation boundary** and the **future host direction**. Both must be consistent with ADR 0006. A planned API or future deployment is not evidence that a capability exists.

## 2. Agreed architectural invariants

1. **One SDK domain authority.** Domain workflow lifecycle, registered command behaviors, transition guards, typed reducers, replay, and application operations belong to the SDK. The UI does not implement an alternative state machine.
2. **Durable source of truth.** The committed append-only **outcome-only** journal is authoritative. Commands reside in the submission inbox; accepted commands are not committed domain outcomes. Persisted projections must be checked against journal evidence.
3. **Immutable composite state.** `RudraState` contains `WorkflowsState`; the current unfinished workflow is a `WorkflowSnapshot` with immutable identity, positive workflow-local version, mandatory lifecycle and registered typed slice bindings.
4. **Verified absence.** `WorkflowsState.current_workflow == null` means successful restoration proved no unfinished workflow exists. Loading, unavailable storage, missing evidence and integrity failure are not interchangeable with absence.
5. **Distinct submission state.** Durable acceptance, pending processing, completion, rejection and quarantine are separate from committed workflow lifecycle state. Do not display accepted Start as established Active.
6. **Pure transitions.** `WorkflowStateMachine` applies registered outcome transitions and reducers without I/O or subscriber management. It may produce a proposal later rejected by persistence.
7. **Atomic commitment.** `WorkflowCommitter` revalidates trusted owner, identity, expected version, reservation and journal inside a transaction. Only a successful commit establishes an authoritative domain change.
8. **Committed-state observation through SDK ports.** The SDK defines a workflow commit **publisher** with `publish()` and a matching **subscriber** with `watch()`. A persistence adapter calls `publish()` only after its authoritative transaction succeeds; SDK observation consumes `watch()`, restores validated state using the existing state machine and exposes immutable `RudraState` to frontends. Notifications are change hints, never authority. The immediate 6C scope and deferred cross-process delivery are distinguished in §8 and the companion design.
9. **No implicit writes.** Explore, navigate, restore, subscribe, render and Quit do not submit/process commands, create an absent persistence database or modify the target filesystem. Explicit authorized operations are separate.
10. **Trusted host boundary.** OS-user identity, database location, permissions and adapter creation are provided by trusted composition, not untrusted frontend parameters. A future network-facing host must authenticate and authorize clients.
11. **Frontend view state, not frontend domain state.** Small, focused view models consume SDK models plus local interaction state; stateless widgets render them. UI visibility is not authorization.
12. **Explicit extensibility.** Feature-owned actions, SDK modules, typed transitions and reducers are registered at appropriate composition boundaries. Do not introduce reflection, an unchecked dynamic state bag or a universal service registry.
13. **Safety before convenience.** One unfinished workflow per trusted OS user, idempotency, expected identity/version guards, fail-closed restoration, append-only audit, quarantine and the dedicated destructive-operation gatekeeper remain intact.
14. **Proportionate abstraction.** Avoid unnecessary frameworks, compatibility shims during pre-release refactors and blanket bans on legitimate UI edits. Verify each coherent slice before proceeding.

## 3. State and responsibility model

### 3.1 Three different types of state

| State | Authority | Contents | Consumer rule |
|---|---|---|---|
| **Domain/application** | SDK | `RudraState`, `WorkflowsState`, immutable `WorkflowSnapshot`, lifecycle and typed slices | Frontends display it; they do not project domain events themselves |
| **Submission/processing** | SDK and durable persistence | Receipt, pending/completed/rejected/quarantined resolution and causal outcome information | Never equate command acceptance with committed state |
| **Presentation** | Frontend | Selection, navigation, viewport, status text, focused view models, temporary UI errors | May reference SDK state; never independently authorize transitions |

Readiness, loading, transient disconnection and integrity failures belong to the observation/application boundary, not to invented workflow domain lifecycle values.

### 3.2 Implemented SDK composite state (6B)

The current domain contracts are **implemented**, not hypothetical:

- `packages/sdk/lib/src/state/rudra_state.dart` — `RudraState(workflows: ...)`.
- `packages/sdk/lib/src/workflow/states/workflows_state.dart` — `WorkflowsState(current_workflow: ...)`; nullable selector for a verified unfinished workflow.
- `packages/sdk/lib/src/workflow/states/workflow_snapshot.dart` — immutable identity, lifecycle, version and typed slice bindings; terminal snapshots cannot be current unfinished workflow state.
- `packages/sdk/lib/src/workflow/states/workflow_slice.dart` — `WorkflowSlice`, `WorkflowSliceKey<T>`, `WorkflowSliceBinding<T>`.
- `packages/sdk/lib/src/workflow/transitions/workflow_slice_reducer.dart` — registered typed, feature-owned reducers. Each reducer sees the **same previous aggregate** and replaces/removes only its own slice.
- `packages/sdk/lib/src/workflow/transitions/workflow_outcome_transition.dart` — registered lifecycle outcome transitions.
- `packages/sdk/lib/src/workflow/workflow_runtime.dart` and module registry — explicit immutable configuration of behaviors, lifecycles, outcome transitions, codecs and reducers.
- `packages/sdk/lib/src/workflow/workflow_state_machine.dart` — pure `transition()` and deterministic outcome-only `replay()`.
- `packages/sdk/lib/src/workflow/reading/workflow_state_reader.dart` — validated restoration of owner-scoped committed histories and unfinished projection.

Workflow-local `snapshot.version` is useful for ordering outcomes **within a single workflow**. It does not order replacement across workflow A → no unfinished workflow → workflow B; observation design must not misuse it as a global revision.

Do not introduce `NullWorkflowSnapshot`, a parallel state hierarchy, lifecycle data inside every feature slice, or a second frontend state machine. New inspection, planning, execution and recovery slices are added only when their domain features exist.

### 3.3 Implemented operation, commitment and observation paths (6C.1–6C.2)

```text
Explicit frontend action
  → WorkflowApplication / EventManager
  → durable accepted command + receipt
  → WorkflowProcessor
  → registered command behavior proposes outcome(s)
  → WorkflowStateMachine applies transition(s) and reducers
  → WorkflowCommitter.commit(plan)
  → atomic journal + ownership projection + submission resolution
  → WorkflowProcessingCommitted(plan), only after successful commit
```

`WorkflowProcessingCommitted` is an **immediate processing result**, not a subscription event. In 6C.2, `PublishingWorkflowCommitter` wraps SQLite commitment and calls the SDK-defined `WorkflowCommitPublisher.publish()` after a successful transaction. A shared local channel supplies matching `WorkflowCommitSubscriber.watch()` change hints to the SDK observer. The observer reconstructs immutable `RudraState` using `WorkflowStateReader` and the existing state machine; neither the hint nor `plan.resulting_state` is treated as authoritative.

`WorkflowApplication` exposes `read_state()`, `observe_state()`, `submit_command()`, `status_for()`, `process_next()`, `start()` and `stop()`. `observe_state()` emits an initial verified snapshot followed by reconciled local changes. `start()` and `stop()` coordinate explicit command submission and confirmed processing; a future host may eventually take over independent processing, but is not part of 6C.

### 3.4 Reactive snapshots versus informational events

**Architectural target from ADR 0006 §7:** An authoritative current snapshot followed by committed changes without an unreported gap; ordering appropriate to the observation scope; recovery after disconnect/restart; eventual visibility of other processes' commits; explicit unavailable/failure semantics; and reconciliation against durable evidence. Direct domain-event subscriptions are optional for audit, diagnostics and integrations, not UI state reconstruction.

**Agreed staged delivery:** 6C.2 implements **in-process, persistence-backed, committed-state observation** and local reconciliation. 6C.3 integrates it into Explorer. Live cross-process fan-out, multi-client reconnection and remote subscriptions are **not claimed complete in 6C**; they are planned for a later trusted-host milestone. Fresh restoration from the existing journal remains authoritative across processes today. This is a scoped intermediate deliverable, **not a revision or repeal of ADR 0006**. See the companion document §§3–7.

### 3.5 Observation ownership and the agreed `publish()` / `watch()` ports

| Boundary | Agreed responsibility |
|---|---|
| `WorkflowStateMachine` | Pure outcome transitions, typed reducers and deterministic replay, without I/O or subscriptions; its implementation may evolve where justified |
| `WorkflowProcessor` | Proposes and validates outcomes; returns durable processing results, not a broadcast |
| `WorkflowCommitter` | Revalidates against persistence and atomically commits journal, reservation and submission outcome |
| **SDK-defined `WorkflowCommitPublisher`** | Persistence-facing port with **`publish()`**; the adapter invokes it **after** successful commitment, once per coherent transaction |
| **SDK-defined `WorkflowCommitSubscriber`** | Observation-facing port with **`watch()`**; SDK application observation consumes committed-change hints from the same shared notification context |
| **Trusted composition / concrete notification implementation** | Wires the publisher and subscriber sides to one local channel for the configured persistence/application lifetime; adapters may choose the underlying mechanism |
| `WorkflowStateReader` | Restores and validates durable evidence through `WorkflowStateMachine.replay()` |
| **SDK observation coordinator / `WorkflowApplication`** | Registers local consumers, reconciles changes, and exposes immutable validated `RudraState` snapshots |
| Frontends | Consume state and render; own UI lifetime and errors; never replay domain histories or authorize transitions |

The **implemented** contract responsibilities and method names are complementary, not two independent notification services: the same composition-owned implementation may satisfy both interfaces. Neither the publisher nor persistence carries `WorkflowSnapshot` or `RudraState` as authority. After a signal, the SDK obtains a validated application snapshot using its existing reader and state machine. In particular, committed Stop yields a terminal `WorkflowSnapshot` but `WorkflowsState.current_workflow == null`.

The implemented `PublishingWorkflowCommitter` publishes **one change hint per successful `commit(plan)`** after transaction completion; existing Start and Stop commits each contain one outcome. SDK observation always reads a **coherent post-commit application snapshot**, rather than publishing intermediate proposals. Publication exceptions are logged without changing the result of an already successful transaction, but a failed hint may leave a live subscriber stale until another notification or fresh restoration. Trusted `os_user_id` scope is established by composition, never by an untrusted frontend.

**Implemented signatures:** `void publish({required String os_user_id})`, `Stream<void> watch({required String os_user_id})` and `Stream<RudraState> observe_state()`. `WorkflowStateObserver` registers the listener before initial restoration, discards reads overtaken by subsequent local notifications, serializes reconciliation, coalesces rapid changes and reports restoration/source errors. Each subscription owns its lifecycle; the SQLite persistence context owns the shared notification channel. Missing SQLite storage is handled without creating a database on read. **Not implemented:** durable notification cursors, automatic catch-up after a lost hint, cross-process push, IPC or a background host. See the companion document §4.

## 4. Frontend composition and interaction

### 4.1 Portable SDK and independent frontends

```text
CLI / Explorer          Flutter desktop           future mobile / web
        \                     |                          /
           application-facing SDK contracts / trusted client
                                 |
                        SDK application + state
                         /                \
              persistence contracts     target contracts
                        |                    |
                    SQLite / Drift       macOS / others
```

In the current embedded mode, CLI composition supplies the SDK runtime, trusted OS user and SQLite adapter directly. A future host will be another SDK-consuming application in the Rudra monorepo, and connected frontends will consume equivalent application-facing contracts through transport adapters. The SDK must remain free of platform service-launch dependencies.

### 4.2 ViewModel is frontend view state

- No automatic `ViewState → ViewModel → Presenter → Widget` relay chain. The view model **is** the widget-facing view state.
- Prefer small focused Header, Directory, Footer and Actions view models, referencing SDK `WorkflowsState` or `WorkflowSnapshot` where useful.
- `show_start`/`show_stop` may be straightforward presentation getters derived from validated current-workflow presence; they are not SDK permission checks. Commit-time validation remains authoritative even when the UI becomes stale.
- Pass cohesive typed objects instead of expanding lists of `navigation_hints`, `status_line`, `can_start`, `workflow_id` primitives.
- No `record_started`, `record_stopped` or `record_paused` methods on frontend state. No mirrored frontend workflow lifecycle machine.
- Error, loading and unavailable views must not display uncertain domain state as proven `Workflow: NONE`.

### 4.3 Stateless compositional widgets

```text
ExplorerScreen
  ├── ExplorerHeader(HeaderViewModel)
  ├── ExplorerDirectory(DirectoryViewModel)
  └── ExplorerFooter(FooterViewModel)
       └── WorkflowActions(ActionsViewModel), if appropriate
```

Widgets render their view models; they do not fetch persistence, trigger commands or mutate domain state. Layout parents own viewport constraints; preserve terminal safety rows, sanitization, truncation and restoration. A genuine new UI action may change its own view model/widget/tests. Do not invent a generic UI action-descriptor registry just to avoid that legitimate change.

A presenter is optional when it adds substantial reusable transformation. Keep shared directory formatting in its suitable owner; avoid a giant substitute `ExplorerViewModel` or arbitrary constructor bundle.

### 4.4 Controller, physical input, actions and composition

1. `TerminalInput` decodes **physical keys** and escape sequences, not Start/Stop/Pause semantic actions.
2. Navigation controls selection, location and read-only target exploration; it does not implement workflow policy.
3. `ExplorerActionRegistry` dispatches feature-owned actions registered explicitly at product composition. Validate IDs, conflicting/reserved shortcuts and deterministic registration.
4. Workflow Start/Stop actions call public SDK application operations, not state-machine transitions.
5. `ExplorerRunner` owns terminal lifecycle, sequential input/action coordination and rendering; it must not accumulate workflow-specific branches.
6. SDK observation (6C.3) replaces action-only refresh with validated state consumption, without rebuilding the presentation architecture.

Preserve `S` Start, `X` Stop, `Q` Quit, arrows, Enter and Backspace. Visibility is a UI choice; executable authorization is checked by SDK processing and persistence.

### 4.5 CLI command contributions (6E)

Continue using `RudraCliModule` and `package:args`. Start/Stop and future Pause become independently contributed nested `rudra workflow` commands, registered through explicit composition. Do not introduce another CLI framework or a central group constructor with one new argument per feature.

## 5. Audit findings and implemented progress

### 5.1 Original audit findings (20 November)

| Finding | Original coupling | Intended / current ownership |
|---|---|---|
| A — Input | Workflow-specific `S`/`X` key enums | Physical key decoding only — addressed in 6A |
| B — Runner | Workflow-specific branches/callbacks | Generic action dispatch — addressed in 6A |
| C — Presentation | Flags and workflow hints assembled by large presenter | Focused ViewModels and widgets — addressed in 6A |
| D — Nested CLI | Hardcoded Start/Stop command set | Independent feature contributions — 6E pending |
| E — Operations | Reusable Start/Stop coordination in CLI composition | `WorkflowApplication` — addressed in 6C.1 |
| F — Persistence extensibility | Start/Stop-specific processing and commit categories | Generic safe continuation — 6D pending |
| G — Tests | Feature-specific shortcuts in generic tests | Feature-owned tests + synthetic contracts — addressed in 6A |
| H — Frontend lifecycle | `WorkflowExplorerState.record_*` and `can_*` | SDK authority only — addressed in 6A |
| I — Domain aggregate | Concrete lifecycle subclasses with expanding fields | Immutable composite snapshot + typed slices — addressed in 6B |
| J — Presentation layering | Redundant presenter/model/primitive projection | Small compositional state and justified presenters — addressed in 6A |

Original source review baseline: [Runner](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/features/explorer/application/explorer_runner.dart), [SDK processor](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/packages/sdk/lib/src/workflow/processing/workflow_processor.dart), [Drift committer](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/packages/persistence/sqlite/lib/src/features/workflow/history/drift_workflow_committer.dart).

### 5.2 Implementation ledger as of `d326fbd`

| Slice | Status | Evidence / qualification |
|---|---|---|
| **6A — Explorer realignment** | **Implemented** | `62d7c9551` marked 6A complete; physical input, action registry, compositional UI and isolated tests |
| **6B — Composite SDK state** | **Implemented** | `e8338e130` through `be5275e1f`; snapshot, typed slices/reducers, immutable `RudraState`, outcome-only replay and tests |
| **6C.1 — Portable operations** | **Implemented; developer-reported verification green** | `c0cd06543`, docs fixes `dcf86f8e2`; `WorkflowApplication`, SQLite durable status, CLI delegation |
| **6C.2 — SDK `publish()` / `watch()` commit observation** | **Implemented; developer-reported full-suite green** | `0439b29`–`d326fbd`; owner-scoped SDK ports, post-commit SQLite publisher, `observe_state()`, missing-storage guard, local race/error/cancellation and integration tests |
| **6C.3 — Explorer observation integration** | **Not implemented** | Explorer still performs read-only refresh around actions |
| **6D — Safe generic continuation/persistence** | **Pending** | Current SQLite committer still dispatches concrete Start/Stop categories |
| **6E — Nested CLI feature contributions** | **Pending** | Architectural target accepted; not marked implemented |
| **6F — Final audit and documentation** | **Pending** | Comprehensive verification and hypothetical Pause change-impact review |

6C.2 local observation is implemented, but Explorer adoption and cross-process delivery are not. Historical progress notes in the original epic were pinned to `434a925` and are superseded by the implementation ledger above. The developer reported the full test suite green on 23 November 2026; this document records that report rather than claiming independent test execution.

## 6. Persistence safety and future continuation

The committed outcome-only journal is authoritative. A reader validates projection, history and owner; the committer must recheck the trusted state inside a transaction. A frontend snapshot or a processor's earlier proposal cannot independently authorize commitment.

| Commit category | Intended outcome | Mandatory atomic checks |
|---|---|---|
| Establishment | Establish one unfinished workflow | Trusted owner, unique workflow/owner reservation, journal, projection, submission resolution |
| Continuation | Advance existing nonterminal phase, e.g. Pause | Expected owner/workflow/version, validated replay, retained reservation, journal, projection, resolution |
| Terminal completion | End/terminate existing workflow | Expected owner/workflow/version, validated terminal transition, journal, ownership release, resolution |

6D will generalize processor/inbox/committer assumptions while preserving failure classification, compare-and-set semantics, idempotency and fail-closed behavior. It must validate **the full proposed immutable snapshot including feature-owned slices**, not merely lifecycle, version and identity, before claiming generic continuation safety. Avoid introducing an unrestricted event writer or conflating lifecycle changes with destructive target operations.

Recovery-required obligations, candidate reservation, quarantine, approval, revalidation, execution gatekeeper and durable outbox remain under their own ADR 0006 safety boundaries. Generic reactive listeners do not authorize file cleanup.

## 7. Testing and verification architecture

### 7.1 Layers

1. **Component unit:** physical input, stateless widget, small view model, navigation controller, deterministic reducer/transition.
2. **Contract/registration:** synthetic feature contributions, duplicate IDs/types/outcomes, immutability, deterministic ordering, no side effects during registration.
3. **Feature operation and adapter:** Start/Stop/Pause frontend adapters and commands tested against public contracts; changes should add feature-owned tests rather than modifying generic decoders or runners.
4. **SDK + real persistence integration:** outcome journal, trusted owner, expected ID/version, atomic rollback, crash/retry, rejection/quarantine, storage integrity and no implicit writes.
5. **Representative frontend end-to-end:** entrypoint + fake terminal/native terminal where practical; verify cleanup on exit and error.

Representative (not mandatory) test ownership:

```text
apps/cli/test/
  features/
    explorer/
      terminal/terminal_input_test.dart
      application/explorer_runner_test.dart
      presentation/*_test.dart
    workflow/
      explorer/start_action_test.dart
      explorer/stop_action_test.dart
      cli/start_command_test.dart
      cli/stop_command_test.dart
  integration/
    workflow_cli_lifecycle_test.dart
    explorer_workflow_lifecycle_test.dart
```

### 7.2 6C test ownership and scope

6C.2 test coverage includes initial validated state, registration/read overlap, rapid and replacement-workflow signals, multiple local observers, owner isolation, post-commit Start/Stop delivery, acceptance versus commitment, failure of the publisher, cancellation during restoration, stream shutdown, invalid history and absent-storage read-only behavior. Existing real Drift tests cover transaction rollback; separate publishing-decorator tests prove that a failing delegate does not notify. **A single combined real-Drift rollback-and-notification test and generalized multi-outcome persistence coverage are not separately established by these tests.** SDK observer tests use synthetic notification/read boundaries; SQLite integration tests use real persistence. The developer reported `./rudra verify all` green for the final 6C.2 code.

6C.3 must verify: initial absent/active Explorer presentation, locally committed Start/Stop, stale UI action handling, safe rendering/input coordination, subscription cancellation and terminal restoration. Do not count cross-process live behavior as passing on the strength of in-process tests.

**Deferred host tests:** independent process/client connections, reconnect after host crash, multi-client ordering, cross-process live fan-out, host authorization and remote transport. Those remain required for the eventual ADR 0006 capability, but are **not 6C exit criteria**.

Do not weaken old safety/regression tests or enlarge a monolithic test fixture with every feature. Check both the test results and the list of touched files.

## 8. Implementation sequence and completion gates

### 6A — Explorer architecture — IMPLEMENTED

Physical input decoupled from semantics; action registry and feature-owned actions; removal of frontend workflow lifecycle state; compositional view models/widgets; generic and feature tests isolated; terminal behavior retained. Implemented at least through `62d7c9551`. Do not repeat this refactor in 6C.

### 6B — Composite SDK state — IMPLEMENTED

Immutable `RudraState`/`WorkflowsState`/`WorkflowSnapshot`; typed slices and reducers; registered lifecycle outcome transitions; deterministic outcome-only state machine and restoration. Completed through `be5275e1f`. Do not rebuild it for observation.

### 6C.1 — Portable SDK application operations — IMPLEMENTED

SDK read/current, confirmed Start/Stop, durable acceptance/processing status and CLI delegation. Implemented in `c0cd06543`; documentation cleanup in `dcf86f8e2`. Tests reported green by developer; retain latest-commit verification discipline.

### 6C.2 — SDK commit publisher/subscriber and application-state observation — IMPLEMENTED; DEVELOPER-VERIFIED

**Responsibility:** Provide validated, immutable SDK application state to local observers, driven by committed persistence changes rather than command acceptance or proposed transitions.

**Implemented components:**

- SDK-defined `WorkflowCommitPublisher.publish()` and `WorkflowCommitSubscriber.watch()` contracts, plus the owner-scoped `LocalWorkflowCommitChannel`.
- SQLite `PublishingWorkflowCommitter` decorator, publishing a hint after each successful atomic `commit(plan)` while logging publication errors without misreporting transaction success.
- `WorkflowApplication.observe_state()` and `WorkflowStateObserver`, reconstructing state through existing `read_state()` / `WorkflowStateReader` / `WorkflowStateMachine.replay()`.
- Watch-before-read startup, serialized reconciliation of overlapping signals, coalescing, independent local subscribers, cancellation and stream-error termination.
- Lazy SQLite connection and `NonInitializingWorkflowHistoryStore`, preserving verified absence without implicit creation of missing persistence and detecting disappearance after persistence has been seen.

**Evidence:** Implementation commits `0439b29` (ports), `d0f7009` (SQLite wiring), `6f28b33` (SDK observer), `eaa3881` (publication safety/integration), `529a1b0` (missing-storage guard), and `d326fbd` (observer lifecycle tests). SDK contract/unit tests and real SQLite integration tests cover local Start → Active → Stop → verified absence, replacement/coalescing, owner isolation, publisher failures, restoration errors and cancellation. The developer reported the final full workspace suite green on 23 November 2026; this documentation update did not execute it independently.

**Scope and residual limitations:** Notification hints are local to one shared in-process persistence context; another process or independently created context cannot observe those hints. There is no durable cursor, guaranteed recovery from a lost publication, cross-process live sync, host or transport. Existing Start/Stop commit one outcome each; generalized multi-outcome commitment belongs to 6D. A notification failure leaves the durable journal authoritative but may require explicit re-restoration for a stale live observer.

**Completion:** 6C.2 implemented and developer-verified. Explorer integration remains 6C.3.

### 6C.3 — Explorer observation adoption — PLANNED

Wire Explorer to the 6C.2 subscription instead of relying solely on action-triggered refresh. Keep the same compositional view models, action registry, input decoding and terminal ownership. Manage the subscription across startup, user actions, rendering, failure and Quit. Do not assert that separate terminal processes stay instantly synchronized before the host milestone.

**Done when:** Explorer reacts to supported committed SDK state changes while open, retains existing interaction and safety behavior, and its feature/integration tests pass.

### 6C closure — SCOPED, NOT FULL ADR 0006 DELIVERY

6C closes when 6C.1–6C.3 and their local tests pass, documentation accurately states supported observation scope, and another **embedded** frontend can consume the same SDK operations and local observation without importing `rudra_cli` or implementing workflow rules. **Cross-process live fan-out, multi-process reconnect and remote subscriptions remain open product requirements under ADR 0006 §7** and require a later trusted-host milestone. Do not mark those tests or requirements complete by implication.

### 6D — End-to-end safe persistence extensibility — PENDING

Remove unjustified hardcoded initial/active assumptions, support valid nonterminal continuation through inbox, reader, processor and committer, distinguish establishment/continuation/terminal categories, validate complete slice state, and test synthetic Pause-like continuation through real Drift including failures and concurrency. Do not weaken transaction guards.

**Done when:** A registered continuation can be processed, committed and restored without a concrete Start/Stop dispatcher branch or bypass of safety invariants.

### 6E — Independently contributed nested CLI commands — PENDING

Use `RudraCliModule` and `package:args`; isolate each nested workflow command and tests; ensure new Pause does not expand central constructors or unrelated test fixtures; preserve CLI behavior without unapproved changes.

**Done when:** An additional command primarily adds its feature, tests and explicit registration.

### 6F — Final reconciliation and change-impact review — PENDING

Remove stale compatibility/dead presentation layers, reconcile `docs/ARCHITECTURE.md`, ADRs and developer conventions with actual implementation, verify the full suite and inspect changed-file locality. Walk hypothetical Pause through SDK, persistence, CLI and UI. Do not allow documenting the future host to become implementing it.

**Done when:** Verified repository state matches documentation and the Pause litmus test succeeds without weakening safety.

## 9. Future trusted host — direction only, outside Epic 6

The future host is **another SDK-consuming application in the Rudra monorepo** (conceptually `apps/host`), not a separate SDK, alternate state machine or separate repository. It will run a long-lived trusted application runtime, coordinate processing, authenticate clients, and forward validated SDK snapshots and application operations through transport adapters. It reuses SDK `publish()` / `watch()` notification wiring and SDK application-state observation rather than introducing a host-specific workflow state machine. A future MySQL or other persistence adapter consumes the same SDK ports; any external-writer detection or network delivery mechanism remains adapter/host-specific.

Two Explorer terminal processes, a Flutter desktop frontend, web clients and eventually authenticated mobile clients should observe the same host-owned authoritative state. The host will preserve trust and safety; a remote subscription never implies filesystem execution authority.

- **Within process:** Dart streams; no socket needed.
- **Future local IPC:** Candidate Unix domain socket or suitable native IPC, chosen during the host milestone.
- **Future remote access:** Authenticated/encrypted, explicitly scoped host endpoint; no automatic direct public exposure.
- **Host lifecycle:** Platform-specific deployment/registration, likely a per-user macOS `launchd` agent with on-demand activation where feasible. The SDK does not spawn/check/enable a daemon; frontends connect through portable client contracts.
- **Implementation language:** A headless pure-Dart host is a natural candidate; Flutter remains useful for desktop/mobile UI and native platform integration.
- **Open questions:** Protocol, authentication/pairing, reconnect cursors, host crash recovery, process ownership and single-writer/out-of-band commits, idle policy, platform registration and network exposure.

These are **future architectural directions**, not existing code or settled deployment protocol. The host should be planned as its own epic when the current observation contracts are stable. See the companion document for details and guarantees preserved from ADR 0006.

## 10. Safety and regression checklist

- [ ] No workflow command is implicitly submitted/processed by Explorer launch, read, subscribe, render or Quit.
- [ ] No database is created by inspecting a previously uninitialized installation.
- [ ] Verified absence, loading/unavailable and corruption remain distinguishable.
- [ ] Command acceptance cannot be displayed as committed workflow success.
- [ ] Event journal remains append-only, outcome-only, consistently replayable and checked against projections.
- [ ] Trusted owner and one-unfinished-workflow reservation remain enforced transactionally.
- [ ] Stale expected workflow identity/version cannot change a replacement workflow.
- [ ] Journal, ownership projection and durable submission completion remain atomic.
- [ ] `publish()` is invoked only after a successful atomic commit; `watch()` is wired to the same scoped notification context. Failed/rolled-back transactions never notify success; subscriber failures never undo or misreport committed success.
- [ ] Terminal input/modes/screen restore on normal exit and catchable errors, without claiming SIGKILL/power-loss guarantees.
- [ ] Cleanup approval, reservation, gatekeeper, outbox, quarantine and recovery invariants from ADR 0006 remain separate from observation.
- [ ] Feature additions modify intended feature/UI surfaces and tests, not unrelated generic infrastructure.
- [ ] Cross-process live observation is not claimed complete before the future host supports and verifies it.

This is a **verification checklist**, not a claim that all items are presently tested or complete.

## 11. Alternatives and decisions retained

- **Frontend `record_started` / `record_stopped` / `can_*` lifecycle policy:** rejected; SDK remains authoritative.
- **Second frontend workflow state machine or event replay:** rejected; clients consume authoritative snapshots.
- **`NullWorkflowSnapshot`:** rejected; no fabricated workflow identity.
- **Separate default ViewState → ViewModel → Presenter layers:** rejected; meaningful presentation transformations remain optional.
- **Universal UI action-descriptor registry or universal plugin/service locator:** rejected; explicit, typed, layer-specific contribution only.
- **Giant concrete lifecycle-state subclass tree or `Map<String, dynamic>` slices:** rejected; immutable typed composite state is implemented.
- **Publishing from a pure transition:** rejected; a proposed outcome is not a committed outcome.
- **Directly publishing `WorkflowProcessingPlan.resulting_state` as authoritative:** deferred/rejected for 6C.2; a transaction may fail and current persistence verification does not establish equality of every feature slice. Restore through the SDK reader instead.
- **A SQLite-owned `WorkflowChangeSource` as the portable SDK abstraction:** rejected in favor of SDK-owned, paired `WorkflowCommitPublisher.publish()` / `WorkflowCommitSubscriber.watch()` ports consumed by interchangeable adapters and SDK observation.
- **Treating notification as source of truth:** rejected; validated persisted journal remains authoritative.
- **SDK-owned polling/OS daemon spawning:** rejected as an SDK responsibility; adapters own signals and host lifecycle remains platform-specific.
- **Implementing an entire host service to finish 6C:** deferred deliberately; multi-client live delivery remains a future ADR requirement.

## 12. Verification and collaboration procedure

After each coherent, independently reviewed slice:

```text
./rudra format
./rudra verify cli
./rudra verify all
git diff --check
git status --short
```

Inspect failing output and the list of changed files; do not assert tests were executed by documentation generation. Make a new commit per completed slice for a clear review baseline.

**Engineering workflow:**

1. Inspect newest pushed `main`, the active slice and this companion document before proposing code.
2. Discuss responsibility, safety consequences and exact interfaces; agree on a cohesive implementation slice, **not a fixed number of files**.
3. Collaborate manually by default: provide paths, exact BEFORE and AFTER replacements, complete code, tests and relevant documentation; do not generate apply scripts/ZIPs unless requested.
4. Keep DartDocs proportionate and complete for public contracts, constructors, parameters, returns, failures and meaningful side effects. Preserve working tests; add isolated feature/layer tests, not unrelated scenario cases.
5. Verify each slice, review the pushed commit and update status with observed evidence. Avoid accidental architectural changes while addressing minor errors.

### Next-session baseline

> Continue Rudra Epic 6 at **6C.3 — Explorer observation adoption**. Read this epic and the 6C companion, then inspect latest pushed `main` (6C.2 baseline `d326fbd`). 6A, 6B, 6C.1 and 6C.2 are implemented; the developer reported full verification green. `WorkflowApplication.observe_state()` already emits validated `RudraState` from a shared in-process SQLite persistence context using the SDK-owned `publish()` / `watch()` ports. Reuse this API in Explorer, preserving feature-owned actions, compositional view models, terminal lifecycle and safety. The current one-operation CLI persistence lifetime is not suitable for a long-running subscription; design ownership and disposal deliberately. Do not add an independent frontend domain state machine, automatic command processing or cross-process IPC. State-machine changes are acceptable if architecturally justified, but pure transition/replay authority must remain in the SDK. Collaborate through explicit, documented, feature-coherent manual edits and isolated tests.

## 13. References and provenance

- [ADR 0004 — SDK-First Application Architecture](../decisions/0004-sdk-first-application-architecture.md)
- [ADR 0005 — CLI Feature-First Structure](../decisions/0005-cli-feature-first-structure.md)
- [ADR 0006 — Event-Sourced Workflow Architecture](../decisions/0006-event-sourced-workflow-architecture.md)
- [Epic 6C companion design](rudra-epic-6c-observability-and-trusted-host-direction.md)
- [SDK workflow registry](../../packages/sdk/lib/src/workflow/modules/workflow_module_registry.dart) and [runtime](../../packages/sdk/lib/src/workflow/workflow_runtime.dart)
- [SDK state](../../packages/sdk/lib/src/state/rudra_state.dart), [snapshot](../../packages/sdk/lib/src/workflow/states/workflow_snapshot.dart), [state machine](../../packages/sdk/lib/src/workflow/workflow_state_machine.dart)
- [WorkflowApplication](../../packages/sdk/lib/src/workflow/application/workflow_application.dart), [WorkflowProcessor](../../packages/sdk/lib/src/workflow/processing/workflow_processor.dart), [WorkflowCommitter](../../packages/sdk/lib/src/workflow/processing/workflow_committer.dart)
- [SQLite committer](../../packages/persistence/sqlite/lib/src/features/workflow/history/drift_workflow_committer.dart)
- [SDK commit channel](../../packages/sdk/lib/src/workflow/observation/workflow_commit_channel.dart), [state observer](../../packages/sdk/lib/src/workflow/observation/workflow_state_observer.dart)
- [SQLite publishing decorator](../../packages/persistence/sqlite/lib/src/features/workflow/observation/publishing_workflow_committer.dart), [non-initializing history store](../../packages/persistence/sqlite/lib/src/features/workflow/history/non_initializing_workflow_history_store.dart)
- [Explorer action registry](../../apps/cli/lib/src/features/explorer/application/explorer_action_registry.dart), [Explorer runner](../../apps/cli/lib/src/features/explorer/application/explorer_runner.dart)

**Provenance:** Original architecture agreed on 20 November 2026; observation/host staging agreed on 22 November 2026; SDK `publish()` / `watch()` direction confirmed on 23 November 2026 (Europe/Amsterdam). 6C.2 implementation inspected through `d326fbd`; the developer reported `./rudra verify all` green. This revision documents implementation and developer verification, not independent execution by the document author. ADR 0006's cross-process live observation, ordering and reconnect requirements remain for a future trusted host.
