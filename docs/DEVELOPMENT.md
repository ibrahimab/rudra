
# Rudra — Development Standards

**Version:** 1.1  
**Last updated:** 2026-11-03  
**Status:** Active development standard

## 1. Purpose

This document establishes the mandatory coding, documentation, testing, verification, and implementation standards for Rudra.

It applies to all packages, applications, adapters, development tools, and automated tests in the repository.

The objectives are:

- Maintain a clear and predictable codebase.
- Preserve architectural boundaries.
- Ensure filesystem inspection remains safe.
- Make all cleanup behavior explicitly user-directed.
- Prevent regressions through automated testing.
- Produce thoroughly documented, maintainable code.
- Support incremental development without unnecessary rewrites.

`docs/ARCHITECTURE.md` is the architectural baseline.

This document governs how that architecture is implemented.

Architectural Decision Records are maintained under:

`docs/decisions/`

## 2. Development Philosophy

### 2.1 Incremental development

Development proceeds through small, focused implementation blocks.

Each block should have:

1. A clearly defined objective.
2. Relevant architectural context.
3. Explicit implementation boundaries.
4. Documented code.
5. Automated tests.
6. Verification commands.
7. A clear completion condition.

Do not combine unrelated refactoring with feature implementation.

### 2.2 Preserve working implementations

Existing working code must not be replaced unnecessarily.

Before modifying an established component:

- Understand its current responsibilities.
- Identify the specific deficiency.
- Prefer the smallest correct change.
- Preserve public behavior unless a deliberate change is agreed.
- Update affected tests and documentation.

A usage error must not automatically trigger architectural refactoring.

Proposed architectural changes must be explained before implementation.

### 2.3 One file at a time

Code contributions should be presented file by file.

Each file must have:

- Its repository-relative path.
- Complete code when creating a new file.
- Focused changes when modifying an existing file.
- An explanation of its responsibilities.
- Relevant tests.

Generated ZIP archives are not the default delivery format.

The development workflow must support manually typing or copying each file into the repository.

When a complete file replacement is explicitly requested, provide the entire file.

### 2.4 No premature abstraction

Introduce abstractions when they establish a necessary architectural boundary, support multiple implementations, or express a meaningful domain concept.

Do not create general-purpose frameworks merely because they might become useful later.

Prefer explicit, understandable code over speculative extensibility.

## 3. Language and Tooling

Rudra uses Dart with Pub Workspaces.

### 3.1 Dart version

Dart 3.6 or newer is the architectural baseline.

The actual workspace SDK constraint remains authoritative for supported language features.

Do not introduce language features that violate the configured SDK constraint.

### 3.2 Package management

Use Dart Pub Workspaces.

Dependencies must be declared in the appropriate package.

Avoid introducing unnecessary dependencies.

Platform-specific dependencies must remain isolated in their corresponding adapters.

### 3.3 Code formatting

All Dart code must be formatted using the Dart formatter.

From the project root:

    ./rudra format

Formatting must not be treated as optional.

### 3.4 Static analysis

All code must pass the repository's analyzer configuration.

Run:

    ./rudra analyze

Do not suppress analyzer warnings merely to make the verification pipeline green.

If suppression is necessary, document the reason and keep its scope minimal.

### 3.5 Full verification

The authoritative repository verification command is:

    ./rudra check

It verifies dependency resolution, formatting, static analysis, and applicable workspace tests.

A development block is not complete until this command passes.

### 3.6 Selective testing

The root development launcher supports:

    ./rudra test

Use the existing command's supported filters for focused testing.

Run the complete verification pipeline before considering a block complete.

### 3.7 Production builds

The production build command is:

    ./rudra build

Development-only tools must not become production commands accidentally.

## 4. Naming Conventions

### 4.1 Types

Use PascalCase for:

- Classes.
- Interfaces.
- Enums.
- Extensions.
- Type aliases.

