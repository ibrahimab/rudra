import '../../workflow/application/workflow_application.dart';

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
/// import 'dart:async';
///
/// Future<void> run_host(
///   WorkflowApplication application,
///   Completer<void> shutdown,
/// ) async {
///   final host = RudraHost(application: application);
///
///   await host.run(
///     shutdown: shutdown.future,
///     on_startup: (application) async {
///       final state = await application.read_state();
///       print(state.workflows.current_workflow);
///     },
///   );
/// }
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

  /// Executes the configured host lifecycle.
  ///
  /// [shutdown] represents the externally managed termination signal.
  ///
  /// [on_startup] optionally performs an explicitly configured
  /// startup operation using the retained application. The operation
  /// completes before the host begins awaiting termination.
  ///
  /// Returns when startup has completed and shutdown has been
  /// requested. Startup and shutdown failures propagate to the caller,
  /// allowing the composition root to dispose of owned resources.
  ///
  /// Throws [StateError] if this instance has previously entered
  /// its execution lifecycle.
  Future<void> run({
    required Future<void> shutdown,
    Future<void> Function(WorkflowApplication)? on_startup,
  }) async {
    if (_has_run) {
      throw StateError('Host has already been run.');
    }

    // Claim the execution lifecycle before awaiting asynchronous
    // work to prevent overlapping calls from starting the same host.
    _has_run = true;

    // Complete explicitly configured startup operations before
    // entering the host's long-running execution phase.
    if (on_startup != null) {
      await on_startup(_application);
    }

    // Delegate termination to the supplied lifecycle signal,
    // keeping platform-specific signal handling outside the SDK.
    await shutdown;
  }
}
