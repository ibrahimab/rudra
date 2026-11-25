# Rudra — Epic 7: Centralized Host and Frontend Synchronization

**Status:** In progress — 7A complete; 7B.1, 7B.2, 7B.3.1 and 7B.3.2 complete; 7B.3.3 next
**Created:** 24 November 2026
**Updated:** 25 November 2026
**Repository:** https://github.com/ibrahimab/rudra
**Planning baseline:** `86cb08462467260afee8beba5f90d05be3aab33b`
**Predecessors:** [Epic 6 — Architectural Realignment](rudra-epic-6-architectural-realignment.md) and [Epic 6C — Observability and Future Trusted Host Direction](rudra-epic-6c-observability-and-trusted-host-direction.md)
**Architectural authority:** [ADR 0006 — Event-Sourced Workflow and Reactive SDK Architecture](../decisions/0006-event-sourced-workflow-architecture.md) and [ADR 0007 — Hierarchical Ownership and Encapsulated Composition](../decisions/0007-hierarchical-ownership-and-encapsulated-composition.md)

## 1. Purpose

Move Rudra's trusted application execution and persistence ownership out of independent frontend processes into **one per-user, long-running Rudra Host**. The host executes the existing SDK application machinery and distributes validated committed application state to connected frontends.

**The host must be platform-agnostic by design**, like the existing filesystem, workflow and state features. Portable host contracts, extension registries and orchestration belong in `packages/sdk/lib/src/host/`. Native host capabilities live under `packages/host/<platform>/`.

The independent `packages/communication/` package owns native communication mechanisms, transport contracts, peer authentication, session management and generic messaging infrastructure. RudraHost constructs and maintains its communication instance by default, while allowing explicit substitution through contracts.

`apps/host` provides headless application composition, establishing trusted identity, exclusive ownership and persistence resources before executing the host. The existing modular CLI provides the host launch command.

The immediate deliverable is a **small, working local macOS host using those portable boundaries**, not a generalized distributed-services framework or an implementation of all three desktop operating systems at once. Windows and Linux must be implementable by adding platform adapters and registering them, without changing portable SDK host logic.

### Acceptance scenario

1. Terminal A runs `./rudra explore` and displays the verified current workflow state.
2. Terminal B runs `./rudra workflow start`, or another Explorer presses **S**.
3. The host durably accepts and processes the requested command through the existing SDK, validates the transition, and commits through its owned SQLite persistence context.
4. Every connected Explorer receives a verified updated `RudraState` without needing a navigation key, manual reload, or process restart.
5. A simultaneous Start from two independent frontends cannot establish two unfinished workflows for the same trusted OS user. At most one distinct Start succeeds; the other receives the correct conflict/rejection outcome.
6. Stopping a workflow from either CLI or Explorer similarly updates all connected clients. Exiting Explorer leaves the committed workflow intact.

This epic is complete only when the scenario is proven with **separate operating-system processes**, not merely several observers in one test isolate.

## 2. Architectural decision and ownership boundaries

### 2.1 SDK-first host architecture and composition root

Rudra follows SDK-first application architecture and hierarchical component ownership.

- **SDK (`packages/sdk/`):** Owns application operations, domain semantics, workflow processing, state observation and portable host orchestration.
- **Communication (`packages/communication/`):** Owns reusable transport contracts, native communication implementations, connection and session lifecycles, and generic messaging infrastructure. It remains independent of the Rudra SDK, host application and persistence packages.
- **Native host adapters (`packages/host/<platform>/`):** Implement trusted identity, exclusive process ownership, process lifecycle coordination and explicit native service-management capabilities.
- **Host application (`apps/host/`):** Establishes trusted environmental configuration, exclusive ownership, application resources and persistence. It delegates execution to RudraHost.
- **Frontends (`apps/cli/`, later Flutter clients):** Consume application-facing host capabilities and observe verified state.

RudraHost constructs its communication instance by default. Communication constructs its default transport internally. Both support explicit substitution through contracts.

The SDK never imports concrete native host adapters. Native communication selection remains encapsulated within the communication package.

Application-specific message semantics and handlers belong to the host and domain SDK. Generic communication infrastructure remains unaware of those semantics.

Communication resource disposal must be confirmed before exclusive host ownership can be released. Failed execution and failed resource disposal are independently distinguishable.

One host retains one workflow application and one persistence context throughout its execution lifecycle.

### 2.2 Proposed feature-first layout

