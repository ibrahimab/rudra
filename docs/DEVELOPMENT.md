# Rudra — Development Guide

## 1. Overview

Rudra is a cross-platform, user-directed filesystem exploration and cleanup application.

The project is implemented as a Dart monorepo using Pub Workspaces. It follows a modular architecture consisting of:

- A platform-independent SDK.
- Target contracts and operating-system-specific adapters.
- Independent application frontends.
- A shared, extensible CLI framework.
- Persistent sessions, cleanup plans, and audit logging.
- A comprehensive automated testing infrastructure.

The first supported application is a terminal-based CLI, with macOS as the initial target platform.

Future frontends may include Flutter desktop, mobile, and web applications.

### Core development principles

1. **No automated destructive actions.** Rudra must never select or delete files without explicit user authorization.
2. **Platform independence.** Shared business logic must not depend on operating-system implementations.
3. **Modular architecture.** Features must expose well-defined contracts and dependencies.
4. **Testability.** All functional changes must have appropriate automated tests.
5. **Thorough documentation.** Public APIs, architectural decisions, and non-obvious implementation behavior must be documented.
6. **Recoverability.** Interrupted cleanup operations must be auditable and recoverable without automatic resumption.
7. **Minimal dependencies.** New packages and frameworks must solve a demonstrated architectural or functional requirement.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the system architecture and [ADR-0001](decisions/0001-modular-cli.md) for the modular CLI design decision.

## 2. Development requirements

### Required software

- Dart SDK 3.6 or newer.
- Git.
- A supported development terminal.
- macOS for initial target-adapter development.

### Recommended software

- Visual Studio Code with the Dart extension.
- Flutter SDK when graphical application development begins.

Flutter is not required to develop or execute the current CLI.

### Project location

The local project root is:

`~/projects/rudra`

Commands in this document assume the current working directory is the repository root unless otherwise specified.

## 3. Repository organization

The repository separates applications, reusable packages, documentation, and development infrastructure.

```text
rudra/
├── apps/
│   └── cli/
│       ├── bin/
│       ├── lib/
│       │   └── src/
│       ├── tool/
│       │   └── src/
│       └── test/
├── packages/
│   ├── sdk/
│   ├── targets/
│   │   ├── contracts/
│   │   └── macos/
│   └── persistence/
│       └── sqlite/
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DEVELOPMENT.md
│   └── decisions/
├── rudra
├── pubspec.yaml
└── pubspec.lock
```

Additional application frontends and platform adapters will be introduced as they are implemented.

The logical architecture may contain more modules than the current repository has physical Dart packages. Separate packages should be introduced when their dependency boundaries justify them.

## 4. Dart workspace

Rudra uses Dart Pub Workspaces to manage the monorepo.

Each Dart package has its own `pubspec.yaml`, while the root workspace manages shared dependency resolution.

### Resolve dependencies

```bash
cd ~/projects/rudra
dart pub get
```

### Discover workspace packages

```bash
dart pub workspace list
```

The workspace listing is also used by Rudra's development tooling to discover packages automatically.

New packages must be registered in the root workspace configuration.

### Dependency rules

The following dependency direction must be preserved:

```text
Applications / Frontends
          |
          v
     Shared SDK
          |
          v
   Target Contracts
          ^
          |
 Platform Adapters
```

Applications compose SDK services and platform adapters.

Target contracts must not depend on concrete operating-system implementations.

The SDK must not depend on CLI or Flutter presentation frameworks.

Development tooling must not become a dependency of the production application.

## 5. CLI architecture

Rudra uses one shared CLI framework built around the `RudraCli` class.

The underlying argument parser is provided by Dart's `args` package.

### Responsibilities of RudraCli

`RudraCli` is responsible for:

- Registering CLI modules.
- Validating module identifiers.
- Detecting duplicate command names and aliases.
- Managing command registration lifecycle.
- Dispatching commands.
- Handling argument usage errors.
- Returning process exit statuses.

The framework does not own filesystem cleanup policies or platform-specific operations.

### CLI modules

Features contribute commands by implementing the `RudraCliModule` contract.

Each module provides:

- A stable `module_id`.
- One or more commands through `create_commands()`.

Modules must be registered explicitly during application composition.

Registration must not execute commands or cause destructive filesystem changes.

### Module lifecycle

1. Construct the CLI framework.
2. Construct the required modules and inject dependencies.
3. Register each module.
4. Validate command and alias uniqueness.
5. Execute the requested command.
6. Close the registration lifecycle.

