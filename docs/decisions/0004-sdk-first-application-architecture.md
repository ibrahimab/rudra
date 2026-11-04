
# ADR 0004 — SDK-First Application Architecture

**Date:** 2026-11-04
**Status:** Accepted
**Implementation:** Incremental

## 1. Context

Rudra is a cross-platform filesystem inspection and cleanup product.

The initial implementation uses a command-line application, but the
product must also support future desktop, mobile, and other interfaces.

Rudra's SDK must be the shared application core rather than a collection
of utilities built specifically for the CLI.

All interfaces must consume the same domain functionality and enforce
the same safety requirements.

## 2. Decision

Rudra SHALL follow an SDK-first architecture.

The SDK owns application functionality, domain services, workflows,
and business rules.

Frontends consume public SDK interfaces and implement their own
presentation, input handling, navigation, and platform-specific UI.

The CLI is the first frontend, not the owner of Rudra's application
logic.

### 2.1 SDK Responsibilities

The SDK SHALL own shared functionality including:

- Filesystem exploration orchestration.
- Storage accounting and aggregation.
- Persistent session lifecycle rules.
- Cleanup candidate selection and planning.
- Cleanup validation and authorization policy.
- Domain models, typed results, and domain errors.
- Application-level services consumed by frontends.

Functionality required by multiple frontends must not be duplicated
inside their presentation layers.

The SDK must remain independent of CLI frameworks, Flutter,
platform-specific filesystem implementations, and SQLite.

### 2.2 Public SDK API

The SDK SHALL expose discoverable, strongly typed application services.

Conceptual service areas include:

- Sessions
- Exploration
- Storage
- Cleanup planning
- Validation

For example, a frontend may request the current session or list
existing sessions through an SDK session service.

The exact class names, method signatures, and facade structure are
deferred until the corresponding services are implemented.

Global mutable singleton state is not required or assumed.

Services should support dependency injection and isolated testing.

### 2.3 Frontend Responsibilities

Frontends own:

- User interaction.
- Presentation models.
- Views and rendering.
- Controllers and input handling.
- Navigation.
- Platform-specific UI behavior.
- Translating domain results into user-facing information.

The CLI SHALL use a lightweight MVC-oriented presentation architecture
for interactive workflows.

MVC is a frontend implementation concern. The SDK must not depend
on CLI-specific models, controllers, or views.

Not every command requires a full interactive MVC screen.

### 2.4 Application Composition

Application entry points SHALL assemble the dependencies required
by their frontend.

The SDK consumes platform-independent contracts.

Concrete filesystem and persistence adapters are supplied through
application composition.

The SDK must not instantiate platform-specific adapters directly.

A frontend should normally access filesystem functionality through
SDK application services, not implement its own domain workflows
using TargetInspector.

Application bootstrapping may supply concrete adapters to the SDK.

### 2.5 Dependency Direction

The intended dependency direction is:

    CLI / Desktop / Mobile / Other Frontends
                     |
                     v
                 Rudra SDK
                     |
                     v
            Domain and Target Contracts
                     ^
                     |
       Concrete Platform / Persistence Adapters

Concrete adapters implement contracts and are injected at
composition boundaries.

The SDK must not import its concrete adapters.

Dependencies must not point from SDK domain logic into frontend
presentation implementations.

### 2.6 Session Management

Session lifecycle policy belongs exclusively to the SDK.

The SDK SHALL enforce the established single-unfinished-session
invariant and immutable original session root.

Frontends may present session information and collect decisions
but must not independently implement session lifecycle rules.

The persistence adapter stores session state according to SDK-defined
contracts and invariants.

Session inspection, resumption, cancellation, and cleanup execution
authorization remain distinct operations.

### 2.7 Safety Boundaries

All filesystem inspection workflows remain read-only.

The SDK owns cleanup selection, validation, and authorization policy.

Frontends must not bypass SDK safety rules or invoke destructive
filesystem operations independently.

