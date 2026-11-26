import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import 'host_workflow_identity_provider.dart';

/// Indicates that an explicitly requested startup workflow operation
/// did not complete successfully.
///
/// Preserves the application outcome responsible for preventing host
/// readiness. Infrastructure and resource-management failures propagate
/// through their existing boundaries.
final class HostStartupWorkflowException implements Exception {
  /// Creates a startup failure associated with [outcome].
  ///
  /// Throws [ArgumentError] if the operation completed successfully.
  HostStartupWorkflowException({required this.outcome}) {
    final result = outcome;

    if (result is WorkflowOperationResolved &&
        result.resolution.state == WorkflowSubmissionState.completed) {
      throw ArgumentError.value(
        outcome,
        'outcome',
        'A completed operation is not a startup failure.',
      );
    }
  }

  /// Durable application outcome preventing host readiness.
  final WorkflowOperationOutcome outcome;

  /// Formats the unsuccessful operation's stable classification.
  @override
  String toString() {
    return switch (outcome) {
      WorkflowOperationIdempotencyConflict() =>
        'Startup workflow idempotency conflict.',
      WorkflowOperationResolved(:final resolution) =>
        'Startup workflow ${resolution.state.name}'
            ' (${resolution.rejection_code?.name ?? resolution.quarantine_code?.name ?? resolution.receipt.event_id}).',
    };
  }
}

/// Composes the application resources owned by a Rudra host.
///
/// Establishes trusted ownership and constructs a shared workflow
/// runtime and a user-scoped persistence context for one host lifecycle.
/// Separate production hosts open independent connections to one database.
///
/// Exclusive ownership remains established until communication,
/// authoritative state publication and persistence resource disposal
/// have been confirmed.
///
/// Example:
/// ```dart
/// final composition = HostComposition(
///   identity_provider: identity_provider,
///   ownership_provider: ownership_provider,
///   resolve_database: storage.resolve,
///   target_id: 'local-macos',
///   inspector: inspector,
/// );
///
/// await composition.run(
///   shutdown: shutdown.future,
///   on_ready: (os_user_id, workflow) {
///     print(os_user_id);
///     print(workflow?.identity.workflow_id);
///   },
/// );
/// ```
final class HostComposition {
  /// Creates a host composition with its required dependencies.
  ///
  /// [identity_provider] resolves the trusted operating-system owner.
  /// [ownership_provider] establishes exclusive ownership before
  /// application resources are constructed.
  /// [resolve_database] supplies the database file after ownership is acquired.
  /// Native composition validates production provisioning in this callback.
  /// [target_id] identifies the configured filesystem target.
  /// [inspector] supplies read-only inspection for the configured
  /// filesystem target.
  /// [require_existing_wal] verifies that storage has already been configured
  /// for durable multi-user execution. Isolated fixtures may initialize WAL.
  /// [communication_factory] optionally substitutes the host-owned
  /// communication implementation using its assembled messaging
  /// configuration.
  ///
  /// Construction retains configuration without acquiring ownership,
  /// opening persistence or binding communication endpoints.
  HostComposition({
    required this.identity_provider,
    required this.ownership_provider,
    required this.resolve_database,
    required this.target_id,
    required this.inspector,
    this.communication_factory,
    this.require_existing_wal = false,
  });

  /// Platform implementation responsible for trusted identity resolution.
  final HostIdentityProvider identity_provider;

  /// Platform implementation responsible for exclusive host ownership.
  final HostOwnershipProvider ownership_provider;

  /// Resolves the database backing the host-owned persistence context.
  final FutureOr<File> Function() resolve_database;

  /// Configured filesystem target used by explicit startup operations.
  final String target_id;

  /// Platform-independent inspection capability for the configured target.
  ///
  /// Its concrete implementation is selected by native host composition.
  final TargetInspector inspector;

  /// Optional replacement for the communication subsystem owned by the host.
  final HostCommunicationFactory? communication_factory;

  /// Whether persistence requires an already provisioned WAL-mode file.
  final bool require_existing_wal;

  /// Records whether this composition has entered its lifecycle.
  bool _has_run = false;

