# Rudra — Epic 6: Architectural Realignment

**Status:** Architecture agreed on 2026-11-20; implementation in progress, **not verified complete**.  
**Previous title:** Feature Isolation, Extensibility & Test Architecture  
**Canonical repository:** https://github.com/ibrahimab/rudra  
**Original review baseline:** `ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513` (2026-11-20).  
**Latest inspected implementation:** `edbc075d43e7a1de734d82ebeacf5b6b9f12917c` (2026-11-20; amended incomplete 6A implementation).  
**Preceding milestone:** Block 5C: Start → Active → Stop → Ended workflow lifecycle, SDK state machine, SQLite persistence, CLI and Explorer interactions.  
**Document purpose:** Architectural source of truth and implementation plan. Agreements below are **targets**, not assertions that all APIs exist. Inspect the latest `main` before working on a slice.

## 1. Objective and architectural acceptance test

Rudra must be an SDK-first, event-sourced, safety-first filesystem application whose domain behavior is implemented **once** and consumed by independent frontends. Its CLI, interactive Explorer, Flutter desktop, Android, web/trusted-host interfaces and third-party clients must not implement competing workflow rules.

Epic 6 realigns boundaries so that adding a capability primarily adds feature-owned behavior, contracts and tests. It must not routinely require edits to terminal key decoding, generic interaction dispatch, unrelated constructors, unrelated tests, or a centralized workflow-state class.

**Open/Closed applies at the appropriate boundary:** generic infrastructure should be closed to feature-specific changes, while a view or view model **may and should change** when the actual product UI changes. Adding a visible `P Pause` instruction is a legitimate reason to change the relevant Actions/Footer widget and its tests. A registry is not a goal in itself.

**Change-impact litmus test:** hypothetically introduce `workflow pause` (not an implementation request). Review the required changes through SDK domain behavior, state slices, persistence, application operations, state observation, CLI, Explorer and tests. The architecture passes if changes remain concentrated in the feature and intended UI surfaces, with explicit composition updates and necessary safety/schema changes. Passing an isolated registry test is insufficient.

## 2. Decisions and invariants

1. **One domain authority:** The SDK owns workflow lifecycle, domain rules, event processing, safe operations, state transitions and authoritative state reconstruction.
2. **Event sourcing:** The committed append-only event journal is the source of truth. A derived projection or observed snapshot must be reconstructable and validated against that journal.
3. **Composite SDK state:** Expose one coherent immutable, versioned workflow snapshot with a mandatory lifecycle component and typed, independently owned domain slices.
4. **Reactive SDK state:** Frontends obtain consistent current snapshots and observe committed updates. They do **not** need to replay domain events or rely on notification listeners for correctness.
5. **Distinct submission state:** Durable acceptance, processing, rejection, quarantine and committed completion are not interchangeable with domain lifecycle state.
6. **Behaviors own decisions:** Registered SDK behaviors, transition guards and state-machine validation own domain decisions. Do not reproduce Start/Stop/Pause lifecycle conditions in frontend state holders.
7. **No separate capability framework:** Do not introduce an additional capability/policy evaluation layer merely to determine which UI actions to display. Offer/hide decisions are presentation; execution remains authoritatively checked by SDK operations.
8. **UI state is view-model state:** No second frontend `ViewState` wrapper by default. Small view models hold the objects and local interaction information that their respective stateless widgets need.
9. **Compositional presentation:** Screens compose small widgets. Each widget consumes a focused view model and chooses how to render it. Presenters are optional, justified only by substantial transformation or composition.
10. **Cohesive object contracts:** Prefer passing typed objects over repeatedly flattening them into growing primitive parameter lists such as `navigation_hints`, `status_line`, `can_start`, `workflow_id`, etc.
11. **Explicit actions and composition:** Frontend action dispatch is registered where appropriate, independent of physical input decoding. SDK modules contribute behavior and typed state transitions through explicit registries. No reflection, service locator or universal plugin framework.
12. **Safety and process independence:** Trusted OS-user identity, one unfinished workflow per OS user, expected-workflow-ID/version guards, transactional persistence, fail-closed integrity errors, idempotency and terminal restoration must be preserved.
13. **No implicit writes:** Launch, navigation, inspection, rendering, restoration, subscription and Quit never implicitly submit workflow commands. Only explicit user/domain operations may do so.
14. **Pre-production freedom:** Internal breaking refactors are acceptable; do not build compatibility shims around contracts that are being intentionally replaced. A finished slice must still be verified.
15. **No abstraction for abstraction's sake:** A constructor, switch, or intentional UI edit is not automatically a design failure. Evaluate change locality and genuine responsibility.