```text
packages/
  sdk/
    lib/
      rudra_sdk.dart
      src/
        filesystem/                     # Existing feature
        workflow/                       # Existing domain/application feature
        state/                          # Existing immutable state
        host/
          host.dart                     # SDK host feature barrel
          runtime/                     # Portable host lifecycle/coordination
          platform/
            contracts/                 # Identity, storage, ownership
            host_platform_plugin.dart  # Optional capability contribution
            host_platform_registry.dart
          install/
            host_install_step.dart      # Explicit installation contribution
            host_install_registry.dart
            host_install_plan.dart      # Describe/validate proposed changes
  communication/
    lib/
      rudra_communication.dart
      src/
        communication.dart
        sessions/
          connection_service.dart
        transport/
          contracts/
          local_transport.dart
          macos/
            unix/
    test/
    pubspec.yaml
  persistence/
    sqlite/                             # Existing SDK persistence adapter
  host/
    macos/
      lib/
        rudra_host_macos.dart           # Native adapter exports
        src/
          macos_identity.dart
          plugins/
            launchd/
              macos_launchd_plugin.dart
              launchd_service_manager.dart
            power/
              macos_power_plugin.dart
              macos_power_manager.dart
          install/
            steps/
              directories/
                macos_directories_install_step.dart
              executable/
                macos_executable_install_step.dart
              launchd/
                macos_launchd_install_step.dart
    windows/                             # Future native adapter package
    linux/                               # Future native adapter package
apps/
  host/
    lib/
      rudra_host.dart                   # Host application API
      src/
        composition/
          host_composition.dart
          local_host.dart
        development/
          host_transport_probe.dart
  cli/
```

This is an **ownership sketch, not an instruction to create all directories and types now**. Some contracts may be grouped or renamed as we implement coherent slices. Native packages can be split/shared when actual dependencies justify it; the example does not mandate duplication of transport code. The `host/host.dart` feature barrel follows the existing `workflow/workflow.dart` pattern and can be exported from public `rudra_sdk.dart`.

### 2.3 Platform capabilities, feature plugins and registration

The SDK owns platform-agnostic capability contracts; native adapters supply their implementations. Required runtime infrastructure initially includes trusted identity, authenticated IPC/listener, storage/runtime paths and host-instance exclusivity. Optional capabilities can be contributed as **independent plugins**, such as launchd service management and power management on macOS.

The SDK should define an intentionally small plugin contract and registry. In conceptual terms:

```dart
// Illustrative only; exact signatures belong to 7A/7E.
abstract interface class HostPlatformPlugin {
  String get id;
  void register(HostPlatformRegistry registry);
}
```

- Multiple plugins may be registered for one platform; a plugin contributes a focused capability, not an alternate host application.
- Registry composition is explicit, deterministic and validated. Duplicate plugin IDs and conflicting exclusive capability providers must fail clearly; independent contributions coexist.
- Required host infrastructure can be supplied directly by composition. **Do not force foundational IPC or identity into optional plugins merely for uniformity.**
- Registration is declarative and must not open listeners, change power settings, install services, create persistence or perform other operational side effects.
- Activation/acquisition (for example, acquiring a prevent-sleep lease) and release must have explicit lifetime ownership. Availability alone does not imply a capability should be enabled.
- Plugins must not implement workflow transitions or business rules; those remain SDK application responsibilities.

The macOS feature layout separates `plugins/launchd` and `plugins/power` so adding one does not modify unrelated implementations or a monolithic `MacOsHostPlatform` class. `launchd` is the native service mechanism; automatic start on login is a setting/action the service-management capability may expose, **not automatically a separate plugin**.

### 2.4 Explicit installation contributions

Installation is a separate feature, organized under each platform's `install/`, with SDK-owned contracts and a validated contribution registry under `src/host/install/`. Its structure resembles plugin registration, but **installer steps are not runtime plugins**: they describe and perform setup or removal when the user explicitly requests it.

Possible macOS contributions include application/runtime directory provisioning, executable placement and a launchd agent configuration. Each step must have a stable identity, prerequisites, inspectable intended changes, idempotent or explicitly guarded execution, a verifiable result and a defined partial-failure strategy. Do not promise transactional rollback of external OS operations. Actual contract shapes remain a 7E design decision.

- **Register:** Make a capability or install step discoverable; never execute it.
- **Plan/inspect:** Validate prerequisites and report what would change before mutation.
- **Install/configure:** Perform requested steps through their owning platform implementations, with explicit authorization and truthful failure reporting.
- **Run:** Start the already-composed host listener/runtime; do not call installation implicitly.
- **Uninstall:** Explicitly remove only documented managed components. Never silently remove a user's workflow database, journal or audit evidence.

