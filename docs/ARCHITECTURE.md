
# Rudra — Software Architecture

Version: 1.3
Last updated: 2026-11-11
**Status:** Architectural baseline

## 1. Purpose

Rudra is a cross-platform, safety-first filesystem inspection and cleanup application.

Its primary purpose is to help users understand filesystem storage consumption, explore directories interactively, identify cleanup candidates, and make informed decisions about removing unnecessary data.

Rudra is not an autonomous disk cleaner.

The user remains the authority over what is selected, reviewed, approved, and ultimately removed.

The initial implementation targets macOS and provides a command-line interface with an interactive terminal wizard.

The architecture must support future Windows and Linux adapters, graphical applications built with Flutter, and reusable functionality through a pure-Dart SDK.

## 2. Foundational Principles

The following principles are architectural invariants.

### 2.1 User authority

Rudra must never autonomously decide to remove filesystem content.

Every cleanup candidate is explicitly selected by the user.

Every cleanup execution requires explicit approval of the complete cleanup plan.

The following actions never authorize filesystem deletion:

- Inspecting a file or directory.
- Navigating through the wizard.
- Marking an item for cleanup.
- Saving or pausing a session.
- Resuming a session.
- Cancelling a session.
- Generating a cleanup preview.

Marking an item expresses intent, not authorization to execute.

### 2.2 Read-only exploration

The entire interactive inspection wizard is a dry-run collection process.

During exploration, Rudra may:

- Inspect filesystem entries.
- Enumerate directory contents.
- Collect available metadata.
- Calculate or estimate storage consumption.
- Identify potentially unnecessary files.
- Explain risks associated with cleanup candidates.
- Record the user's cleanup selections.
- Persist wizard progress and inspection observations.

The wizard must not modify, move, truncate, or delete filesystem content.

Writing session state to Rudra's own persistence database is permitted and does not constitute cleanup of the inspected target.

### 2.3 Explicit execution boundary

Cleanup execution is architecturally separate from exploration and planning.

No filesystem mutation may occur until:

1. The user has completed the desired exploration.
2. A complete cleanup plan has been assembled.
3. Every candidate has been validated.
4. The complete plan has been presented for review.
5. The user has explicitly confirmed execution.

Rudra must never perform unattended, scheduled, inferred, or background cleanup.

Execution is limited to the explicitly approved plan.

### 2.4 Filesystem state verification

Filesystem state may change between inspection, selection, approval, and execution.

Rudra must not assume that a previously inspected path still references the same filesystem object.

Each cleanup candidate must be revalidated before execution.

If relevant filesystem state has changed, or cannot be reliably verified, the cleanup execution must be blocked.

The user must inspect the affected candidate again and explicitly approve the updated cleanup plan.

### 2.5 Fail-closed behavior

Uncertainty must not be interpreted as safety.

Missing metadata, inaccessible entries, changed identities, incomplete directory scans, unsupported safeguards, and unexpected errors must prevent unsafe cleanup.

Rudra must never silently skip validation or treat an incomplete scan as complete.

### 2.6 Platform independence

The core SDK must remain independent of:

- Command-line presentation.
- Terminal UI frameworks.
- Flutter widgets.
- Platform-specific filesystem implementations.
- SQLite implementation details.

Operating-system differences are isolated behind explicit contracts and adapters.

### 2.7 Auditable decisions

User decisions, relevant inspection observations, cleanup-plan changes, confirmations, and execution outcomes must be persistable as auditable events.

Rudra must distinguish between:

- What was discovered.
- What the user selected.
- What the user approved.
- What Rudra attempted.
- What actually happened.

These are different facts and must not be conflated.

## 3. Technology Stack

Rudra uses a Dart Pub Workspaces monorepo.

### 3.1 Core technologies

- Dart 3.6 or newer, subject to the workspace SDK constraint.
- Dart Pub Workspaces.
- Pure-Dart domain and SDK packages.
- A modular command-line application.
- Platform-specific filesystem adapters.
- SQLite for persistent sessions and audit records.
- `package:test` for automated testing.
- Flutter for future graphical applications.

### 3.2 Terminal interface

The initial product is CLI-first.

An interactive terminal wizard will provide directory exploration, inspection results, cleanup marking, review, and session navigation.

Nocterm is a leading candidate for the terminal UI framework, but its adoption is subject to prototype validation.

The SDK must not depend on Nocterm or another presentation framework.

### 3.3 Future graphical interfaces

Flutter applications must reuse the same SDK, inspection contracts, session orchestration, cleanup plans, and safety policies.

A graphical interface must not implement separate cleanup business rules.

All application interfaces must use the same domain-level approval and execution mechanisms.

## 4. Repository Structure

The repository is rooted at:

`~/projects/rudra`

The established package organization is:

    rudra/
      rudra
      pubspec.yaml

      apps/
        cli/
          bin/
            rudra.dart
          tool/
            rudra_dev.dart

      packages/
        sdk/
        targets/
          contracts/
          macos/
        persistence/
          sqlite/

      docs/
        ARCHITECTURE.md
        DEVELOPMENT.md
        decisions/

This describes the established architectural layout, not an exhaustive inventory of every implementation file.

### 4.1 rudra_cli

Responsible for:

