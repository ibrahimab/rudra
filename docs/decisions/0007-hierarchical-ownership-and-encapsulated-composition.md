# ADR 0007 — Hierarchical Ownership and Encapsulated Composition

**Date:** 2026-11-25  
**Status:** Accepted  
**Implementation:** Incremental

## 1. Context

Rudra consists of reusable infrastructure, application services, native platform capabilities and frontend applications.

As the system grows, exposing the internal dependencies of each component through its consumer's API increases coupling, constructor complexity and composition overhead.

The communication infrastructure introduced during Epic 7A provides a concrete opportunity to establish independent package boundaries and hierarchical component ownership.

## 2. Decision

Rudra SHALL adopt hierarchical ownership and encapsulated composition.

Components SHALL construct, maintain and dispose of their intrinsic dependencies by default, while permitting explicit substitution through appropriate contracts.

Consumers interact with a component through its public capabilities without requiring knowledge of its internal implementation structure.

### 2.1 Component ownership

- Each component owns its internally constructed dependencies.
- An explicitly supplied substitute follows the receiving component's documented ownership and lifecycle contract.
- Components coordinate the lifecycle of their immediate dependencies.
- Resource disposal follows dependency order.
- Construction and registration remain free of externally observable operational side effects.

### 2.2 Dependency substitution

Dependency injection SHALL enable customization, testing and alternative implementations without requiring consumers to assemble every internal component.

Default implementations SHALL be provided where a meaningful and safe default exists.

Required environmental configuration, trusted identities, authorization decisions and explicitly selected external resources remain the responsibility of the appropriate composition boundary.

Missing or unsupported capabilities SHALL fail explicitly.

### 2.3 Independent infrastructure packages

Cohesive infrastructure capabilities SHALL be isolated into independently testable packages when their responsibilities extend beyond a single application component.

Generic infrastructure SHALL remain independent of Rudra's domain semantics, application workflows and frontend implementations.

Package boundaries SHALL follow concrete responsibilities rather than individual classes or speculative abstractions.

### 2.4 Communication infrastructure

The communication package SHALL own:

- Transport contracts and implementations.
- Native peer authentication.
- Connection and session lifecycle management.
- Message encoding, decoding and framing.
- Generic messaging, correlation and delivery.

The communication package SHALL construct its default transport internally and permit explicit transport substitution.

Native transport selection SHALL remain encapsulated within the communication subsystem.

RudraHost SHALL construct and maintain its communication instance by default, while permitting an alternative implementation to be supplied.

Workflow messages, application handlers and domain-specific capability registration belong to Rudra's application-facing host and SDK components.

Communication infrastructure SHALL process these messages through generic contracts without depending on their application semantics.

### 2.5 Platform boundaries

Native implementations SHALL remain behind portable capability contracts.

Platform selection belongs to the component responsible for the selected capability or its dedicated composition boundary.

Operating-system implementation details SHALL NOT propagate through unrelated consumer APIs.

### 2.6 Extensibility

Adding an application capability should primarily involve introducing feature-owned code and registering it at the appropriate application boundary.

Adding a communication mechanism should primarily involve implementing the transport contract and integrating it within the communication subsystem.

Neither change should require modification of unrelated infrastructure.

## 3. Consequences

### Benefits

- Reduced constructor and composition complexity.
- Clearer resource ownership and disposal guarantees.
- Independently reusable infrastructure packages.
- Focused testing and substitution boundaries.
- Reduced coupling between application semantics and native mechanisms.

### Costs

- Requires deliberate public API and lifecycle design.
- Default implementation selection must remain explicit and predictable.
- Ownership transfer and resource disposal contracts require verification.
- Package extraction introduces additional dependency management.

## 4. Implementation strategy

Epic 7A.4 introduces the independent communication package and establishes hierarchical ownership of communication and transport resources.

Epic 7B introduces typed messaging above the existing transport infrastructure.

Existing workflow processing, persistence ownership, authentication, authorization and execution safety guarantees remain unchanged.

Future architectural changes SHALL apply these principles where concrete implementation responsibilities justify them.

## 5. Verification requirements

Tests SHALL verify that:

- Communication infrastructure has no dependency on Rudra's domain SDK.
- Components support their default construction path.
- Explicit substitutes are used without constructing unnecessary default implementations.
- Construction does not acquire external resources.
- Owned resources are disposed of in dependency order.
- Failed resource disposal does not prematurely release exclusive host ownership.
- Unsupported platforms fail explicitly.
- Existing authentication, concurrency and persistence safety guarantees remain intact.

## 6. Related decisions

- ADR 0004 — SDK-First Application Architecture
- ADR 0005 — CLI Feature-First Structure
- ADR 0006 — Event-Sourced Workflow and Reactive SDK Architecture
- Epic 7 — Centralized Host and Frontend Synchronization