A `launchd` installation step should **reuse** the launchd service-management capability instead of reimplementing native commands. Similarly, a power plugin may expose an optional, releasable power assertion used by an explicit host operation; simply running Rudra does not imply that preventing sleep is appropriate.

Installing a host may create *service-related configuration and runtime paths* when authorized. It must not initialize absent **workflow persistence** or create a workflow. Connection, observation, construction and normal start must never silently install, enable, configure or uninstall an OS-managed service. Start-on-login and automatic restarts are user-directed configuration, not implicit behavior.

**Flutter is not required for the headless service.** Pure Dart supports the portable SDK runtime and executable; Flutter is a choice for future graphical clients.

### 2.5 One host owns the application runtime and persistence

For a given authenticated OS user and Rudra persistence scope, one host process shall own:

- The composed `WorkflowRuntime` and `WorkflowApplication`.
- SDK command processing (`EventManager`, `WorkflowProcessor`, `WorkflowStateMachine`) through their existing contracts.
- The SQLite/Drift persistence adapter, database connection lifetime, transactional committer, journal, inbox, projections and submission resolution.
- The existing post-commit `WorkflowCommitPublisher.publish()` and `WorkflowCommitSubscriber.watch()` context.
- SDK state restoration/observation and client subscription fan-out.

**The host is the sole intended writer for official Rudra frontend operations.** Production CLI/Explorer clients shall not open workflow SQLite connections, instantiate their own workflow processors or persist workflow outcomes directly after cutover. No direct-SQLite fallback is permitted when the host is unavailable.

Host ownership is not a replacement for transactional safety. SQLite constraints, compare-and-set validation, workflow identity/version checks, durable idempotency and ownership invariants remain authoritative even when a single host coordinates requests.

One host-owned persistence context is the architectural target; implementation must confirm actual Drift/SQLite connection behavior rather than claiming physical single-connection guarantees without verification. The persistence adapter stays in `packages/persistence/sqlite`, not in a new duplicate platform persistence layer.

### 2.6 Frontends remain thin consumers

A frontend may own navigation, terminal input, rendering, local selection, view models and explicit user-action handling. It communicates with the host through an **application-facing client contract** for supported operations and state observation.

A frontend does **not** call `WorkflowStateMachine` directly. It requests `WorkflowApplication` operations **through the host**, which uses the existing state machine internally. Neither SDK host coordination nor native host adapters reimplement lifecycle rules, outcome transitions, typed reducers, journal replay or safety policy.

Explorer's **S** and **X** actions and `./rudra workflow start|stop` must converge on the same host-side application operations. Feature-specific frontend actions remain independently registered. Generic terminal key decoding remains unaware of workflow semantics.

### 2.7 Existing SDK observation remains the inner boundary

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

The host sends **verified application state**, not uncommitted proposals, raw frontend-replayed domain events or an accepted submission masquerading as a completed transition.

### 2.8 One process owner is not a new workflow lifecycle

A workflow persists independently of the host process, client connection, terminal or frontend. Starting/stopping the host never implicitly starts/stops a workflow. A host restart reconstructs the current workflow from the authoritative journal.

One host per trusted user/scope is **process and resource ownership**, not a new domain session. The current one-unfinished-workflow-per-user rule continues to be enforced by SDK/persistence, not merely by the host's request queue.

## 3. Target topology

```text
Terminal A: ./rudra explore    Terminal B: ./rudra workflow start|stop
            |                             |
            +-----------+-----------------+
                        |
              Application client API
                        |
          Authenticated local transport
             (native host adapter)
                        |
             Rudra SDK host runtime
        (packages/sdk/lib/src/host)
                        |
               WorkflowApplication
              /               \
       SDK processing      SDK observation
              |               ^
       WorkflowCommitter      | watch()
              |               |
      SQLite/Drift journal -- publish()

apps/host: detect OS, register and compose native adapters
    → SDK host runtime: run with one application/persistence owner
    → platform plugins: optional capabilities, explicitly activated
    → install contributions: explicit setup/removal, never run implicitly

Future desktop/mobile/web frontends use the same application-facing
semantics through appropriate authenticated transport adapters.
```

The host is a **new headless Dart application in the existing monorepo**. Do not put native service-management implementations inside the SDK or a second workflow engine inside the host. Any shared transport/client package must be justified by actual dependencies, not pre-created from a speculative diagram.

## 4. Local MVP boundaries

### Included