- Production command registration.
- Development command registration.
- Command-line argument handling.
- Interactive wizard presentation.
- User input and confirmation.
- Presentation of inspection results.
- Translating application outcomes into process exit codes.

The CLI must not contain filesystem inspection algorithms, persistence rules, or cleanup safety policy.

The CLI is a consumer of the SDK.

The CLI uses a feature-first organization, governed by ADR 0005.

The production source structure is:

apps/cli/lib/
  rudra_cli.dart
  src/
    rudra_cli.dart
    composition/
      product_sdk_composition.dart
    core/
      cli/
        rudra_cli_module.dart
        rudra_exit_code.dart
      rendering/
        renderer.dart
        terminal_text.dart
        theme.dart
        bare/
          ansi_text.dart
          bare_widget_renderer.dart
        widgets/
          terminal_column.dart
          terminal_label.dart
          terminal_widget.dart
    features/
      about/
        about_cli_module.dart
        about_command.dart
      explorer/
        application/
          explorer_controller.dart
          explorer_model.dart
          explorer_runner.dart
        cli/
          explore_command.dart
          explorer_cli_module.dart
        terminal/
          dart_explorer_terminal_host.dart
          explorer_terminal_device.dart
          explorer_terminal_host.dart
          terminal_input.dart
        presentation/
          bare_explorer_renderer.dart
          explorer_presenter.dart
          explorer_view_model.dart
          widgets/
            explorer_screen.dart
            header/
              explorer_header.dart
              explorer_header_view_model.dart
            directory/
              explorer_directory.dart
              explorer_directory_view_model.dart
            footer/
              explorer_footer.dart
              explorer_footer_view_model.dart
      filesystem/
        cli/
          filesystem_cli_module.dart
          list_command.dart
        presentation/
          bare_filesystem_renderer.dart
          directory_listing_presenter.dart
          filesystem_view_model.dart
          widgets/
            directory_listing/
              directory_listing_view_model.dart
              directory_listing_widget.dart
            directory_inspection_issues/
              directory_inspection_issues_view_model.dart
              directory_inspection_issues_widget.dart
      welcome/
        application/
          welcome_controller.dart
          welcome_model.dart
        presentation/
          bare_welcome_renderer.dart
          welcome_presenter.dart
          welcome_view_model.dart
          widgets/
            welcome_screen.dart
            header/
              welcome_header.dart
              welcome_header_view_model.dart
            target/
              welcome_target.dart
              welcome_target_view_model.dart
            commands/
              welcome_commands.dart
              welcome_commands_view_model.dart
            footer/
              welcome_footer.dart
              welcome_footer_view_model.dart

Feature directories own their presentation and command implementations.

Core contains only reusable CLI infrastructure.

Application composition creates concrete dependencies and supplies
them to features.

The test directory mirrors feature ownership where useful.
Integration and development tooling tests remain separately organized.

The production entry point and public CLI API remain unchanged.

Development-only implementation files remain under `apps/cli/tool/`
and are excluded from the production entry point's dependency graph.

### 4.2 rudra_sdk

Responsible for:

- Inspection orchestration.
- Directory traversal.
- Storage aggregation.
- Scan boundaries.
- Session lifecycle rules.
- Wizard domain state.
- Cleanup candidate selection.
- Cleanup-plan construction.
- Conflict detection and resolution.
- Cleanup validation policy.
- Execution authorization policy.
- Coordination of explicit cleanup execution.

The SDK owns application behavior, not operating-system-specific filesystem operations.

### 4.3 rudra_target_contracts

Responsible for platform-independent filesystem inspection types and interfaces.

Current contracts include:

- `TargetPath`
- `FilesystemEntry`
- `FilesystemEntryKind`
- `FilesystemMetadata`
- `FilesystemPermissions`
- `FilesystemIdentity`
- `TargetCapabilities`
- `TargetCapabilityStatus`
- `TargetInspectionFeature`
- `TargetInspectionErrorCode`
- `TargetInspectionOperation`
- `TargetInspectionException`
- `TargetInspector`

The contracts package must remain independent of the CLI, SDK implementation, Flutter, and platform-specific adapters.

### 4.4 rudra_target_macos

Implements target contracts using macOS filesystem facilities.

The macOS adapter is responsible for translating native filesystem observations and errors into Rudra's platform-independent models.

It must not decide what the user should delete.

### 4.5 rudra_persistence_sqlite

Provides SQLite-backed persistence for domain state.

Its responsibilities will include:

- Session records.
- Wizard checkpoints.
- Cleanup selections.
- Inspection snapshots.
- Cleanup-plan revisions.
- User decisions.
- Validation results.
- Execution journals.
- Audit events.

SQLite must not become the owner of domain policy.

The SDK defines the rules; the persistence adapter stores and retrieves their state.

### 4.6 Dependency direction

The intended dependency direction is:

    CLI / Future Flutter UI
              |
              v
          Rudra SDK
          /       \
         v         v
    Target       Persistence
    contracts    contracts
         ^         ^
         |         |
    macOS adapter SQLite adapter

Concrete adapters are supplied through application composition.

Neither the SDK nor the target contracts may import CLI-specific types.

Persistence contracts will be introduced as needed rather than prematurely coupled to SQLite.

## 5. CLI Architecture

Rudra uses a modular `RudraCli` framework.