Examples:

    TargetInspector
    FilesystemEntry
    CleanupPlan
    InspectionSession
    RudraExitCode

### 4.2 Variables and functions

Use snake_case for:

- Local variables.
- Parameters.
- Fields.
- Functions.
- Methods.

Examples:

    root_path
    session_id
    allocated_size_bytes
    inspect_directory()
    validate_cleanup_plan()
    resume_session()

Private declarations retain Dart's leading underscore convention:

    _active_session
    _validate_candidate()

### 4.3 Enum values

Use lowerCamelCase for enum constants where required by Dart's analyzer conventions.

Examples:

    FilesystemEntryKind.regularFile
    FilesystemEntryKind.symbolicLink
    TargetInspectionErrorCode.permissionDenied

Do not disable standard analyzer rules to enforce a conflicting naming convention.

### 4.4 Files and directories

Use snake_case for Dart source filenames.

Examples:

    filesystem_entry.dart
    target_inspector.dart
    cleanup_plan.dart
    inspection_session.dart

Test filenames should end in `_test.dart`.

## 5. Code Quality

### 5.1 Explicit behavior

Code must express its intent clearly.

Avoid hidden side effects.

Constructors should establish valid object state, not initiate filesystem cleanup or other destructive actions.

### 5.2 Strong typing

Prefer explicit domain types over loosely structured maps or arbitrary strings.

Use typed enums and exceptions for decisions that affect application behavior.

Do not require consumers to parse human-readable error messages.

### 5.3 Immutability

Prefer immutable domain value objects and snapshots.

Defensively copy mutable collections supplied to immutable objects.

Do not expose mutable internal state unintentionally.

### 5.4 Validation

Enforce domain invariants at the appropriate boundary.

Validation that must hold in production must not rely solely on Dart assertions.

Invalid input should produce a clearly documented failure.

### 5.5 Nullable values

Use nullable types when information may genuinely be unavailable.

Never represent unknown filesystem information with fabricated defaults.

In particular:

- Unknown size is not zero.
- Unknown permissions are not denied permissions.
- Missing identity is not a path-derived identity.
- Unknown capability support is not unsupported.
- Incomplete enumeration is not an empty directory.

### 5.6 Error handling

Use typed error categories where meaningful.

Preserve useful diagnostic context without coupling higher layers to native implementation details.

Do not silently swallow errors.

Do not convert failures into successful empty results.

### 5.7 Asynchronous operations

Document asynchronous behavior, including:

- Stream lifecycle.
- Cancellation.
- Error propagation.
- Partial results.
- Resource cleanup.
- Ordering guarantees.

Do not promise atomic filesystem observations when the underlying filesystem cannot provide them.

### 5.8 Constants

Avoid unexplained magic numbers.

Use named constants for meaningful limits and domain thresholds.

Comments should explain why a value exists, not merely repeat the code.

### 5.9 Comments

Place comments above complex logic.

Prefer comments explaining invariants, assumptions, consequences, and non-obvious decisions.

Avoid comments that merely restate simple expressions.

## 6. Documentation Standards

Thorough documentation is mandatory for generated and manually written Rudra code.

Documentation is part of implementation, not optional follow-up work.

### 6.1 Public API documentation

Every public type must include DartDoc describing:

- Purpose.
- Responsibility.
- Important invariants.
- Relevant limitations.
- Usage examples.

Public constructors, methods, fields, and functions must be documented.

### 6.2 Constructor documentation

Constructors must explain:

- Required and optional arguments.
- Validation performed.
- Invalid input behavior.
- Relevant exceptions.
- Important state guarantees.

### 6.3 Method documentation

Public methods must explain:

- Their purpose.
- Input requirements.
- Return values.
- Side effects.
- Error contracts.
- Asynchronous behavior.
- Relevant safety guarantees.

When appropriate, include an `Example` section or DartDoc code example.

### 6.4 Interface documentation

Interfaces must document both method signatures and expected behavior.