- A portable SDK host feature with necessary platform capability contracts and a small validated registration mechanism.
- `apps/host` as the composition root, selecting the native implementations supplied by `packages/host/<platform>`.
- One macOS adapter-backed per-user host and one configured local persistence scope as the first verified implementation.
- One deliberately managed host listener, initially runnable explicitly for development.
- Explicit optional platform plugins and distinct install-step contributions, introduced only when needed by their slices.
- Local IPC for multiple CLI processes (Unix-domain socket is a leading design; verify support and security on each target platform before coding).
- Authenticated/trusted local owner resolution and socket/path permission controls.
- Application-facing **read current state**, **observe state**, **Start** and **Stop** operations, with typed outcomes and errors.
- Shared host-side SDK processing/persistence and post-commit state distribution.
- Integration of existing CLI workflow commands and Explorer action/display paths.
- Safe initial subscription, disconnect, cancellation, reconnection/re-synchronization and host shutdown behavior.
- Explicit macOS-managed activation/lifecycle integration, planned and installed through separate SDK-defined installation contributions after the runnable host works (per-user `launchd` agent is the initial direction; verify mechanics before implementation).

### Deferred

- Fully implemented Windows and Linux host adapters/service installation; their **architectural compatibility is not deferred**.
- Optional power-management activation and additional plugin capabilities not needed by the 7A–7E acceptance scenario.
- Network exposure, pairing, remote authorization, TLS/WebSocket delivery and actual Android/web clients.
- Generalized background command scheduling, crash recovery workers or automatic filesystem cleanup.
- New workflow domain states, Pause, candidate planning/execution and destructive-operation gatekeeper changes.
- Durable cross-restart stream cursors or a full historical event-feed API; journal restoration remains authoritative.
- Multiple database backends or clustered/replicated hosts.
- Unrestricted arbitrary event submission from untrusted clients.

**Offline behavior:** Until an explicit offline-capable contract is designed, a client unable to reach the host reports the host as unavailable. It shall not silently open SQLite or invent a verified `Workflow: NONE` state.

## 5. Correctness, concurrency and transport requirements

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

Define the minimal wire contract for correlation, operation results, typed errors, state snapshots, stream completion and protocol version/compatibility. Use bounded messages and explicit backpressure/error behavior.

The transport represents **SDK application semantics** and must accommodate registered feature-owned state slices later. Do not hardcode a permanent Start/Stop-only state model, transfer unchecked dynamic domain bags or make frontend clients reimplement the event replay engine. Decide codec ownership/registration at the appropriate composition boundary **before** implementation.

Portable framing and application-facing semantics belong above native transport adapters. Socket APIs, peer-identity calls, path naming and platform-specific service discovery belong below those contracts.

### 5.4 Disconnect, reconnect and failure

- A disconnected client releases its subscription resources; it does not stop a workflow.
- On reconnect or host restart, the client obtains **fresh validated state** before resuming updates. Old host generations/streams must not overwrite newer state.
- A failed read, broken stream, missing host or corrupted journal is an explicit unavailable/error condition, not verified absence.
- Errors during Explorer interaction must not leave terminal modes or cursor state unrestored.
- A host crash may leave durable accepted submissions unresolved; do not claim background processing or automatic recovery until implemented and tested.

### 5.5 Trust and process exclusivity

Trusted identity comes from the host's OS context and authenticated local transport, **not** a client-supplied `os_user_id`. Validate IPC peer identity where supported and secure socket/database directories. Do not expose the local service on a network interface by default.

Use an explicit single-owner strategy for host startup and database access. Multiple competing host instances must fail closed or resolve to the same authorized owner; do not assume a socket filename alone solves races. Official clients must use host transport after migration, including workflow commands and Explorer.

An unrelated process deliberately opening the same database under the same OS account is outside the cooperative single-writer guarantee unless stronger OS isolation is introduced; preserve SQLite safety validation regardless.

### 5.6 Read-only and destructive-operation safety

Connecting, observing, rendering, navigating, quitting, cancelling and reading verified absence must not create an absent database or submit/process commands. Only explicit authorized Start may initialize workflow storage as currently designed. No filesystem cleanup occurs from host startup or subscription notifications. Existing append-only journal, quarantine, outbox, revalidation and execution-gatekeeper requirements from ADR 0006 remain intact.

## 6. Implementation slices

Slices are defined by **coherent responsibilities**, not file counts. Agree on interfaces and failure semantics before editing, verify each slice, then inspect the pushed commit.

### 7A — Portable SDK host runtime, native capabilities and composition

**Goal:** A thin `apps/host` entrypoint composes and runs one long-lived SDK host/application/persistence context. It chooses native adapters without implementing OS-specific behavior; the portable host has no platform branches.