A CLI instance cannot register additional modules after execution begins.

A CLI instance is intended for one command invocation.

### Product and development composition

Rudra has two composition entrypoints sharing the same CLI framework.

**Production entrypoint**

`apps/cli/bin/rudra.dart`

Registers product modules only.

**Development entrypoint**

`apps/cli/tool/rudra_dev.dart`

Registers the product modules and extends them with `DevToolsCliModule`.

This design provides a single command framework without exposing development commands in the production registry.

Development modules must not appear in the production entrypoint's import dependency graph.

### Plugin discovery policy

Rudra currently uses explicit, compile-time module registration.

Automatic discovery and execution of arbitrary external plugin code is not supported.

Future plugin discovery mechanisms must define an explicit trust and security model before implementation.

## 6. Development commands

The repository provides a development launcher named `rudra`.

On macOS and Linux:

```bash
./rudra help
```

On Windows, development commands can be invoked directly through Dart:

```powershell
dart run apps/cli/tool/rudra_dev.dart help
```

The development launcher delegates command handling to the shared `RudraCli` framework.

### Available commands

| Command | Description |
| --- | --- |
| `./rudra help` | Display available commands |
| `./rudra about` | Display Rudra application information |
| `./rudra test` | Execute workspace test suites |
| `./rudra analyze` | Run static analysis |
| `./rudra format` | Format Dart source files |
| `./rudra check` | Run the complete quality gate |
| `./rudra build` | Compile and verify the production executable |

Development commands must return nonzero exit statuses when their operations fail.

### Full quality gate

```bash
./rudra check
```

The command performs the following operations sequentially:

1. Resolve workspace dependencies.
2. Verify Dart formatting without modifying source files.
3. Execute static analysis.
4. Run the workspace test suites.

Execution stops at the first failed stage.

### Scoped quality gate

```bash
./rudra check --package rudra_cli
```

Restricts formatting, analysis, and testing to the selected package.

Dependency resolution remains workspace-wide.

A scoped check is useful during feature development but does not replace the full quality gate.

### Formatting

```bash
./rudra format
```

Formats Dart source files using the official Dart formatter.

Unlike `check`, this command modifies source files.

### Static analysis

```bash
./rudra analyze
```

Runs Dart's static analyzer.

All analyzer errors must be resolved before committing.

Warnings and lints must be reviewed rather than suppressed without justification.

## 7. Testing framework

Rudra uses Dart's official `package:test` framework.

We do not implement a custom test assertion framework or duplicate existing Dart testing functionality.

The development CLI provides orchestration, workspace discovery, and filtering.

### Run all tests

```bash
./rudra test
```

The test runner:

1. Discovers packages using `dart pub workspace list`.
2. Inspects each package for `*_test.dart` files.
3. Executes available test suites.
4. Reports skipped packages.
5. Stops when a suite fails.
6. Returns a nonzero status on failure.

Tests currently execute sequentially.

### Run one package

```bash
./rudra test --package rudra_target_contracts
```

Or use the short option:

```bash
./rudra test -p rudra_cli
```

Package filters use the declared Dart package name, not the filesystem directory name.

### Filter by test name

```bash
./rudra test --package rudra_cli --name "RudraCli"
```

The name filter is forwarded to Dart's test runner and supports regular-expression matching.

### Filter by tags

```bash
./rudra test --tags unit
```

Exclude tests carrying a particular tag:

```bash
./rudra test --exclude-tags slow
```

Compound tag selectors are supported through the underlying Dart test framework.

Tags must be explicitly assigned to tests or test groups before they can be used for filtering.

### Run package tests directly

During debugging, package tests can also be run without Rudra's development command:

```bash
cd apps/cli
dart test
```

This is useful when diagnosing failures in the Rudra CLI framework itself.

## 8. Testing strategy

Rudra's testing infrastructure is organized into five conceptual layers.

### Unit tests

Verify isolated business logic and application behavior.

Examples include:

- Target capability detection.
- Directory selection policies.
- Parent-child selection conflict handling.
- CLI module registration.
- Command argument validation.
- Session state transitions.

### Contract tests

Verify that platform implementations satisfy shared target contracts.

Every target adapter must pass the relevant contract test suite.

Contract tests must not assume that every target supports the same optional capabilities.

### Integration tests

Verify interactions between multiple real components.

Examples include:

- Directory enumeration through the macOS adapter.
- SQLite session persistence.
- Cleanup plan serialization.
- Audit event storage and retrieval.