A method's contract should clarify what implementations are required to guarantee.

For filesystem interfaces, document:

- Symbolic-link behavior.
- Enumeration scope.
- Error propagation.
- Cancellation behavior.
- Metadata limitations.
- Ownership of recursive traversal.

### 6.5 Domain-state documentation

Stateful domain models must describe:

- Valid states.
- Permitted transitions.
- Forbidden transitions.
- Persistence requirements.
- Recovery behavior.
- Conditions that invalidate prior decisions.

### 6.6 Safety documentation

Any code involved in cleanup planning, validation, authorization, or execution must document its safety invariants.

Code must explain what it guarantees and what it cannot guarantee.

Unsupported guarantees must never be implied.

### 6.7 Architectural documentation

Update `docs/ARCHITECTURE.md` when an implementation changes an established architectural rule.

Create or amend an ADR when a significant design choice is made.

Do not silently diverge from the architectural baseline.

## 7. Dependency Boundaries

### 7.1 CLI

The CLI owns user interaction, command composition, and presentation.

It must not own filesystem safety policy.

It must not independently authorize cleanup execution.

### 7.2 SDK

The SDK owns application and domain behavior.

It must remain independent of CLI and Flutter presentation.

The SDK must not depend directly on SQLite or concrete operating-system adapters.

### 7.3 Target contracts

Target contracts must remain platform-independent.

Do not introduce native filesystem implementation dependencies into the contracts package.

### 7.4 Platform adapters

Platform adapters translate native functionality into the established contracts.

They must not independently decide which files should be removed.

### 7.5 Persistence

Persistence implementations store and retrieve state.

They must not replace domain-level lifecycle or authorization rules.

### 7.6 Composition

Application composition connects interfaces to concrete implementations.

Dependencies must flow toward platform-independent contracts and domain logic.

## 8. Testing Standards

All meaningful behavior requires automated tests.

### 8.1 Unit tests

Unit tests should verify:

- Normal behavior.
- Invalid inputs.
- Boundary values.
- Error conditions.
- Null and unknown states.
- Domain invariants.
- State transitions.

### 8.2 Contract tests

Contract tests must verify expected interface behavior independently of implementation details.

Examples include:

- Valid filesystem entry types.
- Missing path errors.
- Symbolic-link handling.
- Directory enumeration.
- Capabilities.
- Identity semantics.
- Stream failures.

### 8.3 Adapter conformance tests

Concrete adapters must satisfy shared conformance tests.

The existence of passing in-memory fixture tests is not sufficient to establish native adapter correctness.

Native implementations require separate integration tests.

### 8.4 Platform integration tests

Platform tests should cover:

- Real filesystem metadata.
- Native error translation.
- Permission failures.
- Symbolic links.
- Filesystem identities.
- Directory enumeration.
- Cancellation and resource cleanup.
- Relevant race conditions.

Tests must use controlled temporary fixtures.

### 8.5 SDK tests

SDK tests must cover inspection orchestration, aggregation, planning, session behavior, and safety policy independently of the UI.

Prefer deterministic fake adapters for domain-state tests.

## 9. Persistent Session Testing

The session lifecycle is a safety-sensitive part of Rudra.

It requires explicit testing.

### 9.1 Single-session enforcement

Verify that:

- A user can create a session when none is unfinished.
- An unfinished session prevents creation of another.
- The original root remains immutable.
- The user is offered continuation or cancellation.
- Continuing restores the original root.
- Cancellation does not modify inspected filesystem content.
- A new session can be created after explicit cancellation.

### 9.2 Resume behavior

Verify that a session can restore:

- Its original root.
- Wizard progress.
- Current navigation position.
- Marked candidates.
- Plan revisions.
- Relevant prior decisions.

Old inspection results must not automatically be treated as current.

### 9.3 Concurrent invocations

Test attempts to open or mutate the same session from multiple processes or coordinators.

Persistent constraints must prevent contradictory session states.

