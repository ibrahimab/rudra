import 'dart:async';

import '../transport/contracts/transport_connection.dart';
import '../transport/contracts/transport_listener.dart';
import 'default_message_session.dart';

/// Coordinates concurrent typed sessions over authenticated connections.
///
/// Owns one listening lifecycle and maintains independent
/// message sessions for accepted connections.
///
/// Session execution failures remain isolated to their respective
/// clients. Listener and resource disposal failures terminate the
/// coordinator and prevent confirmation of successful release.
///
/// Example:
/// ```dart
/// final service = ConnectionService();
///
/// await service.run(
///   listeners: [listener],
///   shutdown: shutdown.future,
///   open_session: open_session,
/// );
///
/// assert(service.resources_released);
/// ```
final class ConnectionService {
  /// Creates an inactive session lifecycle coordinator.
  ///
  /// Construction does not acquire a listener or accept connections.
  /// [maximum_sessions] limits admitted sessions across all listeners,
  /// including sessions still draining their application handlers.
  /// Throws [ArgumentError] when the limit is less than one.
  ConnectionService({int maximum_sessions = 64})
    : _maximum_sessions = maximum_sessions {
    if (maximum_sessions < 1) {
      throw ArgumentError.value(
        maximum_sessions,
        'maximum_sessions',
        'Must be positive.',
      );
    }
  }

  final int _maximum_sessions;

  /// Whether this coordinator has claimed its execution lifecycle.
  bool _has_run = false;

  /// Whether all owned resources have been successfully released.
  bool _resources_released = true;

  /// Whether listener and session disposal have been confirmed.
  ///
  /// Returns true before execution and after successful disposal.
  /// Returns false during execution or following disposal failure.
  bool get resources_released => _resources_released;

  /// Executes concurrent authenticated sessions until termination.
  ///
  /// [listeners] supply authenticated connections and transfer their
  /// execution lifecycles to this coordinator.
  ///
  /// [shutdown] supplies the external termination notification.
  ///
  /// [open_session] constructs an executing message session for
  /// an accepted connection. Successful opening transfers
  /// connection ownership to the returned session.
  ///
  /// [on_startup] optionally initializes application resources
  /// before accepting connections.
  ///
  /// Returns after listener disposal, session resource disposal
  /// and completion of outstanding application handlers.
  ///
  /// Throws [StateError] for repeated execution.
  /// Startup, listener and resource disposal failures propagate.
  /// Individual session execution failures remain isolated.
  Future<void> run({
    required List<TransportListener> listeners,
    required Future<void> shutdown,
    required DefaultMessageSession Function(TransportConnection) open_session,
    Future<void> Function()? on_startup,
  }) async {
    if (_has_run) {
      throw StateError('Connection service has already been run.');
    }

    _has_run = true;
    _resources_released = false;

    final failure = Completer<void>();

    final active = <Future<void>>{};
    final sessions = <DefaultMessageSession>{};

    final subscriptions = <StreamSubscription<TransportConnection>>[];

    var stopping = false;

    Object? disposal_error;
    StackTrace? disposal_stack;

    // Observe termination before asynchronous startup begins.
    final termination = Future.any<void>([shutdown, failure.future]);

    termination.ignore();

    try {
      if (on_startup != null) {
        await on_startup();
      }

      for (final listener in listeners) {
        subscriptions.add(
          listener.connections.listen(
            (connection) {
              late final Future<void> task;

              // Count draining sessions until their handlers have released
              // application resources. Rejection still disposes the transport.
              final execution = sessions.length >= _maximum_sessions
                  ? Future<void>.sync(connection.close)
                  : _serve_connection(
                      connection: connection,
                      open_session: open_session,
                      sessions: sessions,
                    );

              task = execution
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
          ),
        );
      }

      await termination;
    } finally {
      stopping = true;

      try {
        // Stop accepting native connections and terminate
        // connections retained by the listener.
        await Future.wait(listeners.map((listener) async => listener.close()));
      } finally {
        try {
          await Future.wait(
            subscriptions.map((subscription) async => subscription.cancel()),
          );
        } finally {
          try {
            // Explicitly terminate remaining message sessions
            // even when listener disposal reports failure.
            await Future.wait<void>(
              sessions
                  .toList(growable: false)
                  .map((session) => session.close()),
            );
          } finally {
            // Application resources must remain available until
            // every admitted handler has finished executing.
            await Future.wait<void>(active.toList(growable: false));
          }
        }
      }

      final error = disposal_error;

      if (error != null) {
        Error.throwWithStackTrace(error, disposal_stack!);
      }

      _resources_released = true;
    }
  }

  /// Executes one authenticated connection as a typed session.
  ///
  /// [connection] supplies the accepted native transport.
  /// [open_session] establishes its object-level session.
  /// [sessions] tracks sessions retained by the coordinator.
  ///
  /// Failed session initialization disposes of the untransferred
  /// transport connection.
  ///
  /// Session execution failures remain isolated. Resource disposal
  /// failures propagate to the coordinator.
  ///
  /// Returns after session disposal and application-handler draining.
  Future<void> _serve_connection({
    required TransportConnection connection,
    required DefaultMessageSession Function(TransportConnection) open_session,
    required Set<DefaultMessageSession> sessions,
  }) async {
    final DefaultMessageSession session;

    try {
      session = open_session(connection);
    } catch (_) {
      // Session opening did not transfer connection ownership.
      await connection.close();

      return;
    }

    sessions.add(session);

    try {
      try {
        await session.done;
      } catch (_) {
        // Protocol and transport execution failures remain
        // isolated to the affected client session.
      }
    } finally {
      try {
        // Unlike session.done, close reports the retained
        // resource disposal result independently of execution.
        await session.close();
      } finally {
        await session.handlers_done;

        sessions.remove(session);
      }
    }
  }
}