## 3. Three kinds of state — different ownership, no duplication

| Kind | Owner | Contains | Never does |
|---|---|---|---|
| **Authoritative domain state** | SDK | Workflow identity, version, lifecycle, inspection/planning/execution/recovery slices | Depend on widgets, terminal, Flutter or display layout |
| **Operation/submission state** | SDK | Accepted/pending/processing/completed/rejected/quarantined status, correlated to a command | Claim an accepted command established a workflow |
| **Frontend view-model state** | Frontend | SDK snapshot references, navigation selection/history, scroll/viewport and other UI-specific data | Enforce workflow transitions, persist events, create a second domain state machine |

A view model may legitimately contain typed SDK models or expose simple computed getters over them. This is **reuse**, not boundary leakage. The boundary is crossed when the frontend reconstructs domain policy or mutates authoritative state on its own.

The UI may temporarily display an operation's progress, error or loading state; this must not be confused with the committed workflow's lifecycle. A workflow absent, a snapshot not yet loaded, and a restoration integrity failure are three **different** conditions.

### 3.1 SDK application state and workflow collection

The SDK should expose a non-null top-level application state (conceptually `RudraState`) with a non-null workflows slice (conceptually `WorkflowsState`). The workflows slice exposes a computed **current unfinished workflow** selector, which is nullable by design.

```dart
// Illustrative contracts; not current API signatures.
abstract interface class RudraState {
  WorkflowsState get workflows;
}

abstract interface class WorkflowsState {
  /// The only unfinished workflow for the trusted OS user, if any.
  WorkflowSnapshot? get current_workflow;
}
```

- **No `NullWorkflowSnapshot`:** A workflow snapshot implies a real workflow with identity, ownership, original target/root and a committed version. Absence must not be modeled as a fictitious authoritative workflow.
- **No mandatory eager history list:** Historical workflows remain separately queryable; the SDK does not have to load all histories to supply `current_workflow`.
- **No `active == unfinished` assumption:** Paused, awaiting recovery and other nonterminal phases still occupy the unfinished-workflow slot.
- **Never downgrade errors to absence:** Failed restoration, incomplete observation, unknown ownership or corrupted history cannot silently become `current_workflow == null`.
- Typed observation/loading/failure semantics are part of the observation contract, not fabricated domain snapshots.

### 3.2 Composite immutable workflow snapshot and slices

The SDK's long-term workflow representation is a **whole** workflow snapshot, not one giant concrete subclass for every lifecycle phase.

```dart
// Illustrative design, not an instruction to implement these names.
abstract interface class WorkflowSnapshot {
  WorkflowIdentity get identity;
  int get version;
  WorkflowLifecycle get lifecycle;

  T? slice<T extends WorkflowSlice>(WorkflowSliceKey<T> key);
}
```

- **Identity**, **version** and **lifecycle** are foundational mandatory data; lifecycle is not an optional plugin slice. Every established workflow has immutable owner, workflow ID, target and original inspection root.
- **Inspection**, **cleanup plan**, **execution**, **recovery** and future concerns may contribute typed domain slices. Do not pre-implement all these hypothetical slices; introduce them when the capability exists.
- Slice registration needs stable identity, type ownership and deterministic projection/transition contracts. Avoid unchecked string-to-`dynamic` maps and reflection.
- Slices do not each get to own a separate authoritative lifecycle. A committed event produces one coherent new aggregate snapshot and increments the workflow version according to the event/version contract.
- A future Pause changes lifecycle and any justified slice data while retaining the rest of the workflow. It must not require copying an expanding bag of domain fields into `WorkflowPausedState`.
- The current SDK `WorkflowState` / `WorkflowActiveState` hierarchy is a **minimal lifecycle implementation**, not proof that the composite state design has been implemented. Reconcile/migrate it deliberately, including replay and persistence.
- Domain slices are SDK types, not frontend `ViewModel`/widget packages.

### 3.3 Behaviors, transitions and reducers

Retain and evolve the existing SDK `WorkflowModuleRegistry` and `WorkflowRuntime` pattern. They currently register command behaviors, exact state/event transitions and serializers. Extend them where warranted for typed snapshot/slice projection rather than inventing a parallel state engine.

