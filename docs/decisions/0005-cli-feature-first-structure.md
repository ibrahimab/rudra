
# ADR 0005 — CLI Feature-First Structure

**Date:** 2026-11-11  
**Status:** Accepted  
**Implementation:** Incremental migration

## 1. Context

Rudra's CLI originally organized implementation files primarily by
technical layer:

- `commands/`
- `presentation/`
- `rendering/`
- A flat `test/` directory

This distributed the implementation of individual features across
unrelated directories.

For example, the welcome workflow required files from several
locations to understand its controller, presenter, model, view model,
renderer, and tests.

The organization also grouped concrete feature renderers with
genuinely reusable rendering infrastructure.

As Rudra grows to support interactive navigation, persistent
sessions, and additional CLI workflows, this arrangement increases
maintenance costs and obscures feature ownership.

ADR 0004 already establishes the SDK-first application architecture.
This decision refines the CLI's internal organization without changing
the responsibilities of the SDK or platform adapters.

## 2. Decision

The CLI SHALL use a feature-first source organization.

Feature-specific commands, controllers, models, presenters, view
models, renderers, and supporting implementations SHALL reside
together under `lib/src/features/`.

Tests SHOULD mirror the corresponding production ownership.

Shared CLI infrastructure SHALL reside under `lib/src/core/`.

Application composition SHALL remain separate from both features
and shared infrastructure.

### 2.1 Feature organization

The initial production features are:

- `about`
- `welcome`
- `filesystem`
- `explorer`

Feature directories SHALL remain shallow unless additional nesting
provides a clear organizational benefit.

A feature is not required to implement every MVC component.

Simple commands may consist only of a command and registration module.

Interactive features may contain controllers, models, presenters,
view models, input handling, and concrete renderers as needed.

### 2.2 Shared infrastructure

`core/cli/` owns reusable CLI contracts and process exit codes.

`core/rendering/` owns:

- The generic renderer contract.
- Semantic terminal roles and themes.
- Safe terminal text handling.
- Low-level ANSI text encoding.

Core infrastructure MUST NOT depend on feature implementations,
application composition, or concrete target adapters.

Feature-specific renderers SHALL NOT be placed in core merely
because they use the same rendering backend.

### 2.3 Feature dependencies

Feature dependencies SHALL remain explicit and acyclic.

The filesystem feature owns the existing directory-listing
presentation implementation.

Welcome may reuse filesystem listing presentation because it
displays directory observations using the same presentation
contract.

Filesystem MUST NOT depend on welcome.

Explorer SHALL consume SDK filesystem services directly rather
than depending on the filesystem feature's command implementation.

Explorer-specific input decoding remains within explorer.

A general terminal input abstraction SHALL only be introduced
when an implemented use case demonstrates genuine reuse.

### 2.4 Application composition

Application composition is responsible for:

- Selecting and constructing supported target adapters.
- Configuring the public Rudra SDK.
- Supplying the initial target-native directory.
- Constructing feature controllers and CLI modules.
- Selecting concrete rendering implementations.
- Injecting output and diagnostic destinations.

Features MUST NOT depend on `ProductSdkComposition`.

Feature controllers receive the application services and values
they require through explicit constructor injection.

The existing `RudraCli.product()` entry point remains responsible
for production application assembly.

The modular command framework established by ADR 0001 remains
unchanged.

### 2.5 SDK-first boundary

The SDK continues to own:

- Filesystem inspection orchestration.
- Shared application and domain services.
- Persistent session lifecycle policy.
- Cleanup planning and authorization rules.
- Validation and safety requirements.

The CLI owns presentation, command invocation, input decoding,
interactive navigation, and process exit statuses.

Neither feature organization nor renderer injection transfers
domain authority from the SDK into the CLI.

### 2.6 Test organization

Tests SHOULD follow production feature boundaries.

Core tests reside under `test/core/`.

Feature tests reside under `test/features/`.

Composition tests reside under `test/composition/`.

Cross-feature and command-registration integration tests reside
under `test/integration/`.

Development tooling tests reside under `test/tool/`.

Tests do not need to duplicate the exact production directory
depth when a shallower organization remains clear.

### 2.7 Migration rules

The restructuring SHALL preserve:

- Public SDK contracts and existing CLI exports.
- Existing command names and module identifiers.
- Process exit-code values and error propagation.
- Established terminal output formats.
- Incomplete-observation handling.
- Filesystem read-only guarantees.
- Production/development command separation.
- Existing Explorer navigation behavior.

Obsolete forwarding libraries and compatibility adapters SHALL
NOT be introduced.

The migration SHALL NOT introduce new Explorer functionality,
persistent sessions, cleanup planning, or destructive execution.

## 3. Dependency direction

The intended dependencies are:

    Production / Development Entrypoints
                    |
                    v
          Application Composition
                    |
                    v
               CLI Features
                /       \
               v         v
          CLI Core    Rudra SDK
                          |
                          v
                   Target Contracts

Concrete platform adapters implement target contracts and are
injected into the SDK by application composition.

CLI core cannot import feature implementations.

The SDK cannot import CLI presentation code.

Feature-to-feature dependencies are permitted only when ownership
is explicit, reuse is justified, and no dependency cycle is created.

## 4. Alternatives Considered

### Technical-layer organization

Rejected because it separates implementations belonging to the
same feature and obscures feature ownership.

### Deeply nested feature directories

Deferred because small features do not justify separate
`models/`, `presentation/`, and `renderers/` directories.

### Moving all rendering implementations into core

Rejected because concrete feature renderers depend on
feature-specific view models and output contracts.

### Duplicating directory-listing presentation

Rejected because the welcome and filesystem workflows already
share an established presentation contract.

### Introducing a universal CLI MVC framework

Rejected because different CLI commands require different
presentation complexity, and ADR 0004 does not mandate a
universal frontend framework.

## 5. Consequences

Benefits include clearer ownership, localized changes, more
discoverable tests, and reduced accidental coupling between
features and shared infrastructure.

The explicit dependency direction also makes it easier to
identify code that belongs in the SDK rather than the CLI.

Costs include updating source imports, tests, and architectural
documentation during migration.

The filesystem presentation dependency remains shared with
welcome. Its ownership and dependency direction are now explicit.

## 6. Verification

The migration is complete only when:

- Every existing production file has its agreed owner.
- Tests follow the agreed structure.
- No imports reference removed directories.
- No compatibility adapters remain.
- The public CLI API remains available.
- Existing functionality and exit codes are preserved.
- The complete repository verification passes.

Required verification:

    ./rudra format
    ./rudra check --package rudra_cli
    ./rudra check
    git diff --check

## 7. Related Decisions

- ADR 0001 — Modular Rudra CLI.
- ADR 0002 — Persistent single session.
- ADR 0003 — Dry-run cleanup and revalidation.
- ADR 0004 — SDK-first application architecture.

This decision supplements ADR 0004 and does not supersede it.