Marking cleanup candidates does not authorize execution.

Cleanup requires the separately confirmed plan and revalidation
requirements established by ADR 0003.

These requirements apply equally to every frontend.

## 3. CLI Architecture

The existing modular RudraCli framework SHALL be preserved.

The CLI remains responsible for:

- Command registration and dispatch.
- Argument parsing.
- Terminal input and output.
- Interactive presentation through MVC.
- Navigation and application UI lifecycle.
- Mapping domain outcomes to CLI exit codes.

CLI commands act as consumers of SDK services.

For example, a SessionCommand may obtain session information
from an SDK session service and pass the returned domain data
to a CLI view.

The command must not implement session storage or lifecycle policy.

The terminal host and MVC contracts will be developed incrementally.

The exact MVC interfaces and navigation mechanisms are deferred
until their responsibilities have been established.

## 4. Alternatives Considered

### CLI-centric application architecture

Rejected because it would make future frontends dependent on
CLI-owned application behavior or require duplicated functionality.

### Shared UI framework in the SDK

Rejected because terminal interfaces and Flutter applications have
different presentation and lifecycle requirements.

The SDK should expose application capabilities, not UI frameworks.

### Direct adapter usage from every frontend

Rejected as the primary application architecture.

Such an approach would encourage duplication of exploration
algorithms, session rules, and safety policy.

Concrete adapters are integrated through application composition
and consumed through shared SDK services.

### Universal MVC framework for all frontends

Rejected.

Different frontends may use different presentation patterns.
Only reusable application behavior belongs in the SDK.

## 5. Consequences

### Benefits

- One shared implementation of Rudra's domain behavior.
- Consistent safety rules across interfaces.
- Independently testable SDK services.
- Replaceable target and persistence adapters.
- Freedom to evolve CLI and Flutter presentation separately.
- No requirement to rewrite domain workflows for new frontends.

### Costs

- Requires explicit SDK service boundaries.
- Requires application dependency composition.
- Requires typed interfaces between frontends and the SDK.
- Adds some initial structure before the first interactive CLI flow.

These costs are accepted.

## 6. Implementation Strategy

Development SHALL proceed incrementally.

The next milestone will establish the first production CLI
workflow while preserving the SDK-first dependency model.

The initial sequence is:

1. Design minimal SDK consumption and application composition.
2. Establish lightweight CLI MVC contracts.
3. Introduce terminal interaction and navigation.
4. Implement the first production welcome screen.
5. Connect the CLI to existing filesystem inspection capabilities
   through the appropriate SDK boundary.
6. Verify the resulting end-to-end read-only workflow.

Do not introduce unneeded SDK services merely to complete
an architectural diagram.

Do not prematurely implement SQLite persistence, cleanup
execution, or other unrelated domain features.

## 7. Verification Requirements

Tests SHALL verify that:

- SDK services do not depend on frontend implementations.
- CLI controllers and commands can consume injected services.
- Views can be tested independently from filesystem adapters.
- Platform-specific adapters remain outside the pure-Dart SDK.
- Frontends do not duplicate cleanup authorization policy.
- Exploration and navigation do not mutate inspected files.
- Existing production and development CLI separation remains intact.

All changes must follow docs/DEVELOPMENT.md and pass the
repository's verification workflow.

## 8. Related Decisions

- docs/ARCHITECTURE.md
- docs/DEVELOPMENT.md
- docs/decisions/0001-modular-cli.md
- docs/decisions/0002-persistent-single-session.md
- docs/decisions/0003-dry-run-cleanup-and-revalidation.md

## 9. Current Implementation Status

The repository already contains:

- The modular CLI command framework.
- The pure-Dart SDK package.
- Platform-independent target contracts.
- The macOS TargetInspector implementation.
- Shared contract and native adapter tests.

SDK application services, interactive CLI MVC, navigation,
session persistence, and cleanup execution are not yet implemented.

This ADR establishes their architectural boundaries without
claiming that those components already exist.