- Introduce `packages/sdk/lib/src/host/` with only the contracts and portable coordination actually needed by this slice; reuse `WorkflowApplication` and existing observation services.
- Define a minimal, validated registration/composition approach for native host capabilities, with optional plugin contributions isolated from required runtime infrastructure. Do not implement launchd/power plugins ahead of their need.
- Introduce the native macOS implementation under `packages/host/macos/`, including trusted identity, local IPC listener and exclusive-instance ownership as required. Each native implementation depends on SDK contracts.
- Add `apps/host` with a minimal executable and composition root: detect OS, select/inject native implementations, construct one long-lived runtime, workflow application and SQLite persistence owner, then call the SDK host lifecycle.
- Establish deterministic shutdown, connection/subscription cleanup and correct adapter resource disposal.
- Start only the host listener and necessary service-runtime resources; never install a launch agent or initialize workflow persistence merely by starting/observing.
- Introduce a minimal listener with real macOS security checks; defer the full RPC protocol to 7B and installer operations to 7E.
- Prove SDK host portability with fake platform contracts, and verify macOS-specific composition and permissions separately.

**Gate:** One explicitly started host accepts multiple local connections while owning one SDK application/persistence context. Startup, exclusivity, shutdown and missing-storage behavior are tested. No frontend cutover yet; no macOS branches in SDK host orchestration; no automatic host installation.

### 7A.4 — Communication infrastructure extraction

**Goal:** Establish an independently reusable communication package and hierarchical component ownership in accordance with ADR 0007.

- Extract portable transport contracts and connection lifecycle coordination into `packages/communication/`.
- Relocate native communication implementations and their feature-owned tests.
- Establish an independent communication package without dependencies on Rudra application, host or persistence packages.
- Introduce the Communication facade with internally constructed defaults and explicit contract-based substitution.
- Encapsulate native transport selection within the communication subsystem.
- Make RudraHost construct, maintain and own its communication instance.
- Remove listener construction, binding and disposal responsibilities from host application composition.
- Preserve trusted identity, authenticated connections, exclusive ownership and deterministic resource disposal.
- Verify default construction, explicit substitution, independent testing and fail-closed ownership behavior.

**Gate:** Existing authenticated IPC and concurrent session behavior remain verified. Communication is independently reusable and owns its internal components. Typed application messaging remains the responsibility of 7B.

This architectural realignment supersedes the earlier allocation of communication contracts and native IPC implementations to the SDK host and native host adapter packages.

### 7B — Host application command contract

**Goal:** Independent clients can invoke the same SDK operations through the host.

- Establish minimal request/response framing and typed error/correlation semantics above the native IPC adapter.
- Expose current-state read, Start and Stop through the existing `WorkflowApplication`.
- Coordinate concurrent host requests without weakening transaction-level checks.
- Preserve durable acceptance versus confirmed commitment and idempotency behavior.
- Test simultaneous competing Starts from separate client connections.

**Gate:** Concurrent Start yields at most one unfinished workflow and correct per-request outcomes, verified against real SQLite journal evidence.

#### 7B.1 — Typed communication infrastructure (complete)

Established reusable typed messaging infrastructure, including request and response registration, serialization, correlation and request execution.

Communication remains independent of Rudra application semantics. Transport implementations and application-specific message contributions retain their respective ownership boundaries.

#### 7B.2 — Typed application messaging contracts (complete)

Introduced application-owned messaging contributions for workflow establishment, termination, durable submission resolution and composite application state reading.

Operation identifiers, request correlation and durable submission identities remain independently owned concepts.

Composite state serialization uses registered feature-owned slice codecs. Application messaging does not introduce lifecycle transitions or persistence behavior.

#### 7B.3.1 — Durable idempotency and application resolution (complete)

Established one authoritative execution contract for explicit workflow Start and Stop operations.

- Start requires the configured target, original target-native root and idempotency key.
- Stop requires the intended workflow identifier and idempotency key.
- Durable acceptance precedes mutable workflow-state validation.
- Identical scoped operations recover their original durable submission identities and terminal resolutions.
- Conflicting key reuse returns a typed idempotency conflict without creating a replacement submission.
- Application outcomes are owned by the application feature rather than messaging.
- Resolution construction enforces mutually exclusive processing metadata.
- Persistence validates historical command compatibility, causation, correlation, ownership and journal evidence inside a consistent read transaction.
- Historical resolution is independent of the current unfinished-workflow projection.
- One WorkflowApplication serializes command processing, including explicit processing requests and operation-driven resolution.
- Failed processing releases the application processing lane without fabricating successful commitment.
- Business rejection and quarantine remain durable terminal resolutions.
- Existing CLI, Explorer and explicit host startup consumers use the new application contract.