Commands are registered through `RudraCliModule`.

### 5.1 Module responsibilities

A module registers commands appropriate to a specific application composition.

Module registration must be explicit and deterministic.

Modules must not perform destructive filesystem operations as side effects of registration or construction.

### 5.2 Production and development separation

Production entrypoint:

`apps/cli/bin/rudra.dart`

Development entrypoint:

`apps/cli/tool/rudra_dev.dart`

Development tooling must not be exposed accidentally as production functionality.

### 5.3 Exit codes

`RudraExitCode` provides typed process exit outcomes.

Exit codes belong to the CLI application boundary.

Domain and filesystem inspection errors must remain independent of CLI exit codes.

### 5.4 Development commands

The root `./rudra` development launcher supports:

- `./rudra format`
- `./rudra analyze`
- `./rudra test`
- `./rudra check`
- `./rudra build`

`./rudra test` supports selective testing through the existing development command implementation.

`./rudra check` is the full repository verification command.

`./rudra build` builds and verifies the production executable.

### 5.5 CLI Presentation and Rendering Architecture

The CLI uses a lightweight, SDK-first presentation architecture.

Application behavior, presentation data preparation, and rendering
are separate responsibilities.

The established presentation flow is:

    CLI composition
         |
         v
    Controller / Command
         |
         v
    Public Rudra SDK
         |
         v
    Feature Presenter
         |
         v
    Immutable ViewModel
         |
         v
    Renderer<TViewModel>

Controllers and commands consume public SDK application services.

Presenters convert SDK observations and application state into
presentation-ready models.

ViewModels contain no filesystem services, native adapters,
terminal input, or renderer-specific escape sequences.

Renderers consume ViewModels and produce backend-specific output.

### 5.5.1 Rendering contract

The shared rendering contract is:

    Renderer<TViewModel>

It defines the operation:

    void render(TViewModel view_model);

Concrete implementations receive their dependencies through
application composition.

Controllers and commands must not instantiate concrete rendering
backends.

The initial backend is a bare terminal renderer.

Future backends may use Nocterm or another terminal UI framework.

Rendering backend selection is a CLI composition responsibility,
not an SDK responsibility.

### 5.5.2 Feature-specific presentation

CLI features own their presentation implementations.

A feature may contain commands, controllers, models, presenters,
view models, input handlers, and renderers depending on its needs.

A universal MVC hierarchy is not required.

Welcome uses application and presentation responsibilities under its
feature directory.

`WelcomeController` coordinates one read-only SDK listing request.
`WelcomeModel` preserves validated application state.

`WelcomePresenter` converts that state into `WelcomeViewModel`,
which composes independently owned header, target, command, and
footer presentation models alongside an optional `FilesystemViewModel`.

`WelcomeScreen` composes its visual components with the shared
`TerminalColumn` infrastructure and reuses `DirectoryListingWidget`
for filesystem entries.

`BareWelcomeRenderer` delegates main output to
`BareWidgetRenderer` and independently renders typed inspection
diagnostics using `DirectoryInspectionIssuesWidget`.

Welcome does not construct or nest a filesystem-specific renderer,
duplicate filesystem metadata formatting, or perform inspection
operations during presentation.

The filesystem feature owns reusable presentation components for
directory listings and inspection diagnostics.

`DirectoryListingPresenter` converts one SDK directory observation
into a `FilesystemViewModel`, which composes two independent
presentation models:

- `DirectoryListingViewModel` contains observed entry rows and
  directory-listing layout information.
- `DirectoryInspectionIssuesViewModel` contains inspection
  completeness and typed diagnostic information.

`FilesystemViewModel` validates that both components agree on
inspection completeness.

`DirectoryListingWidget` and `DirectoryInspectionIssuesWidget`
render their respective component models without invoking SDK
services or performing filesystem operations.

The `BareFilesystemRenderer` delegates rendering to these widgets
through the shared terminal rendering backend.

Welcome and Explorer reuse filesystem presentation without
duplicating SDK inspection or metadata-formatting logic.

Feature dependencies remain directional: Welcome and Explorer may
depend on filesystem presentation, but filesystem presentation
must not depend on either consuming feature.

Explorer owns transient navigation state and input decoding under
`features/explorer/`.

Explorer uses the public SDK for filesystem observations.

Explorer input decoding is not yet a general-purpose CLI terminal
input abstraction.

The CLI does not implement native filesystem inspection or shared
cleanup authorization rules.

### 5.5.3 Shared CLI infrastructure

Reusable CLI infrastructure resides under `core/`.

The CLI framework contracts and exit statuses reside in:

    core/cli/
      rudra_cli_module.dart
      rudra_exit_code.dart

Shared rendering infrastructure resides in:

    core/rendering/
      renderer.dart
      theme.dart
      terminal_text.dart
      bare/
        ansi_text.dart

The rendering infrastructure provides:

- A backend-independent `Renderer<TViewModel>` contract.
- Semantic styling roles and immutable theme definitions.
- Sanitization of untrusted terminal text.
- Approximate Unicode column measurement.
- Low-level ANSI encoding for the bare backend.

Concrete feature renderers do not belong in core.

Core must not import feature implementations, application
composition, or concrete filesystem target adapters.

