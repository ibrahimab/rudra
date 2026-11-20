# Rudra — Epic 6: Architectural Realignment

**Status:** Architectural direction agreed in conversation on 2026-11-20; implementation not started. Detailed contracts and sequencing remain subject to slice-level review.  
**Previous title:** Feature Isolation, Extensibility & Test Architecture  
**Canonical repository:** https://github.com/ibrahimab/rudra  
**Review baseline:** `main` at `ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513` (commit message: `fixed product workflow composition`; inspected 2026-11-20).  
**Preceding milestone:** Block 5C complete: event-sourced workflow Start → Active → Stop → Ended; SQLite persistence; CLI actions; Explorer `S` and `X`; tests.  
**Nature of this document:** Project architectural source of truth for Epic 6, not evidence that the proposed refactors have been implemented. Reinspect `main` before each implementation slice.

## 1. Epic objective

Realign Rudra toward a **feature-isolated, extensible, testable** architecture: adding functionality should primarily mean adding feature-owned code and registering explicit contributions, not repeatedly changing generic infrastructure, unrelated feature implementations and shared test fixtures.

The Start/Stop workflow and Explorer `S`/`X` implementation exposed excessive coupling across input decoding, action dispatch, presentation, CLI subcommands, application composition, persistence and testing.

The target is **independent behavior ownership**, not merely more registries or fewer constructor parameters.

### Architectural acceptance test

Use a *hypothetical* `workflow pause` operation (not part of the current implementation) as a full-stack extensibility litmus test. The test must cover SDK behavior, restored state, authoritative persistence, frontend action contributions, CLI command registration and isolated tests. Passing only a registry unit test is insufficient.

## 2. Non-negotiable principles

1. **Feature ownership:** Each feature owns its behavior, application operations, frontend adapters/contributions, and related tests.
2. **Contract-based contributions:** Stable contracts and explicit registries replace workflow-specific hardcoded switches, enums and presentation conditionals *where extensibility justifies it*.
3. **Explicit composition:** Registration happens at application boundaries; no reflection, automatic discovery, service locator or global event bus.
4. **Frontend independence:** CLI, interactive Explorer, Flutter desktop, Android and web/trusted-host interfaces consume reusable SDK application operations. Frontend input and presentation remain frontend-specific.
5. **Explicit-action semantics:** Browsing, navigation, rendering and read-only restoration never implicitly submit persistent workflow events. Only explicit user/domain commands may submit them.
6. **Safety preservation:** Keep append-only authoritative event history, trusted OS-user ownership, expected-workflow-ID guards, replay validation, durable submissions, transactional persistence, fail-closed errors and terminal restoration.
7. **Avoid unnecessary abstractions:** Dependency injection, explicit composition, constructor parameters and switches are not automatically defects. Refactor where changes repeatedly cross unrelated ownership boundaries.
8. **Behavior first:** Keep observable CLI behavior, keys, outputs, exit codes, persistence semantics and safety guarantees across incremental refactoring.
9. **Pre-production flexibility:** Breaking internal changes are acceptable if deliberate and verified; there is no need for compatibility shims indefinitely.
10. **Documentation parity:** Update the relevant ADRs, architectural documentation and test conventions alongside changes; do not let this epic's source document drift from implemented code.

## 3. Repository review findings — 2026-11-20

All links below are pinned to reviewed commit `ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513`; later commits require fresh inspection.

### 3.1 Strengths to preserve