- **Command behavior:** Handles a typed command and proposes domain outcome events; it does not commit or present them.
- **Transition guard:** Determines whether the event is valid against the authoritative domain state and global invariants.
- **Transition / slice projection:** Deterministically constructs the next immutable snapshot and the affected typed slice(s); it performs no I/O.
- **State machine:** Resolves the registered behavior/transition, validates resulting identity/version/invariants and reconstructs history by replay.
- **Application processor:** Coordinates trusted identity, command processing, outcome validation and persistence contracts.
- **Persistence committer:** Rechecks trusted owner, expected workflow ID/version, unfinished reservation, journal and projection consistency inside an atomic transaction.

Do not permit independent reducers to overwrite arbitrary slices or bypass global lifecycle/authorization invariants. Feature-owned reductions must compose into one validated transition, with deterministic ordering or explicit conflict rejection. A transition failure must leave authoritative state unchanged.

**No `WorkflowExplorerState.record_started()` / `.record_stopped()` / `.record_paused()`.** These represent domain lifecycle assumptions leaking into the frontend. Similarly, no frontend `can_start`/`can_stop` guard should reproduce SDK processing rules. SDK behavior and execution validation are the source of truth.

### 3.4 Reactive snapshots versus informational events

The SDK observation interface must provide:

- A current coherent snapshot and subsequent committed changes **without an unreported gap** between the initial snapshot and updates.
- Versioning/ordering appropriate to its observation scope; a workflow-local version alone cannot order a transition between *different* current workflows.
- Recovery after disconnect/restart and visibility of other processes' commits.
- Explicit loading, unavailable and error conditions where applicable; malformed or inconsistent persisted state fails closed.
- A way to reconcile notifications with authoritative persistence rather than trusting delivery alone.

Domain-event subscriptions remain **optional and informational** (audit, diagnostics, activity, external integrations). Missed notifications must never make the frontend's view of current state permanently incorrect. Do not make clients replay domain histories to maintain their UI.

### 3.5 Commands and operation outcomes

```text
Explicit user action
  -> frontend action adapter
  -> public SDK application operation / durable command submission
  -> registered SDK behavior + state machine validation
  -> trusted transactional persistence
  -> committed SDK state observation
  -> view model and widget rebuild
```

The frontend never directly invokes a `WorkflowStartBehavior` or mutates a domain snapshot. It invokes a public SDK operation. That operation may expose a durable receipt immediately and a separate eventual result, or may offer a higher-level confirmed-completion method. These are distinct contracts. An accepted submission cannot be shown as a successful transition; rejection, quarantine and pending work remain visible as such.

Execution guards must be authoritative at processing/commit time even if a UI action was visible based on an earlier snapshot. For destructive work, only the execution gatekeeper and durable outbox may authorize and coordinate filesystem mutation.

## 4. Frontend interaction and presentation architecture

### 4.1 Portable SDK, independent frontends

```text
CLI / Explorer         Flutter Desktop / Android         Web / remote
       \                       |                           /
        \                      |           trusted host ---/
         \                     |                 /
           Public SDK application + observation contracts
                              |
               SDK workflow runtime and state
             /                              \
  Persistence contracts                Target contracts
         |                                    |
     SQLite / Drift                 macOS / other adapters
```

- The pure-Dart SDK contains no CLI/Flutter/SQLite/macOS presentation implementation dependencies.
- Trusted composition supplies identity, target access, persistence and concrete adapters. Remote/web frontends access trusted operations over a host service; a browser-provided ID does not grant OS-user authority.
- Shared derived **domain** information (e.g. validated plan totals) belongs in SDK selectors/domain models. Terminal text, padding, widget visibility and layout belong to each frontend.
- The current `RudraSdk` facade exposes filesystem inspection; reusable workflow operations and observation are still to be integrated into an appropriate SDK application API.

### 4.2 ViewModel **is** frontend view state

Do not default to `ViewState -> ViewModel -> Presenter -> Widget`. This is redundant when those layers merely forward the same objects.