**Verification:** Dedicated SDK tests and real SQLite integration tests cover concurrent retries, conflicting submissions, historical resolutions, interrupted acceptance, persistence reopening, durable rejection and quarantine recovery, journal uniqueness and commit notification counts.

**Boundary:** Application serialization applies to one retained application instance. Independent frontend processes do not yet share that instance. Transport-level recovery, authenticated request routing and competing independent client connections remain subsequent work.

**Implementation increments:**

- 7B.3.1A — Application outcome and resolution integrity: `72837bd6aa33e16fd408b9e3e53e4e0717348fa6`
- 7B.3.1B — Serialized idempotent application execution: `53b24b35348c5cd15957640c6f7dba1657a5b4ce`
- 7B.3.1C — Real SQLite recovery and concurrency verification.

#### 7B.3.2 — Authoritative host application request handlers (complete)

Bind registered application request contracts to the single WorkflowApplication retained by RudraHost.

- Register Start, Stop, durable submission-resolution and composite state-read handlers through feature-owned contributions.
- Route explicit operation identifiers and command parameters unchanged to the authoritative application.
- Return typed application outcomes through the existing communication contracts.
- Keep authenticated ownership in trusted host composition.
- Preserve the distinction between application outcomes and communication or infrastructure failures.
- Introduce no additional workflow processor, persistence owner or domain execution path.

**Gate:** Authenticated request dispatch invokes the retained application and returns its verified application outcomes.

**Implementation and verification:**

- Workflow and State messaging modules contribute local request handlers alongside their existing codec registrations.
- RudraHost assembles and freezes the application messaging configuration before communication resource acquisition.
- State serialization uses the immutable workflow runtime retained by the authoritative application.
- Communication authorization derives its trusted owner from that application.
- Explicit communication substitution receives the host-owned configuration through a factory.
- Application handlers verify authenticated peer ownership before accessing execution or persistence.
- Target-specific establishment validation remains the responsibility of trusted host composition.
- Submission-resolution queries preserve the non-initializing storage guarantee.
- Independent client codec configurations exchange typed requests and responses through real communication sessions, the retained application and actual SQLite persistence.

**Boundary:** Verification uses portable loopback transport connectivity. Native transport security remains independently tested. Competing client connections and interrupted response delivery are verified in 7B.3.3.

No changes to the generic communication infrastructure, workflow processing rules, state machine or database schema were required.

#### 7B.3.3 — Competing host clients

Verify simultaneous requests from independent authenticated client connections against one retained host application and SQLite persistence context.

**Gate:** Competing operations, identical retries and interrupted response delivery preserve the exact durable operation semantics established in 7B.3.1.

### 7C — Host state subscriptions and reconnection

**Goal:** The host distributes validated SDK application state to multiple clients.

- Reuse `WorkflowApplication.observe_state()` and the host-owned `publish()`/`watch()` context.
- Provide initial verified snapshot plus subsequent committed updates with no unreported startup gap.
- Define stream generation/ordering, bounded fan-out, cancellation, errors and reconnect re-synchronization.
- Keep transport representation extensible for future registered state slices.

**Gate:** Multiple independent client connections observe committed Start/Stop without manual refresh, including overlap with initial subscription and a reconnect after host restart.

### 7D — CLI and Explorer host-client cutover

**Goal:** Official frontend entry points all use the host as the sole workflow application/persistence owner.

- Route `./rudra workflow start|stop` through a host client adapter.
- Route Explorer **S/X** through the same client operations; use the host state stream for header/actions.
- Preserve physical input decoding, feature action registry, focused view models and stateless widgets.
- Serialize interactive input and observation-triggered renders to avoid redraw races.
- Cancel subscriptions and release connections on Q, EOF, interrupt, error and terminal restoration.
- Remove production frontend-local workflow SQLite/processor composition rather than retaining a hidden fallback.

**Gate:** Two independently running Explorers and a CLI command share one host, render committed changes correctly and never open workflow persistence in their own processes.

### 7E — Platform plugins, explicit installation and end-to-end verification

**Goal:** Finish the smallest usable macOS-managed service lifecycle through SDK-owned plugin and installation contracts, then prove the complete cross-process acceptance scenario without macOS-specific logic in the SDK host runtime.