- **SDK workflow module system:** `WorkflowModuleRegistry` stages registrations, rejects duplicate handlers/serializers, commits only validated contributions and exposes immutable snapshots. `WorkflowRuntime.from_registry()` creates a coherent configuration. [Registry](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/packages/sdk/lib/src/workflow/modules/workflow_module_registry.dart), [Runtime](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/packages/sdk/lib/src/workflow/workflow_runtime.dart).
- **Top-level CLI modules:** `RudraCliModule` and `RudraCli.register_module()` support explicit command contributions, duplicate detection and pre-execution registration. Preserve and extend this idiom rather than inventing a competing CLI framework. [Module contract](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/core/cli/rudra_cli_module.dart), [Registration](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/rudra_cli.dart#L331-L392).
- **Explorer components:** Terminal host guards lifecycle; controller handles navigation/inspection; presenter creates immutable view models; rendering is separated. Preserve successful boundaries rather than rebuilding Explorer wholesale. [Runner](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/features/explorer/application/explorer_runner.dart), [Terminal host contract](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/features/explorer/terminal/explorer_terminal_host.dart).
- **Integration and safety tests:** Existing tests check no database created by read-only Explorer, durable Start/Stop, identity mismatch rejection, terminal restoration and real persistence. Preserve these assurances during moves/refactors.

### 3.2 Finding A: terminal decoder depends on workflow features

`TerminalInput.read_keys()` outputs `ExplorerKey`, whose enum includes `start_workflow` and `stop_workflow`. `S`/`X` key mapping lives inside `_ordinary_key`; workflow-specific decoder tests live in `terminal_input_test.dart`. [Decoder](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/features/explorer/terminal/terminal_input.dart#L11-L38), [Mapping](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/features/explorer/terminal/terminal_input.dart#L195-L225), [Tests](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/test/features/explorer/terminal_input_test.dart#L142-L159).

**Diagnosis:** Raw terminal decoding and semantic action binding are separate responsibilities. Adding `P` must not require changing the decoder or its tests.

### 3.3 Finding B: ExplorerRunner is turning into a workflow controller

The runner constructor accepts `active_workflow`, `pending_submission`, `start_workflow`, `stop_workflow`; it owns `_can_start_workflow` and `_can_stop_workflow`, the dedicated `S`/`X` branches, workflow-specific state mutation, workflow-ID result checks and the `ExplorerKey` switch. [Runner constructor](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/features/explorer/application/explorer_runner.dart#L64-L151), [Dispatch](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/features/explorer/application/explorer_runner.dart#L268-L385).

**Diagnosis:** Each additional workflow action forces modifications to generic Explorer orchestration. Identity protection is correct and must be kept, but should be owned by the feature's action/operation or shared safety contract, not duplicated across generic runners.

### 3.4 Finding C: presentation knows workflow-specific action availability

`ExplorerPresenter.present()` takes `can_start_workflow` and `can_stop_workflow`, then conditionally includes `S Start Workflow` and `X Stop Workflow` in navigation hints. [Presenter](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/features/explorer/presentation/explorer_presenter.dart#L175-L193).

**Diagnosis:** Keybinding, availability, dispatch and displayed hint are currently separate hardcoded sources of truth. Derive them from the same registered action definition and per-render availability snapshot. A visible action is *not* authorization; trusted operations must always revalidate.

**Preserve:** `ExplorerFooterViewModel` already consumes immutable prepared text and need not know workflow specifics. Do not needlessly remodel this component.

### 3.5 Finding D: nested workflow CLI subcommands are hardwired

`WorkflowCliModule` takes separate Start/Stop operation callbacks and `_WorkflowCommand` constructs private `_WorkflowStartCommand` and `_WorkflowStopCommand` directly. [Module](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/features/workflow/cli/workflow_cli_module.dart#L16-L91).

**Diagnosis:** A hypothetical Pause requires changing the existing group constructor and registration logic. Allow independently contributed nested subcommands while continuing to use `package:args` and explicit composition.

### 3.6 Finding E: workflow application use cases live in CLI composition

`ProductWorkflowComposition` combines trusted macOS identity and database-location assembly with `current`, `start`, `stop`, event submission, SDK processor construction, resolution polling, error translation and committed-result checks. Start and Stop duplicate parts of the submission resolution flow. [Composition](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/lib/src/composition/product_workflow_composition.dart).

**Diagnosis:** Other frontends should not import `rudra_cli` or reimplement these operations. Move reusable, typed application use cases into the pure-Dart SDK (or SDK-owned application contracts and implementations), with trusted identity, persistence and platform adapters injected at composition. Preserve read-only `current()` semantics and the distinction between accepted submission and committed outcome. Platform-specific secure provisioning may remain in host composition.

### 3.7 Finding F: SDK registration extensibility is not end-to-end

The state machine and behavior registry are generic, but downstream processing contains concrete assumptions:

- `WorkflowProcessor` classifies some rejections only for Stop and permits Initial/Active source states explicitly. [Processor](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/packages/sdk/lib/src/workflow/processing/workflow_processor.dart#L110-L163).
- `DriftWorkflowInbox` restores history specifically for `WorkflowStopEvent`. [Inbox](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/packages/persistence/sqlite/lib/src/features/workflow/submissions/drift_workflow_inbox.dart#L133-L154).
- `WorkflowStateReader.current()` accepts an unfinished `WorkflowActiveState`, and treats other nonterminal histories as invalid. [Reader](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/packages/sdk/lib/src/workflow/reading/workflow_state_reader.dart#L146-L252).
- `DriftWorkflowCommitter.commit()` dispatches only `WorkflowStartEvent` / `WorkflowStopEvent` to `_commit_start()` / `_commit_stop()`. [Committer](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/packages/persistence/sqlite/lib/src/features/workflow/history/drift_workflow_committer.dart#L57-L79).

**Diagnosis:** A registered Pause command would fail the full pipeline. This is a real architectural defect, but the dedicated Start and Stop SQL paths enforce essential safety invariants. Generalize safe *commit categories* and invariant checks without creating an unrestricted generic event writer.

### 3.8 Test architecture findings

- `terminal_input_test.dart` contains S/X business mapping tests that belong to feature-owned keyboard contribution tests.
- `explorer_runner_test.dart` (~970 lines) includes Start/Stop scenarios; `_Scenario` grows feature-specific constructor arguments. [Runner tests](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/test/features/explorer/explorer_runner_test.dart#L473-L774).
- `explore_command_test.dart` and `workflow_command_test.dart` include full production composition and SQLite scenarios, mixed with smaller tests. Preserve them as integration coverage but locate/name them consistently by responsibility. [Explorer command tests](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/test/features/explorer/explore_command_test.dart), [Workflow CLI tests](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/test/features/workflow/cli/workflow_command_test.dart).
- `workflow_module_test.dart` and `command_registration_test.dart` already use synthetic contributions for generic contract tests: extend that pattern. [SDK registration tests](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/packages/sdk/test/workflow/workflow_module_test.dart), [CLI registration tests](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/apps/cli/test/integration/command_registration_test.dart).

## 4. Target architecture

### 4.1 Dependency direction

```text
CLI commands / Explorer keyboard actions / Flutter desktop / Android / trusted web host
                            |
                            v
             SDK-owned typed application operations
                            |
                            v
           SDK workflow engine (registered behaviors,
         transitions, submission processing, validation)
                            |
                            v
                  Persistence contracts
                            ^
                            |
                SQLite / Drift adapter

Trusted application composition constructs and injects concrete dependencies.
```

- No SDK import of CLI / Flutter / Drift / macOS implementations.
- Platform-specific identity and filesystem access remain under trusted host authority.
- Explicit application-level operations are reusable; UI adapters are independent.
- Read-only queries must not enqueue or process persistent events.
- Domain event subscription is informative, never a mandatory prerequisite for rendering correctly restored frontend state.

### 4.2 Explorer interaction: separate three concerns

1. **Physical terminal decoding:** decode bytes/chunks/ANSI sequences into physical keys, independent of feature semantics. Input errors propagate; lifecycle remains with terminal host.
2. **Feature action contributions:** a minimal explicit `ExplorerAction`-style contract with unique `action_id`, keybinding, human-readable hint, availability predicate, and typed execution handler. Names/API are provisional; agree contracts before implementation. Include deterministic registration order, reserved keys and conflict validation. Keep the contract small.
3. **Generic dispatch:** Explorer coordinates input, controller navigation, rendering and registered actions. Do not add direct Stop/Pause branches. Keep core navigation directly inside Explorer where appropriate; do not build a universal UI-command framework.

**Crucial:** Invocation uses an explicit user action. Action availability drives hints and offered bindings, but is not authorization. A selected operation revalidates against authoritative domain state. Only after confirmed completion may displayed state change.

### 4.3 Presentation contributions

- Action hints and availability derive from the same action configuration used by dispatch.
- Feature-owned state projection can supply workflow status and action descriptors without forcing `ExplorerPresenter` to know individual Start/Stop/Pause commands.
- Preserve read-only filesystem presentation, existing view models, viewport handling and terminal sanitization.
- Avoid introducing a universal widget framework.

### 4.4 Nested CLI command contributions

- Keep `RudraCliModule` and `package:args`.
- Workflow Start, Stop and future Pause contribute their own nested `Command<int>` objects, with explicit assembly into the `workflow` group.
- No per-subcommand additions to unrelated command constructors or generic registration code.
- Top-level product composition is allowed (and expected) to enumerate enabled contributions.

### 4.5 SDK application operations

- Place reusable `current`, `start`, `stop` and future use cases within the SDK's application boundary rather than `apps/cli`.
- Share common submission tracking/processing logic where reasonable without hiding transaction and identity semantics.
- Retain typed domain conflicts distinct from unexpected infrastructure/integrity errors.
- Continue to distinguish durable *acceptance* from committed *outcome*.
- Keep configuration of trusted OS identity, database location, permissions and concrete persistence at trusted composition boundaries.
- Avoid a giant service class that centralizes every future feature.

### 4.6 Extensible safe persistence

Persist general lifecycle categories, each with appropriate invariants:

| Category | Meaning | Commit obligations |
|---|---|---|
| Establishment | Create the user's unfinished workflow | Trusted identity, unique unfinished reservation, validated events, atomic journal + projection + submission resolution |
| Continuation | Advance an existing nonterminal workflow, e.g. Pause | Exact identity and version, journal replay, retained ownership, atomic journal + updated projection + submission resolution |
| Terminal completion | End an existing workflow | Exact identity and version, terminal-state validation, atomic journal + ownership release + submission resolution |

The authoritative journal must remain append-only. Every state projection must be reconstructable from persisted events. The persistence adapter rechecks submitted events, trusted owner, history, version and completion status *inside transactions*; never trust a frontend's state snapshot or a previously read inbox entry as a lock.

Do **not** undertake this persistence refactor in Slice 6A; it is safety-sensitive and deserves its own targeted tests.

## 5. Test architecture and fixtures

### Five explicit layers

1. **Component unit:** raw decoder, action handler, presenter, view model, pure SDK behavior. Fake only direct contracts.
2. **Registration/contract:** synthetic contributions assert unique IDs, collision behavior, stable ordering, immutability, invalid contributions and non-execution at registration.
3. **Feature-owned adapter/application:** Start/Stop/Pause CLI commands, Explorer actions and SDK operations, each under its own feature directory and using injected fakes.
4. **Integration:** actual SDK + Drift + composition + terminal fakes as appropriate; verifies persisted results, ownership and restore semantics.
5. **Representative end-to-end:** actual product entrypoint and, where practical, native terminal lifecycle; keep small, representative and deterministic.

### Representative test hierarchy (illustrative; not a bulk-move instruction)

```text
apps/cli/test/
  core/
    input/terminal_input_test.dart
    actions/action_registry_test.dart
  features/
    explorer/
      application/explorer_runner_test.dart
      presentation/explorer_presenter_test.dart
    workflow/
      cli/start_command_test.dart
      cli/stop_command_test.dart
      explorer/start_action_test.dart
      explorer/stop_action_test.dart
  integration/
    cli_registration_test.dart
    workflow_cli_lifecycle_test.dart
    explorer_workflow_lifecycle_test.dart
  support/
    fake_terminal_host.dart
    recording_renderer.dart
```

Use corresponding boundaries within SDK and persistence packages; do not force directory nesting for trivial features.

### Fixture rules

- A shared fake may represent a stable generic contract (terminal host, renderer, fake persistence adapter, inspection contract).
- Scenario assembly remains local to the responsible feature. Do not introduce one giant `_Scenario` builder with every new feature's callbacks/flags.
- Generic runner tests use synthetic actions, not real Workflow Start/Stop behavior.
- Action tests use fake SDK application operations; they should not need SQLite merely to test keypress-to-operation mapping.
- Integration tests cover real persistence and command composition; do not eliminate or replace them with shallow mocks.
- Tests may intentionally verify the complete enabled composition list; changes to such tests when registering new features are legitimate.
- Preserve current safety tests for read-only Explorer, expected workflow ID mismatches, trusted ownership, crash/retry semantics, transaction failure, and terminal restoration.

### Minimum test matrix for each new action

| Test boundary | Proof |
|---|---|
| Physical input decoder | Characters/ANSI sequences decode without feature knowledge |
| Registry contract | Contributions register; conflicts fail atomically |
| Feature action | Explicit action invokes only its typed operation with correct context |
| Availability/presentation | Hint and action availability agree; state refresh is correct |
| Generic runner | Synthetic action executes sequentially; failures restore terminal |
| Application operation | Correct submission/result semantics and errors |
| SDK state machine | Valid transitions; invalid transitions rejected; replay stable |
| Persistence integration | Ownership, expected ID/version, journal/projection and atomicity |
| Product composition | Real feature wired and available in desired frontend |
| End-to-end | Representative user workflow and no unintended writes |

## 6. Alternatives and decision rationale

**A. Patch local extension points:** Easiest initially; leaves shared SDK operations and persistence as bottlenecks. Insufficient for full `workflow pause` acceptance test.

**B. Layer-specific explicit contribution contracts — SELECTED DIRECTION:** A small interaction registry, reuse CLI modules, reuse SDK module semantics, and safe lifecycle-aware persistence. Best balance of ownership, evolution and traceability; does require coordinated incremental slices.

**C. Universal plugin/service registry:** Would unify wiring superficially but adds a broad framework, obscures dependencies and complicates safety. Reject unless future concrete requirements justify it.

Do not equate every switch, constructor argument or composition update with a code smell. The relevant problem is whether a new feature routinely forces generic infrastructure and unrelated feature tests to change.

## 7. Incremental implementation slices

**Important:** Architecture and order are agreed at a high level; no code has been written for Epic 6 as of this document. Each slice needs design approval and verification before coding the next.

### 6A — Terminal decoding and action registration foundation (FIRST)

- Separate physical key interpretation from semantic actions.
- Design minimal explicit action registration and keybinding contract.
- Validate duplicate IDs, conflicting bindings, reserved navigation shortcuts and deterministic ordering.
- Add decoder-only tests and synthetic registration tests.
- Preserve S/X/Q/arrows/Enter/Backspace behavior using the smallest compatible migration bridge until Slice 6B.
- **No** persistence or SDK workflow changes.

**Done when:** A synthetic action can claim an otherwise unused printable key without modifying the decoder, its tests, or generic action registry code. All existing terminal and Explorer behavior remains green.

### 6B — Feature-owned Explorer interactions

- Extract workflow Start and Stop into independently owned action contributions.
- Make the Explorer runner dispatch actions without workflow-specific branches or injected operation proliferation.
- Generate hints from registered, available actions.
- Relocate Start/Stop action tests under workflow ownership; generic runner tests use synthetic contributions.
- Preserve ID-concurrency checks, navigation semantics, viewport updates and guaranteed terminal restoration.

**Done when:** A new action can be added without touching the generic runner, presenter conditions, physical decoder, or their unrelated tests.

### 6C — Nested workflow CLI commands

- Allow independently contributed subcommands under `rudra workflow`.
- Reuse `RudraCliModule`/`package:args` approach; do not create a parallel CLI system.
- Move Start/Stop tests to feature-owned adapters; keep representative command integration tests.

**Done when:** A new workflow subcommand requires only its own implementation/test and explicit product composition registration.

### 6D — Portable SDK application operations

- Extract reusable `current`, `start`, `stop` and submission-outcome tracking from CLI-specific composition into SDK-owned typed application services/use cases.
- Preserve trusted platform identity resolution and concrete adapter construction at appropriate host boundaries.
- Ensure CLI/Explorer share identical application behavior without direct CLI coupling.
- Add SDK unit/contract tests and real persisted integration tests.

**Done when:** A separate frontend could consume the same operations without depending on `rudra_cli` or duplicating submission processing.

### 6E — End-to-end SDK workflow extensibility

- Review processor source-state assumptions and business rejection classification.
- Generalize inbox history restoration for continuation commands.
- Allow replay/restoration of valid nonterminal workflow states.
- Refactor persistence around safe establishment / continuation / terminal categories, preserving transaction checks and fail-closed behavior.
- Test with synthetic nonterminal continuation behavior, **not** by prematurely implementing full Pause UX.

**Done when:** A registered nonterminal command can pass through processing, persistence and authoritative restoration without modifying generic Start/Stop dispatcher branches or bypassing invariants.

### 6F — Verification, docs and architecture enforcement

- Finish fixture consolidation and integration-suite responsibility cleanup; avoid mass test rewrites without benefits.
- Update ADR/ARCHITECTURE/DEVELOPMENT docs to reflect actual implementation.
- Perform the hypothetical Pause change-impact review across all layers.
- Establish maintainable architecture checks where justified (imports, contract conformance, registration tests), not a large custom framework.

**Done when:** Full suite passes; documented boundaries match code; Pause litmus test demonstrates new-feature code + explicit composition rather than unrelated infrastructure modifications.

## 8. Behavior and safety preservation checklist

Do not declare a slice done if any of the following regresses:

- No implicit workflow submission from Explorer launch, navigation, view rendering, quit or read-only restoration.
- No database creation from read-only Explorer when no persistence exists.
- Only explicit Start or Stop initiates corresponding persistent commands.
- Accepted submission is not misreported as a committed workflow.
- Restore state from the authoritative journal; corruption is not silently ignored/repaired.
- Trusted OS-user identity cannot be overridden by frontend-provided ID.
- Stale displayed workflow ID never causes termination of a replacement workflow.
- New workflow ownership reservation is exclusive per OS user.
- Transaction boundaries atomically update journal, projection and submitted-command completion.
- Failed/quarantined/rejected operations are not misreported as success.
- Terminal modes and interactive display state are restored on successful exit and catchable failures; do not claim SIGKILL/power-loss guarantees.
- Existing CLI command names, flags, user-facing messages and exit codes remain unchanged unless intentionally revised and documented.

## 9. Workflow Pause litmus test (not an implementation request)

For a future `workflow pause` capability, expected changes should concentrate in:

- New SDK command event + behavior + state transition(s) + serializer + typed operation;
- New feature-owned CLI command, Explorer action/hint and their tests;
- Registration in SDK/runtime and product/frontend composition;
- New feature-specific persistence/domain tests and representative integration coverage.

Expected **no routine changes** to:

- `TerminalInput` and its physical decoding tests;
- Generic Explorer action dispatcher/runner tests;
- Start/Stop action and CLI test suites;
- Generic CLI framework/command group internals;
- SDK state machine, workflow processor and SQLite commit dispatcher for each new registered continuation behavior, once 6E has established the extension point.

Changes to explicit registries, product wiring, intentional composition snapshots, database migrations required by real new domain data, and safety policy tests are legitimate. Goal is not zero modified existing files; goal is change-locality and no unrelated test churn.

## 10. Verification approach

Per focused slice, use (as available in the repository):

```text
./rudra format
./rudra verify cli
./rudra verify all
git diff --check
git status --short
```

These are **planned verification commands**. The architectural review was read-only: no local test execution or implementation is claimed. Confirm exact commands against current repository scripts before use.

Review not only test pass/fail but the list of files changed. A new feature shouldn't unexpectedly touch raw terminal decoder, unrelated tests, generic runner and persistence dispatcher unless the slice intentionally changes a contract.

## 11. Open design questions to settle during Slice 6A/6B

1. **Action context:** What minimal read-only contextual snapshot can an action inspect? How does an action propose an updated frontend model after an explicitly executed operation without owning generic Explorer navigation state?
2. **Availability timing:** Evaluate at render time and recheck on dispatch? How to prevent stale UI races while preserving the SDK as final authority?
3. **Key conflicts:** Which physical shortcuts are reserved by Explorer? How are duplicate action keys/IDs detected transactionally before entering terminal mode?
4. **Error classification:** Which failures become typed frontend diagnostics vs propagated unexpected errors that must trigger terminal restoration?
5. **State projection:** How to represent optional workflow status without giving generic Explorer headers a dependency on each future lifecycle state?
6. **Command grouping:** Extend the existing `package:args` nesting naturally without making a new general command-registry DSL.
7. **SDK persistence contracts:** Defer exact categories and contracts until Slice 6E review of all ownership, replay and concurrency guarantees.

## 12. ADR and prior decision alignment

- [ADR 0004 — SDK-First Application Architecture](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/docs/decisions/0004-sdk-first-application-architecture.md): shared operations belong to SDK; frontends supply UI; concrete adapters are composed externally.
- [ADR 0005 — CLI Feature-First Structure](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/docs/decisions/0005-cli-feature-first-structure.md): feature ownership, shared core and test placement. Epic 6 makes extensibility real rather than purely structural.
- [ADR 0006 — Event-Sourced Workflow Architecture](https://github.com/ibrahimab/rudra/blob/ffa62313fbfef6b0eeb3a4a1684e8dab7ea56513/docs/decisions/0006-event-sourced-workflow-architecture.md): durable submission, replayable authoritative state, safe transactional persistence, frontend independence and explicit commands.

Epic 6 should **extend these decisions**, not establish a competing architectural paradigm. A new ADR (e.g. 0007, depending on repository numbering at implementation time) can record the approved contribution/test boundaries once the concrete 6A/6B contracts are agreed. Avoid asserting that such an ADR already exists.

## 13. Working agreement / resumption instructions

- **Review and discuss design before implementation.** No code until slice-level agreement.
- At the beginning of every new chat or slice: inspect the newest pushed `main` and compare it with this dated baseline. GitHub code remains the source of truth for *what is implemented*; this document is the reference for *why and where we are going*.
- Challenge assumptions and distinguish legitimate coupling from true extensibility defects.
- Prefer focused, verifiable slices and minimal changes to established working code.
- Never add abstractions solely because they are fashionable or because constructor injection is visible.
- Do not skip safety/integration tests to achieve more elegant source directories.
- Reconcile this document with implementation as slices land; mark completed slices explicitly and record deviations and rationale.

### Resume prompt

> Continue Rudra Epic 6 — Architectural Realignment. Read the Epic 6 source document in Project Sources and inspect the latest pushed `main` at https://github.com/ibrahimab/rudra. We agreed on layer-specific explicit contributions, feature-owned action and CLI tests, SDK-owned application operations and end-to-end safe workflow extensibility. Begin by reviewing the document's Slice 6A and proposing minimal physical-key and Explorer action-registration contracts. Discuss trade-offs first; do not implement until we agree. Preserve the current S/X/navigation behavior and terminal safety guarantees.

---

**Document provenance:** Compiled from the user-provided Epic 6 brief and the detailed architectural review of latest pushed `main` on 2026-11-20. This is an architectural decision record and implementation plan; it is not a claim that any Epic 6 refactoring has been done.
