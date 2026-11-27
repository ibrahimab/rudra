import 'dart:async';
import 'dart:io';

/// Coordinates graceful termination of a macOS host process.
///
/// Translates operating-system termination signals into an
/// asynchronous shutdown notification consumed by the portable
/// SDK host lifecycle.
///
/// Signal subscriptions remain active for the duration of the
/// supplied operation, keeping the process available while the
/// host awaits termination.
///
/// Example:
/// ```dart
/// final lifecycle = MacOsHostShutdown();
///
/// await lifecycle.run((shutdown) async {
///   print('Host ready');
///   await shutdown;
///   print('Host shutting down');
/// });
/// ```
final class MacOsHostShutdown {
  /// Creates a macOS process shutdown coordinator.
  ///
  /// Signal subscriptions are established when [run] is invoked.
  const MacOsHostShutdown();

  /// Executes [operation] within a managed process lifecycle.
  ///
  /// The operation receives a future that completes when the
  /// process receives SIGINT or SIGTERM.
  ///
  /// Returns when the supplied operation completes. Signal
  /// subscriptions are released regardless of its outcome.
  ///
  /// Throws [UnsupportedError] outside macOS. Signal registration
  /// and operation failures propagate to the caller.
  Future<void> run(
    Future<void> Function(Future<void> shutdown) operation,
  ) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('macOS host shutdown requires macOS.');
    }

    final shutdown = Completer<void>();

    // Both termination signals converge on the same notification.
    // Subsequent signals must not complete the future again.
    void request_shutdown(ProcessSignal signal) {
      if (!shutdown.isCompleted) {
        shutdown.complete();
      }
    }

    final interrupt = ProcessSignal.sigint.watch().listen(request_shutdown);

    try {
      final terminate = ProcessSignal.sigterm.watch().listen(request_shutdown);

      try {
        await operation(shutdown.future);
      } finally {
        await terminate.cancel();
      }
    } finally {
      // Release the first subscription even if registration
      // of the second signal fails.
      await interrupt.cancel();
    }
  }
}