- Define the **necessary** SDK host plugin/installation contribution contracts and registries, including duplicate/conflicting capability rejection, prerequisites, plan/inspect behavior, explicit execution and resource lifetime. Do not introduce a generalized installation engine beyond verified requirements.
- Implement a focused `packages/host/macos/lib/src/plugins/launchd/` capability; introduce other plugins (such as `power/`) only with a concrete use case, not merely to populate the proposed tree.
- Implement `packages/host/macos/lib/src/install/` as feature-owned installation steps, initially for the executable, required directories and per-user launchd configuration, reusing the launchd service manager rather than duplicating OS commands.
- Expose explicit install/verify/uninstall or configure actions through `apps/host` composition and the SDK-defined installation contract. Registration and `host.run()` must never install, enable, disable or remove services.
- Separate installed, enabled and running status. Explicitly document automatic login startup, disable/uninstall semantics, retained workflow data and partial installation failures; verify safe no-op/idempotent repeat behavior.
- Run multi-process concurrency, lifecycle, restart/reconnect, permission, terminal-restoration, install/verify/uninstall and missing-storage tests; test optional plugin/installer registration with synthetic SDK fixtures.
- Make service-unavailable and startup-conflict behavior explicit, and update architecture and usage docs only after verification evidence exists.

**Gate:** A deliberately configured macOS installation can run the two-terminal acceptance scenario; host restarts and client reconnects recover truthful state, no duplicate workflow commits occur, installer operations never modify workflow history, and the SDK host core remains portable. Native Windows/Linux support remains separately scoped.

## 7. Test architecture and acceptance checklist

Test at the feature's owning boundary. Prefer separate unit, contract, real-persistence integration and process-level tests. Do not expand generic terminal decoder tests for new workflow actions.

- **SDK host unit/contract:** Portable lifecycle orchestration, command routing, state fan-out, typed contracts, cancellation and fake capability adapters; tests cannot depend on macOS APIs.
- **`apps/host` composition:** OS detection, selected adapter/feature registrations, trusted runtime/persistence assembly, no native algorithms and clean disposal.
- **Communication (`packages/communication`):** Default construction, transport substitution, authenticated peers, native endpoint security, concurrent sessions, communication lifecycle and resource disposal.
- **Native host adapters (`packages/host/<platform>`):** Trusted identity, instance ownership, process lifecycle, native host capabilities and explicit service management.
- **Plugin/installation contracts:** Multiple independent contributions, duplicate ID/conflict rejection, no side effects on registration, explicit activation and release, inspectable install plans, repeated installation behavior, partial failures and data retention on uninstall.
- **SDK/persistence regression:** Existing state-machine replay, atomic commit, owner uniqueness, expected identity/version, idempotency, rejected/quarantined submission semantics and no publication on rollback.
- **Real host integration:** Two simultaneous Start requests with barriers (not timing sleeps), Start-vs-Stop races, committed change fan-out, failed commit silence and reconnect to verified journal state.
- **Actual process integration:** Separate host, CLI commands and at least two Explorer processes; process termination, competing host startup, socket permission/identity enforcement and no accidental frontend SQLite usage.
- **Explorer integration:** Initial verified display, external live Start/Stop, navigation-vs-notification ordering, stale displayed workflow ID guard, no phantom Active, terminal restoration and subscription cleanup on every exit path.
- **No-write checks:** Absent database stays absent after host/client construction, read, observe, navigation, Quit and Stop selection when no workflow exists. Explicit durable submissions may initialize persistence, including a Stop targeting a known workflow identifier whose absence must be durably recorded as a rejection.

At every completed slice, run formatting, affected tests, full `./rudra verify all`, `git diff --check`, and inspect the resulting commit. Do not mark a behavior implemented or green without the corresponding execution evidence.

## 8. Architectural safeguards and change-impact test

