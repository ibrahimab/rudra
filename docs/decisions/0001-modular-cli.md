
# ADR-0001: Modular Rudra CLI

Status: Accepted

## Context

Rudra is a cross-platform filesystem exploration and cleanup application.

Its CLI must support multiple independently developed features while
sharing the same application framework.

Development tools must reuse the CLI framework without becoming part of
the production application.

Rudra also requires a common test runner across its Dart workspace.

## Decision

### 1. One CLI framework

All CLI applications use `RudraCli`.

It owns:

- Command registration
- Module registration and validation
- Command dispatch
- Usage error handling
- Application invocation lifecycle

Dart's `args` package supplies the underlying command parser.

### 2. Module contract

Every CLI integration implements `RudraCliModule`.

Modules contribute commands during application composition.

Registration is explicit. Rudra does not dynamically discover and
execute arbitrary plugin code from the filesystem.

A module must not perform destructive operations during registration.

### 3. Dependency direction

The SDK and target contracts must never depend on the CLI.

CLI integration modules may depend on SDK functionality.

The CLI is a frontend adapter, not a domain authority.

### 4. Composition boundaries

The production entrypoint registers only product modules.

The development entrypoint registers product modules plus development
modules.

Development-only implementations remain outside the production
entrypoint's dependency graph.

Production builds compile the production entrypoint.

### 5. Exit statuses

Application-owned process exit statuses are defined by `RudraExitCode`.

Exit statuses returned by external processes retain their original
numeric values when appropriate.

Unexpected application errors must not be silently converted to success.

### 6. Testing

Workspace package discovery uses `dart pub workspace list`.

Packages do not need CLI plugins merely to make tests discoverable.

The test command supports package, test-name, inclusion-tag, and
exclusion-tag filters.

Dart's `package:test` remains the authoritative test framework.

Tests must not perform destructive operations on real user data.

### 7. Registration lifecycle

Modules are registered before execution begins.

Command names and aliases must be unique.

Registration cannot continue after execution starts.

Module registration must not invoke commands.

## Consequences

Benefits:

- Reusable CLI infrastructure
- Independent feature integration
- Shared product and development command handling
- Explicit production/development separation
- Automatic workspace test discovery
- Selective verification during development

Tradeoffs:

- Module registration is currently explicit, not automatic
- Command integration modules require maintenance
- Two composition entrypoints remain necessary
- SDK functionality and CLI presentation code cannot be shared
  indiscriminately across dependency boundaries

## Deferred decisions

- Automatic generation of compile-time module registries
- Separate CLI integration packages
- Third-party plugin loading and its security model
- Dependency injection container
- Parallel test execution
- Test execution across future Flutter applications

These are not required for the current implementation.