- A **ViewModel is the state a widget consumes**: a narrow, typed, preferably immutable object containing the relevant SDK object references and local UI interaction data.
- The controller/observation coordinator handles user interactions and SDK updates and produces a new view model or causes rebuilding from a new immutable SDK snapshot. **Widgets do not mutate their view models.**
- View models can expose simple computed getters as conveniences (e.g. `show_start` from an SDK workflows slice's `current_workflow == null`). These are **UI visibility**, not domain permission or authoritative transition checks.
- Pass cohesive objects, not growing sets of primitive flags. For example, an Actions view model can receive a `WorkflowsState`, not separate `active_workflow`, `pending_submission`, `workflow_id`, `can_start`, `can_stop` and label parameters.
- A view model is not required to contain another `ExplorerModel` plus copies of every field. Reassess existing `ExplorerModel` and `ExplorerViewModel` responsibilities together rather than preserving both by renaming them.

Illustration:

```dart
final class WorkflowActionsViewModel {
  const WorkflowActionsViewModel(this.workflows);

  final WorkflowsState workflows;

  bool get show_start => workflows.current_workflow == null;
  bool get show_stop => workflows.current_workflow != null;
}
```

The example deliberately shows *presentation choices*, not authorization. An actual Stop action must still be validated by the SDK, and later UI design may distinguish Pause/Resume/Stop visibility. A snapshot may also be loading or erroneous; the observation owner must not present unknown state as established absence.

### 4.3 Stateless, compositional widgets

Follow the useful part of Flutter's `StatelessWidget` approach in the CLI terminal UI:

```text
ExplorerScreen
  +-- ExplorerHeader(HeaderViewModel)
  +-- ExplorerDirectory(DirectoryViewModel)
  +-- ExplorerFooter(FooterViewModel)
       +-- WorkflowActions(ActionsViewModel), as appropriate
```

- A widget receives its view model and chooses **what and how** to render; it does not fetch SDK data or run domain commands.
- A screen composes its children. Each child owns its rendering concerns and does not know the source or lifecycle of the underlying data.
- It is **appropriate to edit** an Actions widget or view model when adding a visible `P Pause` instruction, visibility condition or revised layout. OCP does not prohibit intentional view changes.
- Do not force action-hint rendering through a universal action-descriptor registry. The **interaction dispatch registry** and the **actual view design** have different reasons to change.
- A parent/layout boundary owns viewport constraints; children render within allocated constraints. Preserve terminal safety rows, truncation, sanitization and restoration behavior.
- Do not replace one massive `ExplorerViewModel` with another. Keep Header, Directory, Footer, Actions and Screen composed and independently testable.

### 4.4 Presenter: optional, not architectural middleware

There is **no mandatory Presenter stage**. A presenter may remain only where it performs a substantial, independently useful transformation—e.g. shared filesystem-entry display formatting or a complex viewport calculation that does not belong naturally in a small view model/widget/layout helper.

Do not preserve `ExplorerPresenter` solely for historic MVC symmetry, and do not move all of its logic into a giant `ExplorerViewModel`. Review its existing viewport/row transformation behavior method by method; preserve useful algorithms in the proper compositional component or narrowly scoped utility. Tests should follow the final owner.

### 4.5 Controller, action dispatch, and composition

Keep the boundaries distinct:

1. `TerminalInput` converts bytes/ANSI sequences to **physical keys**. It knows nothing about Start/Stop/Pause.
2. Explorer's navigation controller handles navigation, SDK read-only inspection and local selection/history state. It does not register workflow behavior itself.
3. Explicit **product composition** registers frontend action adapters, e.g. `WorkflowStartExplorerAction` and `WorkflowStopExplorerAction`.
4. A small **Explorer action contract** describes shortcut, identity and typed execution. Prefer feature-owned implementations over growing closures/construction-time dependencies inside generic infrastructure. Dispatch remains generic.
5. An action adapter invokes a **public SDK application operation**, not an SDK transition/behavior directly.
6. The SDK's updated state is then observed; the widget renders it. Never call frontend `record_started`/`record_stopped` to emulate domain transitions.

Generic action registration should validate shortcut conflicts, duplicate IDs, reserved input and deterministic registration without execution side effects. Core arrows, Enter, Backspace and Quit can remain built-in; do not create a universal UI-command framework. Actions execute sequentially where the interactive host contract requires it; failures propagate through guarded terminal restoration.

UI visibility and action execution are **different decisions**. A hidden shortcut may be declined by the generic dispatcher as a UX policy; a visible one is still not permission. Avoid embedding SDK lifecycle policy in dispatch availability checks. If the UI elects to offer Start even when it will be rejected, that is acceptable as long as the SDK rejects invalid requests correctly and renders the result honestly.

### 4.6 Nested workflow CLI commands

Continue to use `RudraCliModule` and `package:args`. Independently owned Start, Stop and later Pause commands are explicitly added under `rudra workflow` by composition. Do not make nested subcommands add more constructor arguments to a central workflow command group or introduce a second command framework.

## 5. Existing repository diagnosis and current progress

### 5.1 Strengths to retain (original audit at `ffa62313`)

- `WorkflowModuleRegistry` stages and validates module behaviors, transitions and serializers; `WorkflowRuntime.from_registry()` snapshots coherent registration.
- `RudraCliModule` already supports explicit top-level CLI registration and collision detection.
- SDK-backed Explorer navigation, terminal host lifecycle guards, shared directory observation formatting and rendering contracts are valuable investments.
- Tests already cover read-only Explorer, durable Start/Stop, ownership mismatch, terminal restoration and real persistence; do not replace these with shallow mocks.

### 5.2 Coupling findings (original audit)

| Finding | Originally observed issue | Required boundary |
|---|---|---|
| A — Input | `TerminalInput` mapped `S` and `X` to workflow-specific `ExplorerKey` values | Physical key decoding independent of semantic commands |
| B — Runner | `ExplorerRunner` accepted workflow-specific callbacks, state and branches | Generic dispatch; feature-owned action adapter |
| C — Presentation | Presenter assembled workflow hints and `can_start_workflow`/`can_stop_workflow` flags | Small widget/view-model composition; no duplicated domain policy |
| D — Commands | Workflow group hardcoded Start and Stop subcommands | Explicit independent nested contributions |
| E — Operations | `ProductWorkflowComposition` owned reusable Start/Stop submission and outcome logic | SDK-owned typed application operations, trusted host composition |
| F — End-to-end registration | Processor, reader, inbox and Drift committer assumed Initial/Active and Start/Stop | Support registered continuation through safe generic contracts |
| G — Tests | Workflow scenarios and S/X mappings lived in generic input/runner tests | Feature-owned unit tests, synthetic infrastructure tests |
| H — State separation (new) | `WorkflowExplorerState` mirrored active state with `record_started`, `record_stopped`, `can_start`, `can_stop` | SDK owns lifecycle; ViewModel owns view concerns only |
| I — Aggregate state (new) | Concrete `WorkflowActiveState` is a lifecycle variant, not a composable whole-workflow snapshot | Mandatory lifecycle + registered typed domain slices |
| J — Presenter/primitive explosion (new) | Repeated `navigation_hints`, statuses, booleans and callback parameters created extra data-shaping layers | Cohesive objects, small compositional widgets, optional presenter |

Source references for the original findings are retained at the pinned baseline: [runner](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/features/explorer/application/explorer_runner.dart), [terminal input](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/features/explorer/terminal/terminal_input.dart), [presenter](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/features/explorer/presentation/explorer_presenter.dart), [workflow composition](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/composition/product_workflow_composition.dart), [state reader](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/packages/sdk/lib/src/workflow/reading/workflow_state_reader.dart), [processor](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/packages/sdk/lib/src/workflow/processing/workflow_processor.dart), [committer](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/packages/persistence/sqlite/lib/src/features/workflow/history/drift_workflow_committer.dart).

### 5.3 Actual implementation status as of `edbc075`

**Partially implemented (production code only):** `TerminalKey`/physical decoding, a concrete callback-based `ExplorerActionRegistry`, generic runner dispatch, generic status/hints in presentation, Start/Stop Explorer action functions, `WorkflowExplorerState`, and composition registration in `rudra_cli.dart`. Initial cleanup was amended and pushed.

**Not yet complete or accepted as final design:** Interface-based feature-owned action classes; removal/replacement of duplicate frontend lifecycle state and policy; compositional ViewModel/widget refactor and reevaluation of Presenter; SDK composite snapshot, slices and observation; portable SDK workflow use cases; generic safe persistence continuation; nested CLI contributions; test restructuring. Existing tests were **not migrated** when inspected. No passing test run has been established for the amended commit.

Some existing code is expected to be replaced by this agreed design; do not freeze the current `WorkflowExplorerState` or callback-based registry merely to make tests green temporarily. No compatibility shims are required for pre-production experimental APIs.

## 6. Safe persistence and workflow processing

The journal remains authoritative, append-only and replayable. The persistence adapter must not trust the frontend's observed state, an in-memory capability hint or a previously read inbox record as transaction authority.

| Commit category | Intent | Mandatory atomic protections |
|---|---|---|
| **Establishment** | Create one unfinished workflow | Trusted identity, uniqueness reservation, journal + projection + submission outcome |
| **Continuation** | Advance existing nonterminal workflow (e.g. Pause) | Expected workflow ID/version, owner, validated replay, retained reservation, journal + projection + outcome |
| **Terminal completion** | End a workflow | Expected ID/version, valid terminal transition, journal + ownership release + outcome |

Generalize the current Start/Stop-specific inbox, processor, reader and Drift committer *without weakening* their identity/transaction checks and without introducing an unrestricted generic event writer.

Only committed events establish domain state. A failed validation or transaction leaves journal, projection and submission status consistent. Recovery-required obligations, quarantine, approval and filesystem mutation must remain under the dedicated safety contracts from ADR 0006; these are **not** handled by generic reactive listeners.

## 7. Tests and verification ownership

### 7.1 Test layers

1. **Component unit:** physical input, small widget/view-model, navigation controller, deterministic reducer/transition.
2. **Registration/contract:** synthetic feature contributions, ID/key collisions, duplicate transitions/serializers, immutability, ordering, no side effects at registration.
3. **Feature-owned adapter and operation:** Start/Stop/Pause action and command tests using fake public SDK operations; no SQLite required to prove key-to-operation mapping.
4. **Integration:** real SDK + Drift + composition and fake terminal as needed; durable journaling, replay, expected identity/version, trusted owner, concurrent ownership, no implicit writes.
5. **Representative end-to-end:** production CLI entrypoint and native terminal lifecycle where practical; small, deterministic and focused.

Representative organization (adapt to final feature ownership, not a blind move script):

```text
apps/cli/test/
  features/
    explorer/
      terminal/terminal_input_test.dart
      application/explorer_runner_test.dart
      presentation/explorer_header_test.dart
      presentation/explorer_directory_test.dart
      presentation/explorer_footer_test.dart
    workflow/
      explorer/start_action_test.dart
      explorer/stop_action_test.dart
      cli/start_command_test.dart
      cli/stop_command_test.dart
  integration/
    workflow_cli_lifecycle_test.dart
    explorer_workflow_lifecycle_test.dart
  support/
    fake_terminal_host.dart
    recording_renderer.dart
```

### 7.2 Rules

- Each stable generic contract gets generic tests using **synthetic** contributions, not production Workflow Start/Stop behavior.
- Add a Pause feature test in Pause's own area; do not insert Pause scenarios into terminal decoding/navigation tests.
- Widgets and small view models get local tests for actual presentation decisions; changing Actions/Footer UI appropriately updates **their own** tests.
- An SDK snapshot/reducer test does not need an actual terminal or SQLite database. An integration test asserting persistence safety must use real persistence, not a mock.
- Shared fakes model stable interfaces only; do not grow a monolithic `_Scenario` fixture with new fields for every feature.
- Preserve and extend existing tests for read-only Explorer, restoration corruption, trusted ownership, transactional failure, crash/retry, ID/version mismatches, terminal restoration and no premature outcome display.
- Test snapshot/observation reconnection, initial-subscribe race, ordering across successive workflows, loading/error versus absent, and cross-process state changes before claiming reactive correctness.
- Check both test results **and the list of modified files** to catch unrelated infrastructure churn.

## 8. Revised Epic 6 implementation sequence

These are **implementation boundaries**, not invitations to implement the entire future application at once. Review exact contracts and source before each slice; preserve safety at every migration. No code is claimed complete by this plan.

### 6A — Explorer physical input, action and compositional UI realignment (IN PROGRESS)

- Keep physical key decoding separate from feature dispatch; retain `S`, `X`, `Q`, arrows, Enter and Backspace semantics.
- Refine the partially implemented registry to a small interface-based action contract, with feature-owned implementations and explicit composition.
- Remove `WorkflowExplorerState` lifecycle mutation/policy (`record_started`, `record_stopped`, `can_start`, `can_stop`); do not build another frontend state machine.
- Converge navigation and UI state into narrow view-model ownership where appropriate. Pass cohesive SDK objects into small Header/Directory/Footer/Actions view models.
- Make widgets stateless and compositional. Preserve useful directory formatting and viewport algorithms; remove or narrow Presenter only after reviewing its genuine responsibilities.
- Keep UI visibility separate from SDK authorization. SDK state observation is a later SDK slice; use read-only confirmed SDK state/operation results in the meantime without inventing frontend transitions.
- Migrate generic and feature-owned tests; preserve terminal lifecycle and real persistence integration tests.
- **No SDK workflow/persistence schema changes in this slice.** Avoid short-lived compatibility shims.

**Done when:** The generic decoder/runner need no modifications to wire an additional workflow action; views are compositional; no frontend lifecycle state processor remains; tests and behavior are green.

### 6B — SDK composite state and typed slice contracts

- Design `WorkflowSnapshot` with mandatory identity/version/lifecycle, typed slice keys, immutable slice storage and module-owned deterministic transitions/reducers.
- Reconcile the current `WorkflowState`/concrete lifecycle subclasses and exact-type transition graph deliberately rather than adding a parallel state model.
- Define stable public selectors and a non-null SDK workflows state with nullable `current_workflow`.
- Preserve event journal replay/version invariants; ensure no NullWorkflowSnapshot, no eager all-history requirement and no corruption-as-absence fallback.
- Build pure domain and state-machine tests, including a synthetic new slice/phase.

**Done when:** New typed domain slices and a synthetic nonterminal lifecycle transition can extend the SDK without growing a central concrete state class.

### 6C — SDK portable operations, confirmed outcomes and observation

- Move reusable `current`, Start, Stop and command-outcome coordination from CLI product composition into public, typed SDK application use cases.
- Add a coherent read/observe contract with gap-free initial snapshot + updates, ordering across workflow replacement, reconnect and error/loading semantics.
- Expose durable submission/processing status independently of committed workflow state.
- Keep platform identity, database location, permissions and concrete adapter creation at trusted host composition; remote clients use host authority.
- Adapt CLI/Explorer to consume the SDK operations and state/observation contracts, not direct behavior calls or local transition methods.

**Done when:** Another frontend can consume the same workflow operations and reactive state without importing `rudra_cli` or reimplementing domain logic.

### 6D — End-to-end safe workflow extensibility in processing and persistence

- Remove hardcoded Initial/Active source assumptions in the processor where contractually unjustified.
- Generalize inbox history loading and restoration for valid nonterminal workflow phases.
- Generalize safe commit categories: establishment, continuation and terminal completion, with explicit transaction invariants and fail-closed errors.
- Validate synthetic continuation through the entire SDK/Drift pipeline, including reconciliation, identity/version conflicts, crash and transaction failures.

**Done when:** A registered continuation can be processed, committed and restored without editing a concrete Start/Stop dispatcher branch or bypassing safety invariants.

### 6E — Independent nested workflow CLI commands

- Reuse `RudraCliModule` and `package:args` with independently contributed Start/Stop commands.
- Ensure future Pause can register without expanding unrelated CLI constructors, framework switches or test fixtures.
- Retain real command integration tests and existing flags/exit codes unless a change is explicitly approved.

**Done when:** A new subcommand requires its own implementation/tests and explicit composition registration, not changes to unrelated framework code.

### 6F — Final realignment, tests, documentation and change-impact review

- Remove stale compatibility assumptions, redundant model/presenter layers and obsolete tests.
- Reconcile `docs/ARCHITECTURE.md`, ADRs and developer conventions with the actual implementation. Consider a new ADR for the composite state and frontend presentation decisions.
- Run the full verification suite and inspect file-level change locality.
- Walk the hypothetical Pause addition across SDK, persistent projection, commands, CLI and UI; document intended UI modifications separately from unintended generic framework edits.

**Done when:** The full suite passes, repository docs match reality, and the Pause litmus test succeeds without weakening safety.

## 9. Safety and behavior regression checklist

- Explorer launch, navigation, read-only restoration, state observation, layout and Quit do not submit or process persistent workflow commands.
- Read-only Explorer does not create a database where none existed.
- Command acceptance is not misreported as committed workflow success; pending/rejected/quarantined outcomes remain distinguishable.
- Committed history replays deterministically; corrupt or mismatched evidence causes explicit failure, not silent repair or null substitution.
- Trusted OS-user identity is not replaceable by frontend identity; at most one unfinished workflow per OS user is reserved atomically.
- A stale snapshot/expected ID/version cannot advance or terminate a replacement workflow.
- Journal, projection, ownership and submission resolution obey transactional consistency.
- Global candidate reservation, approval, execution gatekeeper, outbox, quarantine and recovery invariants from ADR 0006 remain intact.
- Views, presenters, UI state and informational event listeners never trigger destructive filesystem operations.
- Terminal host restores modes and screen state on normal exit and catchable exceptions; do not claim crash/SIGKILL/power-loss guarantees.
- Public CLI keybindings, flags, user-facing messages and exit codes remain stable unless deliberately changed and documented.
- A changed Actions/Footer widget may require its own test updates; unrelated decoder and runner tests must not need new feature-specific cases.

## 10. Alternatives considered

- **Patch existing `can_start`/`record_started` helpers:** Rejected. Makes frontend code the keeper of workflow-specific lifecycle rules.
- **Second frontend workflow state machine:** Rejected. Duplicates SDK authority and drifts across platforms.
- **Additional capability/policy evaluation layer for button visibility:** Rejected for now. SDK behaviors and transitions already own business constraints; straightforward visibility is a frontend concern. Revisit only with concrete requirements.
- **`NullWorkflowSnapshot` as a domain object:** Rejected. Falsifies workflow identity and can conceal absence versus error. Prefer a non-null `WorkflowsState` with a nullable current-workflow selector.
- **Mandatory Presenter / separate ViewState / giant ViewModel:** Rejected. Use small view models as UI state and stateless compositional widgets; retain a presenter only for substantial useful transformation.
- **Dynamic generic action-descriptor UI to avoid ever editing a widget:** Rejected. A real new `P Pause` instruction legitimately changes the relevant view and view model.
- **Universal plugin/service registry or `Map<String, dynamic>` slices:** Rejected. Explicit, typed, layer-specific registration is sufficient and safer.
- **Exact-state subclass tree carrying an ever-growing whole-workflow data bag:** Not accepted as the long-term model. Migrate the current minimal lifecycle state machine toward a composite immutable snapshot with typed slices.
- **Mutable session as source of truth, ephemeral event bus, or independent frontend event replay:** Rejected by ADR 0006. Keep committed append-only history and authoritative SDK observation.

## 11. Verification procedure

Per coherent completed slice (commands subject to repo script availability):

```text
./rudra format
./rudra verify cli
./rudra verify all
git diff --check
git status --short
```

A green generic unit suite is insufficient: check domain contracts, persistence invariants, terminal lifecycle, integration tests and the list of files changed. No tests were run merely by updating this document.

## 12. ADR alignment and references

- [ADR 0004 — SDK-First Application Architecture](../decisions/0004-sdk-first-application-architecture.md): shared domain/application behavior belongs in SDK; UI and composition are independent.
- [ADR 0005 — CLI Feature-First Structure](../decisions/0005-cli-feature-first-structure.md): isolate CLI features and tests; retain compositional core rendering.
- [ADR 0006 — Event-Sourced Workflow and Reactive SDK Architecture](../decisions/0006-event-sourced-workflow-architecture.md): durable commands, state-machine authority, event journal, reactive SDK state, host trust and execution gatekeeper.
- [Current SDK workflow module registry](../../packages/sdk/lib/src/workflow/modules/workflow_module_registry.dart) and [workflow runtime](../../packages/sdk/lib/src/workflow/workflow_runtime.dart).
- [Current Explorer action registry](../../apps/cli/lib/src/features/explorer/application/explorer_action_registry.dart), [Runner](../../apps/cli/lib/src/features/explorer/application/explorer_runner.dart), [workflow interaction snapshot](../../apps/cli/lib/src/features/workflow/explorer/workflow_explorer_state.dart).

This epic **extends** existing ADRs; it does not silently supersede their safety invariants. Once concrete SDK composite-state and observation contracts are implemented, record any genuinely new permanent design decision in an ADR rather than silently treating illustrative names here as final APIs.

## 13. Working agreement and resumption

- Inspect newest pushed `main` at the start of each implementation slice; the latest code, not this dated review, determines what actually exists.
- Discuss and approve focused interface changes before coding. Make architectural pushback explicit; do not turn the document's illustrative APIs into commitments without review.
- For manual changes, give **file path, original commit-relative line range, complete BEFORE selection and complete AFTER replacement**. Nothing outside the BEFORE selection may implicitly be removed or edited. Prefer full-file replacements when the change warrants one.
- Keep DartDoc useful: purpose, contract, safety/side effects, parameter meaning, errors and examples where appropriate.
- Preserve working functionality and safety tests; avoid unnecessary replacement of stable subsystems.
- Verify each completed slice and update this epic's status to reflect actual merged work, not aspirational contracts.

### Resume prompt

> Continue Rudra Epic 6 using `docs/epics/rudra-epic-6-architectural-realignment.md` as the agreed architectural reference. Inspect the latest `main` at https://github.com/ibrahimab/rudra before proposing code. We agreed on one authoritative event-sourced composite SDK workflow state with typed slices and reactive observation; SDK-owned behaviors and operations; a non-null workflows slice with nullable current workflow; no duplicated frontend lifecycle state or additional capability framework; ViewModel-as-frontend-state; small stateless compositional widgets; optional presenters; explicit frontend action composition; and safety-preserving extensibility. The amended Explorer 6A code is incomplete and the tests still need migration. Propose the next minimal, coherent 6A change using exact BEFORE/AFTER blocks and retain SDK/persistence work for the appropriate subsequent slices.

**Provenance:** Updated from the existing Epic 6 document and a fresh GitHub inspection of `edbc075` on 2026-11-20, incorporating the agreed SDK-to-frontend architectural review. This update changes documentation only; it is **not** evidence of implementation or verification.