  /// Composes and executes one exclusively owned host lifecycle.
  ///
  /// [shutdown] supplies the externally managed termination signal.
  /// [startup_root] optionally requests explicit workflow establishment
  /// at a validated target-native filesystem location.
  /// [on_ready] receives the trusted owner and verified current
  /// workflow after initial authoritative state publication and
  /// before client session admission.
  ///
  /// Acquires ownership before constructing application resources
  /// and retains it until communication, authoritative state
  /// publication and persistence disposal have been confirmed.
  ///
  /// Returns after graceful termination and resource disposal.
  ///
  /// Throws [HostAlreadyOwnedException] when this operating-system user
  /// already has a host, or [StateError] for repeated execution or invalid
  /// trusted identity.
  ///
  /// Application, communication, state publication, ownership and
  /// persistence failures propagate to the caller.
  /// Throws [HostStartupWorkflowException] when an explicitly requested
  /// workflow operation does not complete successfully.
  Future<void> run({
    required Future<void> shutdown,
    required void Function(String os_user_id, WorkflowSnapshot? workflow)
    on_ready,
    TargetPath? startup_root,
  }) async {
    if (_has_run) {
      throw StateError('Host composition has already been run.');
    }

    // Claim composition ownership before asynchronous initialization
    // to prevent overlapping execution of the same instance.
    _has_run = true;

    final os_user_id = await identity_provider.resolve();

    if (os_user_id.trim().isEmpty) {
      throw StateError('Trusted OS-user identity must not be blank.');
    }

    // Competing hosts fail before opening persistence or binding endpoints.
    final ownership = await ownership_provider.acquire();

    var persistence_closed = true;

    RudraHost? host;

    try {
      final database = await resolve_database();
      if (!await database.parent.exists()) {
        throw FileSystemException(
          'The host database directory must already exist.',
          database.parent.path,
        );
      }

      final runtime = WorkflowRuntime.standard();

      final persistence = RudraSqlitePersistence(
        database_file: database,
        scope_id: os_user_id,
        require_existing_wal: require_existing_wal,
        runtime: runtime,
      );

      persistence_closed = false;

      try {
        final application = WorkflowApplication(
          runtime: runtime,
          persistence: persistence,
          identity_provider: HostWorkflowIdentityProvider(
            os_user_id: os_user_id,
          ),
          os_user_id: os_user_id,
        );

        final filesystem_application = FilesystemApplication(
          target_id: target_id,
          inspector: inspector,
        );

        host = RudraHost(
          application: application,
          filesystem_application: filesystem_application,
          validate_start: _validate_start,
          communication_factory: communication_factory,
        );

        await host.run(
          shutdown: shutdown,
          on_startup: (application) async {
            // Explicit startup is a new user intention, identified once before
            // invoking the authoritative application operation.
            if (startup_root != null) {
              _validate_start(target_id, startup_root);

              final idempotency_key = Uuid().v4();

              final outcome = await application.start(
                target_id: target_id,
                root: startup_root,
                idempotency_key: idempotency_key,
              );

              if (outcome is! WorkflowOperationResolved ||
                  outcome.resolution.state !=
                      WorkflowSubmissionState.completed) {
                throw HostStartupWorkflowException(outcome: outcome);
              }
            }
          },
          on_ready: (state) {
            on_ready(os_user_id, state.workflows.current_workflow);
          },
        );
      } finally {
        // Host execution drains admitted handlers and authoritative
        // observation before persistence disposal.
        await persistence.close();

        persistence_closed = true;
      }
    } finally {
      final host_released = host?.resources_released ?? true;

      // Fail closed when either resource owner cannot confirm disposal.
      // Process termination releases native exclusive ownership rather
      // than admitting another host while resources may remain active.
      if (host_released && persistence_closed) {
        await ownership.release();
      }
    }
  }

  /// Validates workflow establishment against the configured local target.
  ///
  /// [requested_target_id] must identify this host's configured target.
  /// [root] must be absolute using the local target's native path syntax.
  ///
  /// Throws [ArgumentError] for an unsupported target or relative root.
  ///
  /// Validation preserves the original path and performs no filesystem
  /// inspection or persistence operation.
  void _validate_start(String requested_target_id, TargetPath root) {
    if (requested_target_id != target_id) {
      throw ArgumentError.value(
        requested_target_id,
        'target_id',
        'The requested target is not configured on this host.',
      );
    }

    // This composition currently represents a local filesystem target.
    // Native path interpretation belongs here rather than in the SDK.
    if (!Directory(root.value).isAbsolute) {
      throw ArgumentError.value(
        root.value,
        'root',
        'A local workflow requires an absolute root.',
      );
    }
  }
}
