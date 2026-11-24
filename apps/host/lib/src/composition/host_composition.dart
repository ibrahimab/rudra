import 'dart:io';

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
  ///
  /// Construction retains configuration without acquiring ownership
  /// or opening SQLite.
  HostComposition({
    required this.identity_provider,
    required this.ownership_provider,
    required this.data_directory,
    required this.target_id,
  });

  /// Platform implementation responsible for trusted identity resolution.
  final HostIdentityProvider identity_provider;

  /// Platform implementation responsible for exclusive host ownership.
  final HostOwnershipProvider ownership_provider;

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

        await host.run(
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
        // Close persistence while exclusive ownership remains
        // acquired, including after failed startup operations.
        await persistence.close();

        persistence_closed = true;
      }
    } finally {
      // Fail closed if persistence disposal could not be confirmed.
      // In that situation, process termination releases the native
      // ownership resource rather than admitting another host early.
      if (persistence_closed) {
        await ownership.release();
      }
    }
  }
}
