# ADR 0008 — Machine-Wide Persistence and Transport-Independent Connectivity

**Status:** Accepted  
**Date:** 26 November 2026  
**Related:** ADR 0004, ADR 0006, ADR 0007  
**Implementation:** Epic 7D.1.4

## Context

Rudra provides authoritative application execution through a long-running host. Independent frontend processes consume application capabilities through authenticated communication.

The initial host implementation associates persistence, exclusive host ownership and native communication endpoints with a common configurable directory.

This association introduces unnecessary coupling between application storage, process ownership and communication.

Future machine-wide filesystem reservations must coordinate operations across workflows belonging to different operating-system users.

## Decision

### Machine-wide persistence

Rudra uses one authoritative machine-wide application data directory and SQLite database.

All Rudra hosts on the same machine access this shared database through independently owned persistence contexts.

Workflow ownership, submission resolution, history restoration and application authorization remain scoped to trusted operating-system identities.

Production host execution uses the platform-defined application data location. Arbitrary persistence directory overrides are prohibited.

Isolated application composition and test fixtures may supply disposable persistence locations.

### Exclusive host ownership

At most one Rudra host may run concurrently per operating-system user on a machine.

Exclusive host ownership is independent of database location, transport selection and communication endpoint configuration.

Competing host instances are rejected before persistence initialization or communication endpoint activation.

Ownership remains retained until application, communication and persistence resource disposal has been confirmed.

Different operating-system users may run independent Rudra hosts concurrently.

### Communication ownership

Communication owns transport registration, default transport selection, listening endpoint activation, connection establishment, session coordination and transport resource disposal.

RudraHost consumes authenticated application communication without selecting or managing individual transport implementations.

Transport implementations encapsulate native endpoint configuration and connection mechanics.

Registered listening transports are activated according to their configuration before admitting incoming connections.

The client selects one transport for each connection lifecycle.

Default local connectivity uses the native platform's supported communication mechanism.

The initial implementation uses Unix-domain socket communication on macOS.

### Endpoint configuration

Local communication transports provide deterministic default endpoint configuration.

Host-side transport execution creates and owns its listening endpoint.

Client-side transport execution connects to the corresponding configured endpoint.

Explicit transport configuration may override the default communication endpoint without changing application persistence or exclusive host ownership.

Frontend applications are not required to resolve host persistence locations, native socket paths or trusted operating-system identities to establish default connectivity.

### SDK connectivity

RudraSdk remains the single public frontend application facade.

Application capabilities are composed independently of connection establishment and transport selection.

The SDK supports default connectivity and explicitly configured connectivity through one application execution architecture.

Disconnected SDK instances reject application operations.

Connection replacement requires confirmed disposal of previously owned communication resources. Previously submitted application operations are never implicitly repeated.

### Authentication

The initial local implementation retains native peer credential verification and existing host application authorization.

Future authentication mechanisms should remain independently composable with compatible transports.

Additional authentication contracts, remote identity mapping, pairing and network transport implementations are deferred until required.

### Filesystem reservations

Future filesystem reservations operate across all Rudra workflows and operating-system users on the machine.

Conflicting reservations must be rejected through transactional validation and acquisition within the shared authoritative persistence domain.

Reservation acquisition and its associated durable workflow outcome must remain coordinated.

Filesystem identity, overlapping directory reservations, reservation lifetime and execution-time revalidation remain subjects of the relevant cleanup implementation.

Rudra reservations coordinate Rudra operations. They do not guarantee exclusion of unrelated applications or operating-system processes.

### Trust boundary

The initial shared persistence model assumes cooperative Rudra host execution.

Deliberate external modification of the SQLite database is outside the initial threat model.

Application integrity validation, owner-scoped operations, transactional safety and execution-time revalidation remain mandatory.

Database tamper detection and stronger persistence isolation may be introduced separately.

### Native resource layout

The initial macOS layout uses the machine-wide application support directory:

```text
/Library/Application Support/Rudra/
    rudra.sqlite
    runtime/
        <uid>/
            rudra.sock
            rudra.lock
```

Database storage is shared between authorized Rudra users.

Native listening endpoints and exclusive host ownership resources remain user-scoped and protected.

The concrete native provisioning mechanism must establish appropriate directory ownership, permissions and SQLite auxiliary-file accessibility.

Native resource layout and implementation details belong to the relevant platform and persistence capabilities.

### Lifecycle and installation

Host execution does not implicitly install or configure operating-system services.

Required machine-wide directories and permissions are established through explicit provisioning.

Host startup fails when required native resources are unavailable or unsuitable.

Service installation and managed startup remain separate capabilities.

## Consequences

- Persistence becomes a shared machine-wide coordination boundary.
- Independent hosts retain native operating-system permissions and user-scoped application execution.
- SQLite transaction contention and concurrent initialization must be handled safely across processes.
- Default client connectivity becomes independent of host persistence configuration.
- Additional transports can be introduced without changing application services or host execution semantics.
- Host endpoint overrides cannot establish additional host instances or independent persistence domains.
- Frontends retain no local application execution or persistence fallback.
- Cross-process and multi-user verification become explicit implementation requirements.

## Superseded decisions

This ADR supersedes directory-scoped host exclusivity and mandatory frontend or host application composition of concrete communication transports.

Earlier architectural decisions concerning SDK-first execution, event sourcing, hierarchical ownership, workflow safety and feature isolation remain applicable.