Filesystem integration tests must use isolated temporary fixtures.

### Recovery and failure-injection tests

Verify behavior when execution is interrupted or fails.

Examples include:

- An operation completes but its completion event is not recorded.
- A selected target disappears before execution.
- A file is replaced after inspection.
- Permission changes prevent an authorized operation.
- A worker terminates unexpectedly.
- A previously interrupted job is reopened.

Tests must demonstrate that Rudra does not automatically resume destructive execution.

### End-to-end tests

Verify complete user workflows.

Examples include:

- Starting an exploration session.
- Navigating nested directories.
- Marking and excluding files.
- Resolving conflicting selections.
- Reviewing a cleanup plan.
- Performing a dry run.
- Confirming authorized execution.

Terminal interaction tests will be introduced when the TUI implementation begins.

## 9. Test isolation and safety

Tests must never delete or modify real user data.

In particular, tests must not target:

- Actual user home directories.
- Real application caches.
- Developer SDK installations.
- System directories.
- Mounted user volumes containing real data.

Destructive-operation tests must use explicitly created, isolated test fixtures.

Fixtures must be uniquely scoped to their test execution.

Tests must verify their safety preconditions before performing filesystem changes.

Mock adapters should be used for domain-level tests.

Real filesystem fixtures should be reserved for integration tests requiring actual filesystem behavior.

Temporary fixture cleanup is permitted as part of the test harness, but must remain strictly confined to verified test-owned locations.

## 10. Exit code conventions

Application-owned process exit statuses are represented by the `RudraExitCode` enum.

| Status | Value | Meaning |
| --- | --- | --- |
| `success` | 0 | Operation completed successfully |
| `invalid_usage` | 64 | Invalid arguments or command usage |
| `missing_input` | 66 | Required input or repository resource missing |
| `software_error` | 70 | Internal application failure |
| `configuration_error` | 78 | Invalid application configuration |

Application-owned exit values must not be scattered throughout the code as unexplained integers.

External subprocesses may return statuses outside this enumeration.

Those statuses should be preserved where appropriate, together with sufficient diagnostic information to identify the failing operation.

Unexpected programming errors must not be silently reported as successful outcomes.

Exit codes represent process outcomes; they do not replace structured domain errors or the persistent execution audit log.

## 11. Building Rudra

### Compile the production CLI

```bash
./rudra build
```

The build command compiles:

`apps/cli/bin/rudra.dart`

The development entrypoint must never be used to create a production distribution.

### Build output

On macOS and Linux:

`build/rudra`

On Windows:

`build/rudra.exe`

The resulting native executable does not require an installed Dart SDK.

### Verify production behavior

```bash
./build/rudra --help
./build/rudra about
```

Both commands should complete successfully.

Now verify that development commands are unavailable:

```bash
./build/rudra test
```

This command must fail with a usage error.

The build verification checks the production command registry. This is distinct from a binary-level audit of included code and dependencies.

### Production dependency boundary

Production application code must not import:

- Development command modules.
- Test runner implementations.
- Test fixture utilities.
- Repository maintenance tasks.

Future production builds should include automated dependency-boundary verification.

## 12. Code quality standards

### Naming conventions

Rudra follows these conventions:

- Types and classes: `PascalCase`.
- Variables and functions: `snake_case`.
- Public and private method naming follows the same convention.
- Constants: descriptive names without unexplained abbreviations.
- Package names: lowercase with underscores.

Names should describe the purpose of a component rather than its implementation details.

### Documentation

All public APIs must have DartDoc documentation.

Documentation should explain:

- Responsibility and intended use.
- Parameters and return values.
- Preconditions and invariants.
- Error and exception behavior.
- Side effects.
- Security and authorization implications.
- Relevant usage examples.

Examples should demonstrate realistic API usage.

### Inline comments

Inline comments should explain non-obvious reasoning, constraints, and safety decisions.

Avoid comments that merely repeat what the code already expresses.

Place explanatory comments above complex operations.

### Error handling

Errors must not be silently discarded.

Platform errors should be translated into documented target-layer errors when crossing platform abstraction boundaries.

Unexpected failures should retain useful diagnostic context.

### Dependency management

Prefer Dart's standard library and established packages.

New dependencies should be justified by functionality, maintenance cost, security, and portability.

Avoid introducing framework abstractions that duplicate existing Dart capabilities.

### Architectural consistency

Implementations must follow the accepted architecture.

Material design changes should be documented using architecture decision records.