The shared terminal text utility approximates display widths.
It does not guarantee complete Unicode grapheme-cluster or
terminal-specific layout correctness.

### 5.5.4 Renderer and SDK composition

`RudraCli.product()` selects the supported SDK composition,
constructs concrete renderers, and assembles production features.

Feature controllers and commands receive their dependencies
through explicit constructor injection.

`WelcomeController` receives a nullable SDK and starting directory,
plus an injected `Renderer<WelcomeViewModel>`.

The SDK and starting directory must either both be present
or both be absent.

Their absence represents an unsupported inspection target.

`ListCommand` receives the configured SDK, starting directory,
and `Renderer<FilesystemViewModel>`.

`FilesystemCliModule` supplies its injected dependencies to
its registered commands.

The Explorer feature is registered through `ExplorerCliModule`.

`ExploreCommand` accepts an optional target-native directory and
delegates execution to an injected `ExplorerRunner` factory.

`RudraCli.product()` constructs Explorer dependencies lazily,
only when the explore command executes.

The Explorer composition contains:

- `ExplorerController` configured with the public Rudra SDK.
- `ExplorerRunner` coordinating read-only navigation.
- `ExplorerPresenter` preparing immutable view models.
- `BareExplorerRenderer` using the ANSI terminal backend.
- `DartExplorerTerminalHost` managing terminal lifecycle.

The terminal host supplies the interactive output destination.
The renderer uses that same destination for screen updates.

Explorer-specific terminal infrastructure remains inside
features/explorer/ under ADR 0005.

The production command is:

    `rudra explore [absolute-directory]`

The existing no-argument welcome workflow and rudra ls output
contracts remain unchanged.

The development launcher continues to use the repository root
as its working directory.

`BareWelcomeRenderer` renders the composable `WelcomeScreen`
through the shared `BareWidgetRenderer`.

`WelcomeScreen` directly composes `DirectoryListingWidget`
when an SDK filesystem observation is available.

Typed inspection diagnostics are independently rendered through
`DirectoryInspectionIssuesWidget` to the configured diagnostic
output sink.

Welcome does not construct `BareFilesystemRenderer` or duplicate
filesystem listing formatting.

Controllers and commands must not construct concrete rendering
backends or terminal styling encoders.

Features must not import `ProductSdkComposition`.

Application composition owns concrete adapter selection and
injection. Features use the public SDK and CLI rendering contracts.

No CLI presentation component may bypass SDK safety policy or
independently authorize destructive filesystem operations.

### 5.5.5 Filesystem presentation guarantees

Filesystem presentation is derived from SDK observations.

The CLI must not independently inspect the filesystem to prepare
display data.

The compact `rudra ls` layout preserves:

- The TYPE, LOGICAL_BYTES, PATH column order.
- SDK observation ordering.
- Explicit unknown metadata.
- Target-native path spelling.

The detailed layout preserves:

- Directory-first presentation ordering.
- Human-readable entry kinds and logical sizes.
- Observed permissions and modification timestamps.
- Explicit incomplete-inspection warnings.

Typed inspection issues remain visible through diagnostic output.

No renderer may interpret an incomplete observation as complete.

No displayed filesystem metadata constitutes cleanup authorization.

### 5.5.6 Terminal safety

Untrusted filesystem names, paths, and inspection diagnostics must
be sanitized before terminal styling is introduced.

Rendering infrastructure must prevent untrusted control sequences
from becoming executable terminal instructions.

ANSI styling is disabled by default.

Terminal capability detection belongs to the terminal host or
application composition boundary.

The initial interactive Explorer is implemented using the
bare terminal rendering backend.

TerminalInput converts raw input bytes into navigation actions.

ExplorerRunner coordinates keyboard events, SDK-backed navigation,
presentation updates, viewport scrolling, and interaction exit
status.

DartExplorerTerminalHost manages terminal input modes, alternate
screen activation, cursor visibility, input subscriptions, signal
forwarding, and terminal restoration.

The host uses an injectable ExplorerTerminalDevice contract,
allowing lifecycle and failure behavior to be tested without
modifying the actual terminal.

Interactive Explorer requires compatible terminal input and output.
Unsupported or initially undersized terminals are rejected before
filesystem inspection begins.

The initial directory is inspected before interactive terminal
modes are enabled.

Later navigation inspections are executed sequentially within
the guarded terminal lifecycle.

All filesystem observations pass through RudraSdk.filesystem.

The initial Explorer supports:

- Up and down navigation.
- Opening observed directories.
- Returning through navigation history.
- Read-only inspection of immediate directory children.
- Selection and viewport scrolling.
- Incomplete-inspection warnings.
- Controlled quitting and input EOF.
- Restoration after catchable interaction failures.

Symbolic links and regular files are not opened by Explorer.

Filesystem observations are not atomic snapshots. The interactive
Explorer does not establish cleanup authorization or secure
session-root containment.

The SDK does not yet support cancellation of an in-progress
directory listing.

Persistent inspection sessions, cleanup planning, final review,
revalidation, and execution remain future implementation work.

This completes the first interactive Explorer integration for
Block 4C.2 without changing the SDK-first architecture.

### 5.5.7 Testing boundaries

Tests must independently verify:

- Presenter transformations.
- ViewModel invariants and immutable collections.
- Exact established output formats.
- Theme and ANSI encoding behavior.
- Sanitization of untrusted terminal text.
- Typed incomplete-inspection diagnostics.
- Renderer dependency injection.
- SDK request counts and read-only behavior.

Integration tests must verify that application controllers and
commands consume SDK services without duplicating filesystem
inspection logic.

Obsolete compatibility rendering adapters must not be retained
after callers have migrated.

This architecture implements the frontend separation established
by ADR 0004 without changing SDK domain responsibilities.

## 6. TargetInspector Architecture

`TargetInspector` defines read-only observations against one target environment.

The initial interface contains four operations:

    Future<TargetCapabilities> capabilities_for(
      TargetPath path,
    );

    Future<FilesystemEntry> inspect(
      TargetPath path,
    );

    Stream<TargetPath> list_directory(
      TargetPath path,
    );

    Future<TargetPath> read_symbolic_link(
      TargetPath path,
    );

### 6.1 Inspection responsibilities

An adapter may:

- Inspect one filesystem entry.
- Enumerate immediate directory children.
- Read the stored destination of a symbolic link.
- Report available capabilities.
- Translate platform-native errors.

An adapter must not:

- Recursively traverse directories on behalf of the SDK.
- Make cleanup decisions.
- Execute cleanup operations.
- Implicitly follow a final symbolic link.
- Conceal inspection failures.
- Modify filesystem contents.

### 6.2 Directory enumeration

Directory enumeration streams immediate child paths.

The SDK determines how and when to inspect each discovered entry.

Enumeration is:

- Lazy.
- Single-subscription.
- Non-recursive.
- Unordered.
- Cancelable.
- Explicit about terminal failures.

An enumeration failure must not be represented as successful completion.

Successfully emitted paths may be retained as partial observations, but the scan remains incomplete.

### 6.3 Filesystem entries

Filesystem entry kinds include:

- Regular files.
- Directories.
- Symbolic links.
- Other special filesystem entries.

Metadata is observational and may be incomplete.

Unknown metadata must be represented explicitly.

### 6.4 Storage accounting

Logical file size, allocated storage, aggregate directory size, and estimated recoverable storage are distinct concepts.

Rudra must not present allocated bytes or logical bytes as guaranteed recoverable space.

Storage calculations must consider, where applicable:

- Hard links.
- Sparse files.
- Filesystem clones.
- Compression.
- Filesystem snapshots.
- Shared allocation.
- Incomplete observations.

The SDK owns aggregation and estimation.

### 6.5 Filesystem identity

`FilesystemIdentity` represents an object using an opaque filesystem identifier and entry identifier.

Identities are compared only within the same target and inspection context.

No cross-target identity comparison or cross-target scan aggregation is permitted within a session.

Filesystem identifiers must not be treated as permanent authorization credentials.

The persistence and execution layers must account for identity reuse and stale observations.

### 6.6 Symbolic links

Symbolic links are inspected as links, not as their destinations.

Reading a symbolic link returns its stored target without resolving it.

A dangling symbolic link remains an inspectable filesystem entry.

The SDK must not automatically traverse symbolic links during directory exploration.

Intermediate path components and filesystem mount boundaries require separate safety consideration.

### 6.7 Inspection errors

Platform-specific failures are translated into typed `TargetInspectionException` instances.

Programmatic behavior must use typed error codes rather than parsing diagnostic messages.

Incomplete inspection, unknown metadata, and operation failure must remain distinguishable.

## 7. Persistent Inspection Sessions

Rudra is a stateful application.

An inspection session represents one user's ongoing exploration, decisions, and cleanup planning.

A session is associated with exactly one originally selected root location and one target environment.

### 7.1 Single unfinished session invariant

Rudra permits only one unfinished inspection session per Rudra user profile.

A user cannot start an independent second session while an unfinished session exists.

This rule applies across CLI invocations and survives application restarts.

A session may be unfinished while paused, awaiting review, or awaiting cleanup execution.

It does not need to have an actively running process.

### 7.2 Original root is immutable

The selected root location is established when the session is created.

The session's root must not change during its lifetime.

Resuming a session always restores its original root.

A new command-line path must not silently replace that root.

### 7.3 Starting Rudra with an existing session

Suppose a user starts a session at:

`/Users/Application Support`

Later, the user invokes Rudra with:

`/Users/Downloads`

Rudra must detect the existing unfinished session before creating another.

It must offer these decisions:

1. Continue the existing session at its original root.
2. Cancel the existing session and proceed with the newly requested location.

Continuing resumes the saved wizard and preserves all existing selections.

Cancelling terminates the old session without deleting any filesystem content.

Starting the new session occurs only after explicit cancellation.

The original session and its historical audit records remain available.

The same rule applies when reopening Rudra without specifying a new target.

### 7.4 Session lifecycle

The conceptual lifecycle includes:

- Created.
- Active.
- Paused.
- Awaiting review.
- Awaiting final confirmation.
- Blocked pending revalidation or review.
- Executing an approved cleanup.
- Completed.
- Cancelled.
- Interrupted execution requiring reconciliation.

The exact persistence state-machine representation will be formalized during SDK session implementation.

Completed and cancelled sessions are terminal.

An interrupted execution must not be silently restarted.

### 7.5 Session state

A persistent session must retain sufficient information to restore:

- Original root.
- Target binding.
- Lifecycle status.
- Current wizard step.
- Navigation position.
- Relevant inspection observations.
- Marked cleanup candidates.
- User decisions.
- Cleanup-plan revision.
- Relevant validation status.
- Relevant audit events.

Presentation-specific information must be separated from domain decisions.

A future Flutter client must be able to resume the same domain workflow without depending on CLI-specific screen state.

### 7.6 Concurrent invocations

Multiple Rudra processes must not be permitted to mutate the same session state concurrently.

Persistent session uniqueness and active process ownership are separate concerns.

SQLite transactions must enforce relevant persistent invariants.

Process coordination must handle stale ownership caused by crashes or abrupt termination.

Reclaiming a stale process lock must never imply authorization to resume destructive execution.

## 8. Interactive Wizard

The interactive wizard is the primary workflow for inspecting and selecting cleanup candidates.

It is strictly read-only with respect to the inspected filesystem.

### 8.1 Exploration

The user can navigate through directories, inspect entries, and review available storage information.

The wizard should explain:

- What an entry appears to contain.
- Why it may consume substantial space.
- Whether it appears potentially disposable.
- Risks associated with removing it.
- Limitations or uncertainties in the inspection.

Rudra must distinguish verified facts from heuristics and estimates.

### 8.2 Marking candidates

The user may mark an item for potential cleanup.

A mark records a proposed action in the session.

It does not delete anything.

The user may unmark or revisit a candidate before final approval.

Each candidate must retain enough information to identify the item and establish the state on which the decision was based.

### 8.3 Global cleanup list

Selections made throughout the wizard contribute to one session-wide cleanup plan.

The global cleanup list must support:

- Viewing all selected candidates.
- Revisiting individual selections.
- Removing candidates from the plan.
- Displaying available size estimates.
- Explaining known risks.
- Detecting overlapping selections.
- Resolving conflicts before approval.

Marking both a parent directory and an item inside it must not result in double-counted reclaim estimates or duplicate deletion operations.

### 8.4 Wizard persistence

Navigation, marking, unmarking, and review progress must be persistable.

The user can pause or exit the wizard without losing the cleanup plan.

Restoring a session must not implicitly execute the pending cleanup.

Previous observations are potentially stale and must be treated accordingly.

### 8.5 Separation of presentation and domain state

The wizard's visual implementation does not own cleanup authority.

The SDK maintains the authoritative domain state.

The terminal interface presents state and passes explicit user decisions to the SDK.

Nocterm or Flutter must not introduce separate cleanup authorization rules.

## 9. CleanupPlan Architecture

`CleanupPlan` is a conceptual domain model representing the user's collection of proposed cleanup actions.

Its implementation belongs in the SDK.

The plan is not an executable script.

### 9.1 Candidate observations

Each selected candidate must retain sufficient baseline evidence from the selection or subsequent explicit review.

Relevant evidence may include:

- Target binding.
- Original path.
- Filesystem entry kind.
- Available filesystem identity.
- Logical and allocated size observations.
- Relevant timestamps.
- Symbolic-link destination where applicable.
- Relevant permission observations.
- Directory membership or subtree evidence.
- Inspection completeness.
- Selection and review timestamps.
- Plan revision.

The exact schema is deferred to the session and cleanup-plan implementation.

### 9.2 Directory selections

A directory selection must not automatically authorize deletion of files introduced after the selection.

Rudra must have sufficient evidence of the selected directory's relevant contents and state to determine whether its cleanup scope has changed.

A directory's own metadata is insufficient to prove that its subtree remains unchanged.

If the required evidence is incomplete or unavailable, the candidate cannot be approved for execution until a sufficient current review is performed.

### 9.3 Plan revisions

Marking, unmarking, changing scope, or reapproving altered candidates changes the cleanup plan.

Final approval must be bound to a specific, immutable plan revision.

Changing the approved plan invalidates the prior execution approval.

### 9.4 Planning and authorization

The following must remain separate:

1. A candidate was marked.
2. A candidate was inspected and validated.
3. The complete plan was approved.
4. An operation was attempted.
5. An operation succeeded or failed.

Neither prior selection nor prior validation is sufficient to execute a changed plan.

## 10. Pre-Execution Verification

Rudra must perform a complete pre-execution validation before performing any destructive operation.

### 10.1 Global preflight barrier

All candidates must pass preflight validation before cleanup execution begins.

If any candidate has changed, is missing required evidence, or cannot be verified, the entire cleanup execution must remain blocked.

Rudra must not begin deleting other candidates while unresolved preflight failures remain.

### 10.2 Detecting changes

Relevant changes include, but are not limited to:

- A path now refers to a different filesystem object.
- Filesystem identity has changed.
- Entry type has changed.
- A file has been modified or replaced.
- A symbolic-link destination has changed.
- Directory contents have been added, removed, or replaced.
- Required metadata is missing or contradictory.
- The target filesystem has become unavailable.
- Inspection cannot be completed.
- A filesystem boundary or relevant access condition has changed.

The exact comparison rules must be conservative and documented.

Timestamps or textual path comparisons alone are insufficient to establish object identity.

### 10.3 User notification

When a relevant change is detected, Rudra must:

1. Stop before cleanup execution.
2. Present the originally selected candidate.
3. Present the current observation.
4. Explain detected differences.
5. Identify unavailable or unverifiable information.
6. Return the affected candidate to review.
7. Require explicit renewed approval.

The message must clearly communicate that the filesystem has changed since the original selection.

Rudra must not silently update the selection and continue.

### 10.4 Reapproval

Reapproval is an explicit user decision.

It must refer to the newly inspected state, not the original stale observation.

Once all affected candidates have been reviewed, Rudra must present the complete updated plan again.

The user must explicitly confirm that complete plan before execution can begin.

### 10.5 Unknown state

If Rudra cannot establish whether a candidate is unchanged, it must treat the candidate as unverified.

Unknown is not equivalent to unchanged.

A candidate without sufficient verification evidence must not be deleted.

## 11. Cleanup Execution

Cleanup execution is a separate, explicitly authorized workflow.

The execution component must not be part of `TargetInspector`.

### 11.1 Execution prerequisites

Execution requires:

- An existing cleanup plan.
- A fully validated current plan revision.
- No unresolved selection conflicts.
- No unresolved filesystem changes.
- No unverified required candidates.
- Explicit user confirmation of the complete plan.
- An available platform execution mechanism capable of enforcing required safety guarantees.

### 11.2 Revalidation at the operation boundary

A successful global preflight does not eliminate the possibility of subsequent filesystem changes.

Immediately before each destructive operation, the executor must verify that it is operating on the approved object.

Path replacement, identity changes, newly introduced contents, or unavailable safeguards must block the affected operation.

Where necessary, platform-supported object handles and directory-relative operations must be used to avoid unsafe path-based check-then-act behavior.

A simple inspect-then-delete sequence is not automatically race-safe.

If required safeguards cannot be provided, the operation must not execute.

### 11.3 No inherited authorization

Approval never automatically transfers to:

- A replacement file at the same path.
- A newly created directory child.
- A changed symbolic-link destination.
- A different filesystem object with similar metadata.
- Another session.
- A revised cleanup plan.

### 11.4 Execution failures

Cleanup is not assumed to be atomic across multiple filesystem operations.

Rudra must persist per-operation outcomes and support accurate reporting of partial execution.

If execution is interrupted, the application must not claim completion.

Automatic restart or continuation of interrupted destructive operations is prohibited.

Recovery requires reconciliation and an explicit user decision, with fresh validation and authorization before further cleanup.

### 11.5 Session cancellation

Cancelling an inspection session only changes session state.

It must not invoke cleanup execution.

Cancelling a session and cancelling an in-progress execution are separate concerns and require separate domain semantics.

The execution-cancellation model will be formalized before destructive functionality is implemented.

## 12. Persistence and Audit Architecture

SQLite is the initial persistence implementation.

The domain model must remain independent of SQL.

### 12.1 Persistence responsibilities

Persistence must support:

- Durable session creation and lifecycle transitions.
- Restoration of wizard progress.
- Cleanup candidate selection history.
- Inspection baselines.
- Cleanup-plan revisions.
- Validation outcomes.
- Explicit approval records.
- Execution attempts and results.
- Recovery and interruption information.

### 12.2 Transactional consistency

Session transitions and their associated audit events must be persisted consistently.

A session must not appear approved if its corresponding approval event or plan revision was not durably recorded.

Concurrent processes must not be able to create conflicting active session states.

### 12.3 Audit history

Audit history must preserve the distinction between user intent and actual filesystem effects.

At minimum, execution history must identify which candidate was involved, the approved plan revision, validation result, attempted action, and observed outcome.

Audit records must not claim successful deletion when an operation was skipped, interrupted, or failed.

Sensitive filesystem paths and metadata must be handled carefully in diagnostics and exported records.

### 12.4 Recovery

On startup, Rudra must detect unfinished sessions and unresolved execution states.

Session restoration may resume the dry-run wizard.

An interrupted destructive execution must never resume automatically.

Recovery must reconcile the persisted journal with current filesystem observations before any further user-authorized cleanup.

## 13. Target and Scan Boundaries

A session has one immutable original root.

A scan must not silently change that root or start inspecting an unrelated target.

The SDK owns traversal scope.

### 13.1 Path semantics

Target paths are interpreted according to the target operating system.

Textual path-prefix checks are insufficient to enforce filesystem containment.

The design must account for path normalization differences, symbolic links in intermediate components, mount points, and concurrent filesystem changes.

### 13.2 Symbolic-link boundaries

Recursive inspection must not automatically follow symbolic links.

The presence of a symbolic link must not expand the cleanup scope.

### 13.3 Mounted filesystems

Filesystem mount boundaries are distinct from session boundaries.

The detailed policy for crossing mounted filesystems remains a separate architectural decision.

Until a safe policy and enforcement mechanism exist, the scanner must not silently expand its approved scope into another filesystem.

### 13.4 Target isolation

A session must not combine cleanup candidates from unrelated target environments.

Filesystem identity comparisons and cleanup authorization remain scoped to the session's target.

## 14. Testing Architecture

Rudra uses layered testing.

### 14.1 Contract tests

Pure-Dart contracts must be tested without native filesystem dependencies.

Tests verify:

- Model invariants.
- Typed errors.
- Missing metadata.
- Identity semantics.
- Capability semantics.
- Directory enumeration contracts.
- Symbolic-link behavior.
- Stream cancellation.
- Partial enumeration failures.

