import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_communication/rudra_communication.dart';

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

/// Constructs authenticated connectivity for an exclusively owned
/// host application environment.
///
/// [scope_directory] identifies the canonical application scope.
///
/// [os_user_id] identifies the trusted operating-system owner.
///
/// Returns a configured inactive transport selected by trusted
/// application composition.
///
/// Implementations retain configuration without binding endpoints
/// or acquiring communication resources.
///
/// Example:
/// ```dart
/// final HostTransportFactory factory = ({
///   required scope_directory,
///   required os_user_id,
/// }) {
///   return MacOsUnixTransport(
///     scope_directory: scope_directory,
///     os_user_id: os_user_id,
///   );
/// };
/// ```
typedef HostTransportFactory = Transport Function({
  required String scope_directory,
  required String os_user_id,
});

/// Composes the application resources owned by a Rudra host.
///
/// Establishes trusted ownership and constructs a shared workflow
/// runtime, application and persistence context for one host
/// execution lifecycle.
///
/// The configured development directory isolates host persistence
/// from the existing frontend-owned production database.
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
///   data_directory: development_directory,
///   target_id: 'local-macos',
///   inspector: inspector,
///   transport_factory: transport_factory,
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
  /// [data_directory] identifies an existing, dedicated development
  /// persistence directory.
  /// [target_id] identifies the configured filesystem target.
  /// [inspector] supplies read-only inspection for the configured
  /// filesystem target.
  /// [transport_factory] constructs configured authenticated
  /// connectivity after trusted identity and exclusive application
  /// ownership have been established.
  /// [communication_factory] optionally substitutes the host-owned
  /// communication implementation using its assembled messaging
  /// configuration.
  ///
  /// Construction retains configuration without acquiring ownership,
  /// opening persistence or binding communication endpoints.
  HostComposition({
    required this.identity_provider,
    required this.ownership_provider,
    required this.data_directory,
    required this.target_id,
    required this.inspector,
    required this.transport_factory,
    this.communication_factory,
  });

  /// Platform implementation responsible for trusted identity resolution.
  final HostIdentityProvider identity_provider;

  /// Platform implementation responsible for exclusive host ownership.
  final HostOwnershipProvider ownership_provider;

  /// Dedicated directory containing host development persistence
  /// and its exclusively owned local communication endpoint.
  final Directory data_directory;

  /// Configured filesystem target used by explicit startup operations.
  final String target_id;

  /// Platform-independent inspection capability for the configured target.
  ///
  /// Its concrete implementation is selected by native host composition.
  final TargetInspector inspector;

  /// Constructs configured connectivity for the trusted host environment.
  ///
  /// Invoked after canonical scope resolution and successful exclusive
  /// ownership acquisition.
  final HostTransportFactory transport_factory;

  /// Optional factory substituting the host-owned communication subsystem.
  ///
  /// Receives the configured transport and validated application
  /// messaging configuration assembled by the host.
  final HostCommunicationFactory? communication_factory;

  /// Filename reserved for the standalone development host.
  static const String database_filename = 'rudra-host-dev.sqlite';

  /// Records whether this composition has entered its lifecycle.
  bool _has_run = false;

  /// Returns the configured development database location.
  ///
  /// Resolving the location does not initialize persistence.
  File get database_file =>
      File.fromUri(data_directory.absolute.uri.resolve(database_filename));

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
  /// Throws [HostAlreadyOwnedException] when the persistence scope
  /// already has an owner, or [StateError] for repeated execution,
  /// unavailable storage or invalid trusted identity.
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

    if (!await data_directory.exists()) {
      throw StateError('The host development directory must already exist.');
    }

    // Resolve one canonical scope so alternative path spellings
    // cannot establish independent ownership of the same resources.
    final scope_directory = await data_directory.resolveSymbolicLinks();

    final scoped_database = File.fromUri(
      Directory(scope_directory).uri.resolve(database_filename),
    );

    // Competing hosts must fail before constructing or accessing
    // application persistence or communication resources.
    final ownership = await ownership_provider.acquire(
      scope_directory: scope_directory,
    );

    var persistence_closed = true;

    RudraHost? host;

    try {
      // Configure connectivity only after the canonical application
      // scope is exclusively owned by the trusted host.
      final transport = transport_factory(
        scope_directory: scope_directory,
        os_user_id: os_user_id,
      );

      final runtime = WorkflowRuntime.standard();

      final persistence = RudraSqlitePersistence(
        database_file: scoped_database,
        scope_id: 'rudra-host-dev:$os_user_id',
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
          transport: transport,
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
