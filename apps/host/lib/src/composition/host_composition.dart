import 'dart:io';

import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../development/host_transport_probe.dart';

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
/// Example:
/// ```dart
/// final composition = HostComposition(
///   identity_provider: identity_provider,
///   ownership_provider: ownership_provider,
///   transport: transport,
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
  /// [transport] establishes the authenticated local communication
  /// endpoint within the exclusively owned persistence scope.
  /// [data_directory] identifies an existing, dedicated development
  /// persistence directory.
  /// [target_id] identifies the configured filesystem target.
  ///
  /// Construction retains configuration without acquiring ownership
  /// or opening SQLite.
  HostComposition({
    required this.identity_provider,
    required this.ownership_provider,
    required this.transport,
    required this.data_directory,
    required this.target_id,
  });

  /// Platform implementation responsible for trusted identity resolution.
  final HostIdentityProvider identity_provider;

  /// Platform implementation responsible for exclusive host ownership.
  final HostOwnershipProvider ownership_provider;

  /// Platform transport establishing authenticated client connections.
  final HostTransport transport;

  /// Dedicated directory containing host development persistence.
  final Directory data_directory;

  /// Configured filesystem target used by explicit startup operations.
  final String target_id;

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
  /// workflow after startup operations have completed.
  ///
  /// Acquires ownership before constructing application resources
  /// and retains it until persistence disposal has completed.
  ///
  /// Returns after graceful termination and resource disposal.
  ///
  /// Throws [HostAlreadyOwnedException] when the persistence scope
  /// already has an owner, or [StateError] for repeated execution,
  /// unavailable storage or invalid trusted identity.
  ///
  /// Application, ownership and persistence failures propagate
  /// to the caller.
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

    // Resolve one canonical directory for both ownership and
    // persistence so alternative path spellings cannot establish
    // independent ownership of the same storage location.
    final scope_directory = await data_directory.resolveSymbolicLinks();

    final scoped_database = File.fromUri(
      Directory(scope_directory).uri.resolve(database_filename),
    );

    // Competing hosts must fail before constructing or accessing
    // any workflow persistence resources.
    final ownership = await ownership_provider.acquire(
      scope_directory: scope_directory,
    );

    var persistence_closed = true;
    var listener_closed = true;

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

        final host = RudraHost(application: application);

        // Exclusive ownership is already established. Only the
        // authorized host may prepare and bind its communication endpoint.
        final listener = await transport.listen(
          scope_directory: scope_directory,
          os_user_id: os_user_id,
        );

        listener_closed = false;

        try {
          await host.run(
            listener: listener,
            shutdown: shutdown,
            handle_connection: run_host_transport_probe,
            on_startup: (application) async {
              // Explicit development startup remains the only operation
              // authorized to establish a workflow during initialization.
              if (startup_root != null) {
                await application.start(
                  target_id: target_id,
                  root: startup_root,
                );
              }

              final state = await application.read_state();

              // Report readiness only after endpoint binding and
              // authoritative workflow restoration have succeeded.
              on_ready(os_user_id, state.workflows.current_workflow);
            },
          );
        } finally {
          // The SDK normally disposes of the listener. Confirm disposal
          // here before permitting release of exclusive host ownership.
          await listener.close();
          listener_closed = true;
        }
      } finally {
        // Close persistence while exclusive ownership remains
        // acquired, including after failed startup operations.
        await persistence.close();

        persistence_closed = true;
      }
    } finally {
      // Fail closed if listener or persistence disposal could not
      // be confirmed. Process termination releases native ownership
      // rather than admitting another host prematurely.
      if (listener_closed && persistence_closed) {
        await ownership.release();
      }
    }
  }
}