Do not replace established, working components without first evaluating the existing implementation and explaining the reason for the change.

## 13. Documentation requirements

Documentation is a mandatory part of implementation.

The `docs/` directory contains project-level technical documentation.

### Architecture documentation

`ARCHITECTURE.md` describes:

- System boundaries.
- Dependency direction.
- Application frontends.
- SDK and target abstractions.
- Session management.
- Cleanup execution.
- Safety and recovery principles.

### Development documentation

`DEVELOPMENT.md` describes:

- Development setup.
- Tooling.
- Testing.
- Building.
- Coding conventions.
- Contributor workflows.

### Architecture decision records

Architectural decisions are recorded in `docs/decisions/`.

Each accepted ADR should include:

- Context.
- Decision.
- Alternatives or tradeoffs.
- Consequences.
- Deferred questions where applicable.

ADRs preserve the reasoning behind decisions rather than merely describing the resulting implementation.

### Documentation maintenance

Documentation must be updated alongside relevant code changes.

Changes to safety invariants, target contracts, public APIs, execution semantics, or package boundaries must not leave the documentation outdated.

## 14. Standard development workflow

A typical development cycle is:

### Step 1 — Identify the component

Determine which application or SDK package owns the functionality.

Respect the established dependency direction.

### Step 2 — Define the contract

Describe:

- Expected behavior.
- Inputs and outputs.
- Failure conditions.
- Safety constraints.
- Required capabilities.

### Step 3 — Implement a focused change

Make the smallest coherent change that satisfies the requirement.

Do not introduce unrelated architectural changes during feature implementation.

### Step 4 — Write or update tests

Include successful cases, failures, edge cases, and relevant invariants.

### Step 5 — Run scoped verification

For CLI work:

```bash
./rudra check --package rudra_cli
```

For target contract work:

```bash
./rudra check --package rudra_target_contracts
```

### Step 6 — Run the full quality gate

```bash
./rudra check
```

This is mandatory before considering a change complete.

### Step 7 — Update documentation

Update DartDoc, development guidance, architecture documentation, and ADRs as applicable.

### Step 8 — Review and commit

Review changed files:

```bash
git diff
git status
```

Commit only after the relevant checks pass.

## 15. Safety requirements

Rudra's primary rule is:

**NO AUTOMATED DESTRUCTIVE ACTIONS.**

Scanning, selecting, reviewing, and deleting are distinct operations.

The user explicitly controls the exploration and cleanup workflow.

### User authorization

- No automatically selected cleanup targets.
- No deletion as a side effect of scanning.
- No implicit authorization from a target capability.
- No silent resolution of conflicting directory selections.
- No destructive actions during module registration.
- No automatic resumption of interrupted cleanup jobs.

### Cleanup execution

Destructive execution will use explicitly approved cleanup plans.

The execution worker must revalidate target identity and relevant safety constraints before acting.

The filesystem is not transactional; recording execution events does not make deletion atomic.

### Recovery

Interrupted jobs must be detectable through persistent execution records.

On reopening a job, Rudra must present its recorded and reconciled state.

Resumption requires explicit user authorization.

The worker must not blindly repeat operations solely because their completion events are missing.

These principles apply to every frontend and every target adapter.

## 16. Future development

The following capabilities are planned or under consideration but are not part of the current development infrastructure:

- Stateful terminal UI using Nocterm, subject to compatibility testing.
- Reusable target-adapter contract test suites.
- Comprehensive permission and symbolic-link testing.
- SQLite-backed session and execution persistence.
- Audit/event inspection commands.
- Failure-injection and recovery testing utilities.
- Bounded parallel test execution.
- Flutter desktop application.
- Windows and Linux target adapters.
- Remote target management.
- Generated compile-time CLI module registration.

These capabilities should be implemented incrementally when justified by concrete requirements.

## 17. Definition of done

A feature is considered complete when:

- [ ] Its behavior matches the documented requirements.
- [ ] Architectural boundaries remain intact.
- [ ] Public APIs are thoroughly documented.
- [ ] Automated tests cover successful and failing cases.
- [ ] Relevant safety invariants are verified.
- [ ] Scoped checks pass.
- [ ] The full `./rudra check` quality gate passes.
- [ ] Relevant documentation is updated.
- [ ] No unexpected production dependencies were introduced.
- [ ] The implementation has been reviewed before committing.

**Rudra prioritizes correctness, user control, safety, maintainability, and recoverability over implementation speed.**