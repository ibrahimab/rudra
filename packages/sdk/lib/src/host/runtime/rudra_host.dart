import '../../workflow/application/workflow_application.dart';

import '../platform/contracts/host_connection.dart';
import '../platform/contracts/host_listener.dart';

import 'host_connection_service.dart';

/// Coordinates the lifecycle of a configured Rudra host.
///
/// Retains a single workflow application for the duration of the
/// host lifecycle, providing a central execution context for
/// trusted application operations.
///
/// The composition root supplies the configured application,
/// manages its persistence resources and provides the shutdown
/// signal appropriate to the execution environment.
///
/// Each host instance represents one execution lifecycle.
/// Restarting the host requires constructing a new instance.
///
/// Example:
/// ```dart
/// final host = RudraHost(application: application);
///
/// await host.run(
///   listener: listener,
///   shutdown: shutdown.future,
///   handle_connection: handle_connection,
///   on_startup: (application) async {
///     final state = await application.read_state();
///     print(state.workflows.current_workflow);
///   },
/// );
/// ```
final class RudraHost {
  /// Creates a host bound to the configured [application].
  ///
  /// [application] supplies the trusted workflow operations used
  /// throughout the host lifecycle. Its associated persistence
  /// resources must remain available until [run] completes.
  ///
  /// The caller retains ownership of those resources.
  RudraHost({required WorkflowApplication application})
    : _application = application;

  /// Retained application context responsible for trusted workflow
  /// submission, processing, restoration and state observation.
  final WorkflowApplication _application;

  /// Records whether this instance has entered its execution lifecycle.
  ///
  /// Prevents repeated or concurrent execution of the same host instance.
  bool _has_run = false;

  /// Executes the configured host and connection lifecycle.
  ///
  /// [listener] supplies authenticated client connections.
  /// Ownership transfers to this execution after the lifecycle
  /// has been successfully claimed.
  ///
  /// [handle_connection] executes an independent client session.
  /// [shutdown] represents the external termination notification.
  /// [on_startup] optionally initializes the retained application
  /// before accepting client sessions.
  ///
  /// Returns after shutdown, listener disposal and termination
  /// of outstanding connection handlers.
  ///
  /// Throws [StateError] if this host has already been executed.
  /// Startup and connection-service failures propagate.
  Future<void> run({
    required HostListener listener,
    required Future<void> shutdown,
    required Future<void> Function(HostConnection) handle_connection,
    Future<void> Function(WorkflowApplication)? on_startup,
  }) async {
    if (_has_run) {
      throw StateError('Host has already been run.');
    }

    // Claim the lifecycle before starting asynchronous work.
    _has_run = true;

    const service = HostConnectionService();

    await service.run(
      listener: listener,
      shutdown: shutdown,
      handle_connection: handle_connection,
      on_startup: () async {
        if (on_startup != null) {
          await on_startup(_application);
        }
      },
    );
  }
}