Crash and stale-lock scenarios must be tested.

### 9.4 Terminal states

Completed and cancelled sessions must not silently return to an active state.

An interrupted execution requires separate reconciliation.

## 10. Dry-Run Wizard Testing

The wizard must remain read-only throughout exploration and marking.

Tests must prove that:

- Directory navigation performs no cleanup.
- Entry inspection performs no cleanup.
- Marking a candidate performs no cleanup.
- Unmarking a candidate performs no cleanup.
- Saving a session performs no cleanup.
- Resuming a session performs no cleanup.
- Cancelling a session performs no cleanup.
- Generating a cleanup preview performs no cleanup.

These guarantees should be checked through explicit fake execution boundaries or other reliable instrumentation.

A test that merely assumes no mutation occurred is insufficient.

### 10.1 Global cleanup list

Test:

- Adding candidates.
- Removing candidates.
- Revisiting selections.
- Overlapping directory and child selections.
- Duplicate selection handling.
- Plan revision changes.
- Plan persistence.
- Accurate representation of incomplete inspections.

## 11. Cleanup Safety Testing

Cleanup behavior is subject to stricter standards than ordinary filesystem inspection.

### 11.1 No implicit authorization

Tests must prove that no destructive operation can occur because a candidate was merely marked.

Authorization requires a separately confirmed complete plan.

### 11.2 Baseline observations

Candidate state must be compared against appropriate saved observations.

Tests must cover:

- Unchanged entries.
- Changed filesystem identities.
- Replaced files at the same path.
- Modified files.
- Changed entry types.
- Changed symbolic links.
- Missing entries.
- Inaccessible entries.
- Added directory children.
- Removed directory children.
- Incomplete subtree observations.
- Unavailable verification capabilities.

### 11.3 Global preflight

No cleanup operation may begin when any candidate has an unresolved validation failure.

Tests must verify that failure of one candidate blocks execution of the entire plan before the first destructive operation.

### 11.4 Reapproval

When a candidate changes:

1. Previous approval becomes invalid.
2. The changed candidate requires renewed review.
3. A revised plan is produced.
4. The complete plan requires renewed confirmation.

Tests must verify that approval of an older plan revision cannot authorize a newer revision.

### 11.5 Runtime validation

Successful preflight must not be treated as permanent authorization.

Tests must simulate changes occurring after preflight but before a destructive operation.

The executor must refuse operations that cannot be safely validated at the operation boundary.

### 11.6 Partial execution

Tests must account for cleanup processes that stop after some operations have succeeded.

Execution records must distinguish:

- Completed operations.
- Failed operations.
- Skipped operations.
- Unattempted operations.
- Interrupted operations.

Partial execution must never be represented as complete success.

### 11.7 Interrupted execution

An interrupted execution must not resume automatically.

Recovery requires reconciliation, fresh validation, and renewed user authorization before additional destructive work.

## 12. Destructive Test Isolation

Future tests involving filesystem mutation must run only against controlled disposable fixtures.

Never run cleanup integration tests against:

- A developer's home directory.
- Real application support directories.
- Actual user caches.
- Production data.
- Arbitrary paths supplied through the environment.
- Unverified external volumes.

Test fixtures must be created deliberately and must have clearly defined ownership.

Cleanup tests must never infer that a directory is disposable merely because its path contains `tmp` or `cache`.

### 12.1 Failure injection

Use deterministic failure injection where possible.

Relevant cases include:

- Permission denial.
- Object replacement.
- Symbolic-link replacement.
- Missing files.
- Changed directory membership.
- Persistence failure.
- Interrupted execution.
- Failed individual operations.
- Unavailable platform safeguards.

### 12.2 Destructive test authorization

Tests must not accidentally invoke production cleanup against real user data.

The test execution mechanism must enforce fixture boundaries independently of the data being tested.

## 13. Persistence Development Standards

SQLite persistence must remain an implementation of explicit domain persistence contracts.

