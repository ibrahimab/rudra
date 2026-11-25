import 'dart:io';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import 'host_workflow_identity_provider.dart';

/// Composes the application resources owned by a Rudra host.
///
/// Establishes trusted ownership and constructs a shared workflow
/// runtime, application and persistence context for one host
/// execution lifecycle.
///
/// The configured development directory isolates host persistence
/// from the existing frontend-owned production database.
///
/// Exclusive ownership remains established until communication
/// and persistence resource disposal have been confirmed.
///
/// Example:
/// ```dart
/// final composition = HostComposition(
///   identity_provider: identity_provider,
///   ownership_provider: ownership_provider,
///   data_directory: development_directory,
///   target_id: 'local-macos',
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
  /// [communication] optionally substitutes the host's communication
  /// implementation. A supplied instance must be unused and its
  /// execution lifecycle transfers to the constructed host.
  ///
  /// Construction retains configuration without acquiring ownership,
  /// opening persistence or binding communication endpoints.
  HostComposition({
    required this.identity_provider,
    required this.ownership_provider,
    required this.data_directory,
    required this.target_id,
    this.communication,
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

  /// Optional substitute for the host-owned communication subsystem.
  ///
  /// When absent, the host constructs its default implementation.
  final Communication? communication;

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
  /// workflow after communication binding and application initialization.
  ///
  /// Acquires ownership before constructing application resources
  /// and retains it until communication and persistence disposal
  /// have both been confirmed.
  ///
  /// Returns after graceful termination and resource disposal.
  ///
  /// Throws [HostAlreadyOwnedException] when the persistence scope
  /// already has an owner, or [StateError] for repeated execution,
  /// unavailable storage or invalid trusted identity.
  ///
  /// Application, communication, ownership and persistence failures
  /// propagate to the caller.
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

        host = RudraHost(
          application: application,
          communication: communication,
        );

        await host.run(
          scope_directory: scope_directory,
          os_user_id: os_user_id,
          shutdown: shutdown,
          on_startup: (application) async {
            // Only an explicitly requested startup operation
            // may establish a workflow.
            if (startup_root != null) {
              await application.start(target_id: target_id, root: startup_root);
            }

            // Restore authoritative application state before
            // reporting successful host initialization.
            final state = await application.read_state();

            on_ready(os_user_id, state.workflows.current_workflow);
          },
        );
      } finally {
        // Host execution has terminated before persistence disposal,
        // ensuring session handlers no longer use the application.
        await persistence.close();

        persistence_closed = true;
      }
    } finally {
      final communication_released =
          host?.communication.resources_released ?? true;

      // Fail closed when either resource owner cannot confirm disposal.
      // Process termination releases native exclusive ownership rather
      // than admitting another host while resources may remain active.
      if (communication_released && persistence_closed) {
        await ownership.release();
      }
    }
  }
}
