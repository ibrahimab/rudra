import 'dart:async';

import '../transport/contracts/transport_connection.dart';
import '../transport/contracts/transport_listener.dart';

/// Coordinates concurrent connections during a communication lifecycle.
///
/// Accepts authenticated connections from a configured listener
/// and executes each connection handler independently.
///
/// Connection-local failures terminate the affected session.
/// Listener and resource disposal failures terminate the service.
///
/// Each service instance owns one listener execution lifecycle.
/// Resource disposal remains independently observable through
/// [resources_released], including after unsuccessful execution.
///
/// Example:
/// ```dart
/// final service = ConnectionService();
///
/// await service.run(
///   listener: listener,
///   shutdown: shutdown.future,
///   handle_connection: handle_connection,
/// );
///
/// assert(service.resources_released);
/// ```
final class ConnectionService {
  /// Creates an inactive connection lifecycle coordinator.
  ///
  /// Construction does not acquire a listener or accept connections.
  ConnectionService();

  /// Records whether this service has claimed its execution lifecycle.
  bool _has_run = false;

  /// Records whether all owned resources have been released.
  ///
  /// Remains false while execution is active or resource disposal
  /// cannot be confirmed.
  bool _resources_released = true;

  /// Whether all resources owned by this service have been released.
  ///
  /// Returns true before execution and after confirmed disposal.
  /// Returns false during execution or following failed disposal.
  ///
  /// Successful disposal does not imply successful session execution.
  bool get resources_released => _resources_released;

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
  /// Throws [StateError] when this service has already been executed.
  ///
  /// Startup, listener and resource disposal failures propagate.
  /// Individual handler failures remain isolated to their sessions.
  ///
  /// [resources_released] confirms whether listener disposal and
  /// termination of outstanding sessions completed successfully,
  /// independently of the execution result.
  Future<void> run({
    required TransportListener listener,
    required Future<void> shutdown,
    required Future<void> Function(TransportConnection) handle_connection,
    Future<void> Function()? on_startup,
  }) async {
    if (_has_run) {
      throw StateError('Connection service has already been run.');
    }

    // Claim the lifecycle before accepting asynchronous work.
    // Resource ownership remains active until disposal is confirmed.
    _has_run = true;
    _resources_released = false;

    final failure = Completer<void>();
    final active = <Future<void>>{};

    StreamSubscription<TransportConnection>? subscription;

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

      // Reaching this point establishes that the listener, subscription
      // and outstanding connection handlers have all been disposed of.
      _resources_released = true;
    }
  }

  /// Executes [handler] for one authenticated [connection].
  ///
  /// Isolates session failures from other connected clients.
  /// Returns after disposing of the connection.
  ///
  /// Connection disposal failures propagate to the coordinator.
  Future<void> _serve_connection(
    TransportConnection connection,
    Future<void> Function(TransportConnection) handler,
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