### 13.1 Transactions

Use transactions for logically atomic state changes.

Session transitions and their associated audit events must remain consistent.

### 13.2 Migrations

Schema changes must be versioned and documented.

Migrations must not silently discard unfinished sessions, cleanup selections, or audit evidence.

### 13.3 State integrity

Persisted state must distinguish:

- Session state.
- Wizard navigation.
- Selected candidates.
- Inspection baselines.
- Plan revisions.
- Approval records.
- Execution outcomes.

A persisted selection must never be interpreted as an execution authorization.

### 13.4 Recovery

Crash recovery must not guess that cleanup succeeded.

Unresolved operations require explicit reconciliation.

Do not automatically continue destructive work from a saved checkpoint.

### 13.5 Concurrency

Persistence must enforce one unfinished session per Rudra user profile.

Process-level coordination and durable session uniqueness must be tested independently.

### 13.6 Audit records

Audit events should capture relevant state transitions and outcomes.

Recorded success must correspond to observed success.

User intent, approval, attempts, and results must not overwrite one another semantically.

## 14. Error Handling Standards

### 14.1 Typed errors

Use appropriate domain and inspection error types.

For target inspection, use `TargetInspectionException` and the corresponding typed error codes.

### 14.2 Preserve failures

Do not turn an exception into an empty collection, null value, or successful result unless the contract explicitly defines that behavior.

### 14.3 Partial results

Partial observations must be distinguishable from complete observations.

The SDK decides whether partial results may be retained for presentation.

Partial scan results must never be used as proof that a cleanup target is unchanged.

### 14.4 Diagnostic safety

Do not expose sensitive native error details unnecessarily.

Diagnostic output should contain enough information to identify the failure without leaking unrelated filesystem information.

### 14.5 Failure ownership

The target adapter reports native observation failures.

The SDK determines domain consequences.

The CLI presents the outcome and translates application results into exit codes.

## 15. Performance Standards

Performance improvements must not weaken safety guarantees.

### 15.1 Lazy enumeration

Prefer streaming directory enumeration over loading an entire directory into memory when practical.

### 15.2 Controlled traversal

The SDK should control traversal depth, concurrency, cancellation, and resource usage.

Do not introduce unbounded filesystem traversal parallelism.

### 15.3 Aggregation

Storage aggregation must account for duplicate filesystem identities and incomplete observations where supported.

Do not advertise inaccurate storage reclamation estimates.

### 15.4 Caching

Cached metadata is an observation, not a permanent fact.

Cached observations must not bypass required cleanup revalidation.

### 15.5 Cancellation

Cancellation must release resources and leave persistent state consistent.

Cancelling inspection must not trigger cleanup.

Cancelling execution requires explicitly defined execution behavior.

## 16. Security and Safety Review

Any feature involving filesystem traversal, persistence, cleanup authorization, or execution requires a safety review.

The review should consider:

- Path traversal.
- Relative and absolute paths.
- Symbolic-link behavior.
- Intermediate path components.
- Mount boundaries.
- Filesystem identity reuse.
- Time-of-check/time-of-use races.
- Permission failures.
- Untrusted or malformed metadata.
- Stale persisted state.
- Concurrent processes.
- Incomplete scans.
- Partial execution.
- User confirmation boundaries.

The existence of a user confirmation prompt is not a substitute for technical safety enforcement.

The implementation must validate that the approved object is the object being acted upon.

## 17. Architectural Decision Records

Significant design choices must be documented in:

`docs/decisions/`

Each ADR should contain:

1. Title.
2. Status.
3. Context.
4. Decision.
5. Alternatives considered.
6. Consequences.
7. Relevant verification requirements.

An accepted ADR must not be silently contradicted by implementation changes.

Current architectural subjects requiring explicit decisions include:

- Modular CLI composition.
- Persistent single-session lifecycle.
- Stateful dry-run cleanup planning.
- Cleanup approval and revalidation.
- Mount-boundary enforcement.
- Safe platform-specific execution.
- Interrupted-execution recovery.