### 14.2 Conformance tests

A shared `TargetInspector` conformance test suite verifies behavior against known fixture layouts.

In-memory tests demonstrate contract usability.

Concrete target adapters must run their own conformance and native integration tests.

An in-memory fixture does not prove that a native adapter is safe.

### 14.3 SDK tests

SDK tests must cover:

- Traversal and aggregation.
- Session lifecycle.
- Single unfinished session enforcement.
- Wizard resume and progress restoration.
- Marking and unmarking.
- Cleanup-plan revisions.
- Overlapping selections.
- Validation failures.
- Changed filesystem observations.
- Approval invalidation.
- Recovery and interruption behavior.

### 14.4 Destructive-operation tests

Future destructive-operation tests must use tightly controlled, disposable fixtures.

They must never target arbitrary user directories or developer machine caches.

Tests must prove that mutation cannot occur without explicit authorization and required validation.

Fault injection must cover races, missing objects, changed identities, partial failures, and interrupted execution.

## 15. Documentation and Decision Records

This document defines Rudra's architectural baseline.

`docs/DEVELOPMENT.md` defines implementation, testing, documentation, and verification standards.

Architectural Decision Records live under:

`docs/decisions/`

Significant architectural choices must be documented with their context, alternatives, consequences, and current status.

An architectural rule must not be silently changed through a local implementation convenience.

## 16. Current Implementation Status

**Status date:** 2026-11-11

### 16.1 Implemented foundations

The repository contains:

- Dart Pub Workspaces monorepo.
- Modular CLI framework and explicit module registration.
- Separate production and development CLI entry points.
- Typed application exit codes.
- Workspace formatting, analysis, testing, and build commands.
- Platform-independent target contracts.
- macOS native target inspection adapter.
- Pure-Dart Rudra SDK.
- SDK-backed directory listing.
- Production SDK and target-adapter composition.
- Read-only `rudra ls` command.
- SDK-backed welcome workflow.
- Feature-specific presenters and immutable view models.
- Generic CLI rendering contract.
- Bare terminal renderers.
- Terminal text sanitization and semantic styling.
- In-memory Explorer navigation controller and model.
- Explorer keyboard-input decoder.

### 16.2 CLI architecture

ADR 0004 establishes the SDK-first application architecture.

ADR 0005 establishes the feature-first CLI organization.

CLI features reside under `apps/cli/lib/src/features/`.

Reusable CLI infrastructure resides under `apps/cli/lib/src/core/`.

Production SDK and target-adapter assembly remains in the
application composition layer.

The welcome, filesystem, and Explorer implementations consume
public SDK services rather than accessing concrete target adapters
directly.

Explorer navigation is transient and read-only. It does not create
or modify a persistent Rudra session.

### 16.3 Verification

The feature-first restructuring requires verification against
the full repository test and analysis workflow.

The final migration baseline is established only after:

    ./rudra format
    ./rudra check --package rudra_cli
    ./rudra check
    git diff --check

Previous test results do not establish that the restructuring
passes verification.

### 16.4 Not yet implemented

The following remain future development work:

- Complete interactive Explorer terminal hosting.
- Integration of keyboard input with Explorer navigation.
- Persistent inspection session lifecycle implementation.
- SQLite-backed session and audit repositories.
- Persistent dry-run cleanup candidate selection.
- Cleanup-plan orchestration.
- Pre-execution revalidation and authorization.
- Destructive cleanup execution.
- Windows and Linux target adapters.
- Flutter desktop and mobile frontends.

The current read-only inspection implementation does not provide
cleanup execution capabilities.

The safety requirements in this document remain binding on all
future implementations.

## 17. Deferred Decisions

The following require further design work before implementation:

- Final terminal UI framework selection.
- Concrete persistent session schema.
- Process ownership and stale-lock recovery.
- Exact candidate snapshot representation.
- Directory subtree fingerprinting strategy.
- Precise cleanup-plan conflict policy.
- Per-platform safe mutation mechanisms.
- Mount-boundary traversal policy.
- Execution cancellation and recovery model.
- Audit retention and export policy.
- Future Windows and Linux implementations.
- Future Flutter application composition.

Deferred decisions must not weaken the foundational safety invariants.

## 18. Architectural Acceptance Criteria

Rudra's architecture is compliant only when the following remain true:

1. Exploration cannot execute cleanup.
2. Marking a candidate cannot execute cleanup.
3. A session has one immutable original root.
4. Only one unfinished session exists per Rudra user profile.
5. A new invocation cannot silently replace an unfinished session.
6. Session decisions and wizard progress can survive restarts.
7. The SDK remains independent of CLI and Flutter presentation.
8. Target inspection remains separate from cleanup execution.
9. Cleanup requires explicit approval of a complete plan.
10. Every candidate is revalidated before execution.
11. Changed or unverifiable candidates block global preflight.
12. A changed plan requires renewed review and confirmation.
13. Runtime object changes cannot inherit previous approval.
14. Interrupted execution cannot restart automatically.
15. Actual execution results are distinguished from intentions.
16. No unsupported safety guarantee is silently assumed.

These invariants take precedence over convenience, performance optimization, and implementation simplicity.
