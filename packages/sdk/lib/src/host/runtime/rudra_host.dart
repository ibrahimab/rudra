import 'package:rudra_communication/rudra_communication.dart';

import '../../workflow/application/workflow_application.dart';

/// Coordinates the lifecycle of a configured Rudra host.
///
/// Retains one workflow application and one communication instance
/// throughout its execution lifecycle.
///
/// The caller supplies the trusted application context and retains
/// ownership of its associated persistence resources.
///
/// Communication is constructed and maintained internally unless
/// an alternative implementation is explicitly supplied.
///
/// Each host instance represents one execution lifecycle.
///
/// Example:
/// ```dart
/// final host = RudraHost(application: application);
///
/// await host.run(
///   scope_directory: scope,
///   os_user_id: trusted_owner,
///   shutdown: shutdown.future,
///   on_startup: (application) async {
///     final state = await application.read_state();
///     print(state.workflows.current_workflow);
///   },
/// );
/// ```
final class RudraHost {
  /// Creates a host bound to the configured [application].
  ///
  /// [application] supplies trusted workflow operations throughout
  /// the host lifecycle. The caller retains ownership of its
  /// associated persistence resources.
  ///
  /// [communication] optionally substitutes the default communication
  /// implementation. The supplied instance must be unused and its
  /// execution lifecycle transfers to this host.
  ///
  /// Construction does not initialize persistence, bind communication
  /// endpoints or execute application operations.
  RudraHost({
    required WorkflowApplication application,
    Communication? communication,
  }) : _application = application,
       communication = communication ?? Communication();

  /// Retained application context responsible for trusted workflow
  /// submission, processing, restoration and state observation.
  final WorkflowApplication _application;

  /// Communication subsystem owned by this host.
  ///
  /// Exposes the retained communication instance for inspection
  /// and communication-specific capabilities.
  ///
  /// Its execution lifecycle remains the responsibility of this host.
  final Communication communication;

  /// Whether this instance has entered its execution lifecycle.
  bool _has_run = false;

  /// Executes the configured host lifecycle.
  ///
  /// [scope_directory] identifies the exclusively owned communication
  /// scope established by trusted application composition.
  ///
  /// [os_user_id] identifies the trusted operating-system owner
  /// associated with the application.
  ///
  /// [shutdown] supplies the external termination notification.
  ///
  /// [on_startup] optionally initializes the retained application
  /// before accepting client sessions.
  ///
  /// Returns after communication resource disposal and completion
  /// of previously admitted application handlers.
  ///
  /// Throws [StateError] if this host has already been executed.
  /// Application initialization and communication failures propagate.
  Future<void> run({
    required String scope_directory,
    required String os_user_id,
    required Future<void> shutdown,
    Future<void> Function(WorkflowApplication)? on_startup,
  }) async {
    if (_has_run) {
      throw StateError('Host has already been run.');
    }

    // Claim the host lifecycle before initializing its
    // internally owned communication subsystem.
    _has_run = true;

    await communication.run(
      scope_directory: scope_directory,
      os_user_id: os_user_id,
      shutdown: shutdown,
      on_startup: on_startup == null ? null : () => on_startup(_application),
    );
  }
}