Existing ADRs must be preserved rather than replaced by unrelated new decisions.

## 18. Development Workflow

Each implementation block should follow this sequence.

### Step 1 — Establish context

Review the relevant architecture, existing code, contracts, and ADRs.

Identify the exact change required.

### Step 2 — Discuss design

Explain:

- The responsibility being introduced.
- Which package owns it.
- Which dependencies it requires.
- The invariants it must enforce.
- Alternatives where they materially affect correctness.

Do not prematurely implement unrelated capabilities.

### Step 3 — Implement incrementally

Provide code file by file.

Preserve existing working implementations.

Use focused changes.

### Step 4 — Document

Add complete DartDoc for new public APIs.

Update relevant documentation for behavior changes.

Document error contracts and safety guarantees.

### Step 5 — Test

Add tests for new behavior, invalid inputs, and failure conditions.

Safety-sensitive features require negative tests proving that prohibited actions do not occur.

### Step 6 — Format

Run:

    ./rudra format

### Step 7 — Verify

Run:

    ./rudra check

All applicable checks must pass.

### Step 8 — Review

Confirm that:

- The implementation matches the architectural design.
- Tests validate meaningful behavior.
- No unrelated implementation changed.
- No platform dependency leaked into core packages.
- Safety invariants remain intact.
- Documentation matches the implementation.

### Step 9 — Commit

Commit only after successful verification and review.

Use a meaningful commit message identifying the completed block or feature.

Do not commit generated binaries, caches, or unrelated artifacts.

## 19. Definition of Done

An implementation block is complete only when:

- The intended behavior is implemented.
- Architectural boundaries are respected.
- Existing working functionality is preserved.
- Public APIs are documented.
- Relevant automated tests exist.
- Negative and failure cases are covered.
- Code is formatted.
- Static analysis passes.
- `./rudra check` passes.
- No unresolved safety regression remains.
- Any necessary architectural documentation is updated.

For safety-critical features, successful tests must demonstrate that prohibited operations cannot occur.

If a known safety requirement is not yet enforceable, the feature must remain non-executable or explicitly deferred.


## 20. Current Development Baseline

As of Block 4B, Rudra has implemented:

- Modular CLI infrastructure and typed exit codes.
- Separate production and development entrypoints.
- Dart Pub Workspaces.
- Platform-independent filesystem contracts and metadata.
- The macOS TargetInspector.
- Pure-Dart SDK filesystem inspection services.
- Production SDK composition.
- SDK-backed directory listing commands.
- CLI welcome MVC.
- Shared CLI directory-listing presentation.
- Read-only welcome-screen filesystem inspection.
- Explicit reporting of incomplete observations.

The SDK remains independent of CLI presentation and concrete
platform adapters.

The development launcher executes from the repository root.

Interactive navigation, persistent sessions, cleanup planning,
validation, authorization, and execution remain future work.

The current verification status must be established by running
the repository quality gate. Historical test totals must not
be presented as current results.

The next milestone is interactive filesystem exploration using
the existing SDK-first architecture and safety requirements.

## 21. Non-Negotiable Development Rules

The following rules apply to all future Rudra contributions:

1. Never introduce autonomous destructive cleanup.
2. Never make the inspection wizard destructive.
3. Never interpret marking as execution approval.
4. Never bypass the final cleanup-plan confirmation.
5. Never execute a stale or unverifiable cleanup plan.
6. Never silently accept replacement filesystem objects.
7. Never allow new directory contents to inherit old approval.
8. Never automatically restart interrupted destructive work.
9. Never replace working code without a justified reason.
10. Never omit required tests or public API documentation.
11. Never allow platform-specific logic to leak into the core contracts.
12. Never conceal incomplete inspection or partial execution.
13. Never sacrifice filesystem safety for convenience or performance.

These requirements take precedence over implementation shortcuts.
