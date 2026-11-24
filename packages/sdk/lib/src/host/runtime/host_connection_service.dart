import 'dart:async';

import '../platform/contracts/host_connection.dart';
import '../platform/contracts/host_listener.dart';

/// Coordinates concurrent connections during a host lifecycle.
///
/// Accepts authenticated connections from a configured listener
/// and executes each connection handler independently.
///
/// Connection-local failures terminate the affected session.
/// Listener and resource disposal failures terminate the service.
///
/// Example:
/// ```dart
/// const service = HostConnectionService();
///
/// await service.run(
///   listener: listener,
///   shutdown: shutdown.future,
///   handle_connection: handle_connection,
/// );
/// ```
final class HostConnectionService {
  /// Creates a portable connection lifecycle coordinator.
  const HostConnectionService();

  /// Executes authenticated sessions until shutdown.
  ///
  /// [listener] supplies authorized connections and is owned by
  /// this execution until disposal completes.
  /// [shutdown] supplies the external termination notification.
  /// [handle_connection] executes an individual session.
  /// [on_startup] optionally initializes application state before
  /// connection acceptance begins.
  ///
  /// Returns after closing the listener and awaiting outstanding
  /// connection handlers.
  ///
  /// Startup, listener and resource disposal failures propagate.
  /// Individual handler failures remain isolated to their sessions.
  Future<void> run({
    required HostListener listener,
    required Future<void> shutdown,
    required Future<void> Function(HostConnection) handle_connection,
    Future<void> Function()? on_startup,
  }) async {
    final failure = Completer<void>();
    final active = <Future<void>>{};

    StreamSubscription<HostConnection>? subscription;

    var stopping = false;

    Object? disposal_error;
    StackTrace? disposal_stack;

    // Attach the shutdown and listener-failure observers before
    // startup can perform asynchronous application operations.
    final termination = Future.any<void>([shutdown, failure.future]);

    // Observe an early termination failure while startup is
    // running. The original result is still awaited below.
    termination.ignore();

    try {
      if (on_startup != null) {
        await on_startup();
      }

      subscription = listener.connections.listen(
        (connection) {
          late final Future<void> task;

          // Do not await a connection handler in the acceptance
          // callback. Each client requires an independent session.
          task = _serve_connection(connection, handle_connection)
              .then<void>(
                (_) {},
                onError: (Object error, StackTrace stack) {
                  disposal_error ??= error;
                  disposal_stack ??= stack;

                  if (!stopping && !failure.isCompleted) {
                    failure.completeError(error, stack);
                  }
                },
              )
              .whenComplete(() {
                active.remove(task);
              });

          active.add(task);
        },
        onError: (Object error, StackTrace stack) {
          if (!stopping && !failure.isCompleted) {
            failure.completeError(error, stack);
          }
        },
        onDone: () {
          if (!stopping && !failure.isCompleted) {
            failure.completeError(
              StateError('Host listener ended unexpectedly.'),
            );
          }
        },
      );

      await termination;
    } finally {
      stopping = true;

      try {
        // Closing native connections unblocks handlers that
        // are awaiting incoming transport data.
        await listener.close();
      } finally {
        try {
          await subscription?.cancel();
        } finally {
          // Application resources remain available until all
          // accepted sessions have actually terminated.
          await Future.wait(active.toList(growable: false));
        }
      }

      if (disposal_error != null) {
        Error.throwWithStackTrace(disposal_error!, disposal_stack!);
      }
    }
  }

  /// Executes [handler] for one authenticated [connection].
  ///
  /// Isolates session failures from other connected clients.
  /// Returns after disposing of the connection.
  ///
  /// Connection disposal failures propagate to the coordinator.
  Future<void> _serve_connection(
    HostConnection connection,
    Future<void> Function(HostConnection) handler,
  ) async {
    try {
      await handler(connection);
    } catch (_) {
      // A failed client session must not terminate the shared
      // host or interrupt other independent connections.
    } finally {
      await connection.close();
    }
  }
}