- **SDK first:** Domain semantics, transitions, reducers, journal validation, processing, application operations and portable host contracts/orchestration are implemented once in the SDK.
- **Explicit dependency direction:** `packages/host/<platform>` implements SDK host contracts; `packages/sdk` never imports concrete native host adapters. The SDK consumes `packages/communication`, which remains independent of the SDK, host application and persistence implementations.
- **Hierarchical ownership:** RudraHost constructs and owns Communication by default. Communication constructs and maintains its internal transport and session components. Explicit substitution remains available through contracts, and resource disposal is coordinated by the immediate resource owner.
- **Composition root:** `apps/host` selects and registers concrete adapters/plugins and constructs the configured SDK host, but contains neither native algorithms nor duplicate application/domain logic.
- **Feature-owned native extensions:** Communication infrastructure belongs to the independent communication package. Native host identity and ownership capabilities remain separate from optional `plugins/` and explicit `install/steps/`. New capabilities and installation steps should primarily add code and one registration.
- **No implicit host installation:** Registration, SDK construction, observation and `host.run()` do not install or configure OS services; install/uninstall actions are separate, explicit and auditable.
- **Portability by construction:** Adding Windows or Linux support should involve adapter implementations and composition registration, not edits to portable SDK host behavior.
- **One persistence owner:** Host composition owns SQLite and its notification channel; frontends use transport clients.
- **Feature isolation:** A future operation such as Pause primarily adds its domain feature, a host-exposed application operation/registration, its frontend feature contribution and isolated tests—not workflow branches throughout generic runners or transport decoders.
- **No premature framework:** Implement only contracts required for the local MVP. Avoid general-purpose RPC, event buses, entity repositories or a second application state hierarchy without concrete need.
- **No hidden policy:** The host coordinates application access and transport; it does not introduce business transition rules or weaken SDK persistence guards.
- **Safety first:** Client visibility never grants permission for cleanup. Destructive actions remain behind the independent authorization and execution gatekeeper.

## 9. Existing work retained and superseded plans

**Implemented baseline retained:** Epic 6A feature-owned Explorer action registration; Epic 6B immutable composite `RudraState`/`WorkflowSnapshot`, typed slices and state-machine replay; Epic 6C.1 `WorkflowApplication` operations; Epic 6C.2 post-commit publisher/subscriber, local observation, validated read-only restoration and associated tests.

**Plan superseded:** Epic 6's planned **6C.3 Explorer-only local observation wiring** is replaced by Epic 7's host-owned application/persistence model and eventual Explorer host-client integration. The earlier host design is promoted from *future direction* to the scope of this epic.

**Historical documents:** Preserve both Epic 6 Markdown files **unchanged** as records of earlier decisions and implementation status. Their prior “6C.3 planned” and “host deferred” statements are historical, not current execution instructions. For new host work, this Epic 7 plan takes precedence; ADR 0006 continues to govern domain and safety invariants. Epic 6's unrelated 6D–6F work remains separate and can be revisited after the host cutover as appropriate.

## 10. Working procedure and documentation rules

1. Inspect the latest pushed repository state before each slice; do not implement from stale examples.
2. Agree on public contract ownership, lifecycle and failure behavior before editing code.
3. Work collaboratively with exact file paths and focused BEFORE/AFTER changes by default. Produce bulk apply scripts or ZIPs **only when explicitly requested**.
4. Keep each slice coherent, independently testable and scoped to its responsibility; avoid arbitrary file-by-file micro-slices or broad rewrites.
5. Favor additive feature ownership and explicit composition over modifications to generic infrastructure. Break pre-release interfaces cleanly when required; do not add temporary compatibility machinery without a reason.
6. Write purposeful DartDocs for public types, constructors and methods: describe responsibility, parameters, return values, meaningful exceptions, ownership/lifetime and side effects where relevant. Avoid filler and documentation that only narrates syntax.
7. Keep SDK contract tests synthetic, component tests feature-local, persistence safety tests backed by real SQLite/Drift and cross-process guarantees proven with actual OS processes.
8. Verify locally, commit, push, then review the updated repository before calling a slice complete.

## 11. Open decisions to resolve within the relevant slice

These are **design checkpoints**, not permission to replace the agreed SDK-first ownership model:

- **7A:** Names/signatures of SDK host runtime, platform contracts and `apps/host` composition root; minimum registry/required-capability boundaries; macOS socket placement, exclusive ownership mechanism, trusted peer verification and explicit development launch command.
- **7B:** Minimal message envelope, protocol evolution, idempotency-key handling across lost responses and whether command handling is queued or otherwise safely serialized.
- **7C:** Host-stream generation/revision representation, bounded subscriber queues and registered serialization of future typed SDK state slices.
- **7D:** Reusable client interface location and Explorer's serialized input/observation event loop.
- **7E:** Plugin versus install-step contract shapes, registry/installation plan and failure semantics, concrete launchd service/install integration, packaging, restart policy, verification and treatment of unavailable/disabled hosts. A power plugin remains optional and requires an explicit need.

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

**Guiding acceptance criterion:** The SDK owns portable host behavior, capability contracts and extension registries; native packages under `packages/host/<platform>` implement independent platform features and installation steps; `apps/host` composes them and launches the configured SDK runtime. Independent frontends then share one trusted application/persistence owner and react to verified committed state. Neither registration nor `run()` implicitly installs operating-system services.
