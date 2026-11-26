import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart';

import '../messaging/application_message_codecs.dart';
import '../messaging/standard_messaging_modules.dart';
import '../workflow/workflow_runtime.dart';

import 'contracts/client_connection_setup.dart';

/// Constructs an independent communication subsystem.
///
/// [codecs] and [handlers] contain validated application messaging
/// configuration supplied by the SDK.
///
/// Returns an unused Communication instance whose execution and
/// disposal lifecycle transfers to the client connection owner.
///
/// The factory must not establish connections or execute handlers.
typedef ClientCommunicationFactory = Communication Function({
  required MessageCodecRegistry codecs,
  required RequestHandlerRegistry handlers,
});

/// Owns successive authenticated SDK communication lifecycles.
///
/// Each connection attempt resolves trusted endpoint configuration
/// and constructs an independent Communication instance.
///
/// Connection replacement requires confirmed disposal of previously
/// owned communication resources.
///
/// Application capabilities borrow typed request execution from
/// this component. They do not independently establish connections.
///
/// Example:
/// ```dart
/// final connection = ClientConnection(
///   setup: resolve_connection,
///   runtime: WorkflowRuntime.standard(),
/// );
///
/// try {
///   await connection.connect();
///   await connection.reconnect();
/// } finally {
///   await connection.close();
/// }
/// ```
final class ClientConnection {
  /// Creates an inactive connection lifecycle owner.
  ///
  /// [setup] resolves trusted configuration for each connection attempt.
  /// [runtime] supplies the immutable application serialization configuration.
  /// [communication_factory] optionally replaces default Communication
  /// construction while preserving SDK-owned messaging configuration.
  ///
  /// [register_handlers] contributes application-owned receiving handlers
  /// to each independent communication configuration.
  ///
  /// [on_session_available] receives the authenticated session after
  /// successful establishment.
  ///
  /// [on_session_unavailable] receives the retiring session and its
  /// failure or invalidation reason before replacement is permitted.
  ///
  /// Lifecycle callbacks are synchronous, must not throw and must not
  /// await or dispose of the owning communication lifecycle.
  ///
  /// Messaging configuration failures propagate.
  /// Construction performs no endpoint resolution or resource acquisition.
  ClientConnection({
    required ClientConnectionSetup setup,
    required WorkflowRuntime runtime,
    ClientCommunicationFactory? communication_factory,
    void Function(RequestHandlerRegistry)? register_handlers,
    void Function(MessageSession)? on_session_available,
    void Function(MessageSession, Object, StackTrace)? on_session_unavailable,
  }) : _setup = setup,
       _communication_factory = communication_factory,
       _register_handlers = register_handlers,
       _on_session_available = on_session_available,
       _on_session_unavailable = on_session_unavailable,
       _codecs = create_application_message_codecs(
         modules: standard_messaging_modules(workflow_runtime: runtime),
       );

  /// Trusted endpoint and peer identity resolution capability.
  final ClientConnectionSetup _setup;

  /// Optional substitution for default communication construction.
  final ClientCommunicationFactory? _communication_factory;

  /// Optional application receiving-handler contribution.
  ///
  /// Invoked before each communication handler registry is frozen.
  final void Function(RequestHandlerRegistry)? _register_handlers;

  /// Optional notification of successful authenticated establishment.
  final void Function(MessageSession)? _on_session_available;

  /// Optional notification of session invalidation.
  ///
  /// Receives the affected session, failure reason and diagnostic stack.
  final void Function(MessageSession, Object, StackTrace)?
  _on_session_unavailable;

  /// Validated application codecs shared by successive connections.
  final MessageCodecRegistry _codecs;

  /// Currently owned communication lifecycle.
  ///
  /// Remains retained until resource disposal has been confirmed.
  _OwnedConnection? _owned;

  /// Whether an explicit connection lifecycle operation is executing.
  bool _busy = false;

  /// Whether this connection owner has permanently closed.
  bool _closed = false;

  /// Whether an authenticated connection admits application requests.
  bool get is_connected => _owned?.available ?? false;

  /// Whether owned communication resources have been released.
  ///
  /// Returns false while owned communication is active, draining or
  /// its resource disposal remains unconfirmed.
  bool get resources_released =>
      _owned?.communication.resources_released ?? true;

  /// Establishes an authenticated connection.
  ///
  /// Returns after successful session establishment.
  ///
  /// Throws [StateError] when already connected, permanently closed
  /// or another lifecycle operation is executing.
  ///
  /// Configuration, connection and resource disposal failures propagate.
  Future<void> connect() {
    return _exclusive(() async {
      if (is_connected) {
        throw StateError('SDK is already connected.');
      }

      await _open_connection();
    });
  }

  /// Replaces the current communication lifecycle.
  ///
  /// Resolves trusted configuration again after the previous
  /// connection's resources have been released.
  ///
  /// Returns after establishing an independent authenticated session.
  /// No previously submitted application request is repeated.
  ///
  /// Throws [StateError] when permanently closed or another lifecycle
  /// operation is executing. Configuration, connection and resource
  /// disposal failures propagate.
  Future<void> reconnect() {
    return _exclusive(_open_connection);
  }

  /// Returns the currently admitted authenticated session.
  ///
  /// Throws [StateError] when no authenticated session is available.
  ///
  /// The returned session is borrowed. Connection lifecycle ownership
  /// remains with this component.
  MessageSession require_session() {
    final owned = _owned;

    if (owned == null || !owned.available) {
      throw StateError('SDK connection is unavailable.');
    }

    return owned.session!;
  }

  /// Executes an authenticated application [request].
  ///
  /// [session] optionally binds execution to a previously acquired
  /// session for operations spanning multiple correlated requests.
  ///
  /// Returns the typed application response.
  ///
  /// Throws [StateError] when the connection is unavailable or the
  /// supplied session is no longer the admitted session.
  ///
  /// Communication and remote execution failures propagate.
  Future<R> request<R extends Response>(
    Request<R> request, {
    MessageSession? session,
  }) async {
    final current = require_session();

    if (session != null && !identical(current, session)) {
      throw StateError('SDK connection has been replaced.');
    }

    return current.request(request);
  }

  /// Permanently closes this connection lifecycle owner.
  ///
  /// Returns after communication and admitted handlers have drained.
  /// Repeated successful closure has no additional effect.
  ///
  /// Throws [StateError] when another lifecycle operation is executing.
  ///
  /// Unconfirmed resource disposal retains the affected connection
  /// and propagates its failure.
  Future<void> close() async {
    if (_closed) return;

    await _exclusive(() async {
      await _release_connection();

      _closed = true;
    });
  }

  /// Executes one explicit connection lifecycle [operation].
  ///
  /// Returns after the operation has settled, including on failure.
  ///
  /// Throws [StateError] for concurrent or permanently closed
  /// lifecycle execution.
  Future<void> _exclusive(Future<void> Function() operation) async {
    if (_busy || _closed) {
      throw StateError('SDK connection lifecycle is unavailable.');
    }

    // Claim lifecycle ownership before yielding to another caller.
    _busy = true;

    try {
      await operation();
    } finally {
      _busy = false;
    }
  }

  /// Establishes a new connection after releasing previous resources.
  ///
  /// Resolves and validates trusted configuration before constructing
  /// Communication, then transfers the resulting lifecycle into
  /// [_owned] before beginning session establishment.
  ///
  /// Failed establishment drains any acquired resources before
  /// propagating the failure.
  Future<void> _open_connection() async {
    await _release_connection();

    final configuration = await _setup();

    _validate_configuration(configuration);

    final handlers = RequestHandlerRegistry();

    _register_handlers?.call(handlers);

    handlers.freeze(codecs: _codecs);

    final factory = _communication_factory;

    final communication = factory == null
        ? Communication(codecs: _codecs, handlers: handlers)
        : factory(codecs: _codecs, handlers: handlers);

    final owned = _OwnedConnection(communication: communication);

    _owned = owned;

    try {
      final session = await communication.connect(
        scope_directory: configuration.scope_directory,
        os_user_id: configuration.os_user_id,
      );

      // Retain the session before validating its authenticated
      // identity so unsuccessful validation can still dispose of it.
      owned.session = session;

      if (session.os_user_id != configuration.os_user_id) {
        throw StateError('Unexpected authenticated host identity.');
      }

      owned.available = true;

      // Session termination invalidates request admission independently
      // of the complete communication handler-draining lifecycle.
      session.done
          .then<void>(
            (_) => _invalidate(owned),
            onError: (Object error, StackTrace stack_trace) {
              _invalidate(owned, error: error, stack_trace: stack_trace);
            },
          )
          .ignore();

      _on_session_available?.call(session);
    } catch (_) {
      await _release_connection();

      rethrow;
    }
  }

  /// Validates trusted [configuration] before acquiring resources.
  ///
  /// Throws [ArgumentError] for a blank endpoint or expected peer
  /// identity. Values retain their original spelling.
  static void _validate_configuration(
    ClientConnectionConfiguration configuration,
  ) {
    if (configuration.scope_directory.trim().isEmpty) {
      throw ArgumentError.value(
        configuration.scope_directory,
        'scope_directory',
      );
    }

    if (configuration.os_user_id.trim().isEmpty) {
      throw ArgumentError.value(configuration.os_user_id, 'os_user_id');
    }
  }

  /// Invalidates request admission for the specified [owned] connection.
  ///
  /// [error] and [stack_trace] optionally preserve its terminal failure.
  /// Otherwise an explicit unavailable-connection error is supplied.
  ///
  /// Application capabilities are notified exactly once after request
  /// admission closes and before replacement begins.
  ///
  /// Notifications from previously replaced connections are ignored.
  void _invalidate(
    _OwnedConnection owned, {
    Object? error,
    StackTrace? stack_trace,
  }) {
    if (!identical(_owned, owned) || !owned.available) {
      return;
    }

    owned.available = false;

    _on_session_unavailable?.call(
      owned.session!,
      error ?? StateError('SDK connection became unavailable.'),
      stack_trace ?? StackTrace.current,
    );
  }

  /// Releases the currently owned communication lifecycle.
  ///
  /// Invalidates request admission before session closure and awaits
  /// Communication's complete admitted-handler disposal boundary.
  ///
  /// A terminal execution failure does not prevent replacement when
  /// resource disposal has been successfully confirmed.
  ///
  /// Unconfirmed disposal retains the owned connection and propagates
  /// the failure rather than allowing another connection to be created.
  Future<void> _release_connection() async {
    final owned = _owned;

    if (owned == null) return;

    _invalidate(owned);

    try {
      try {
        await owned.session?.close();
      } finally {
        try {
          await owned.communication.done;
        } catch (_) {
          // Communication may terminate with an execution error
          // after successfully releasing every owned resource.
          if (!owned.communication.resources_released) {
            rethrow;
          }
        }
      }

      if (!owned.communication.resources_released) {
        throw StateError('SDK communication disposal remains unconfirmed.');
      }
    } finally {
      if (owned.communication.resources_released) {
        _owned = null;
      }
    }
  }
}

/// Retains the resources associated with one communication lifecycle.
///
/// The connection owner controls request admission independently
/// of resource disposal completion.
///
/// Example:
/// ```dart
/// final owned = _OwnedConnection(
///   communication: communication,
/// );
///
/// assert(!owned.available);
/// ```
final class _OwnedConnection {
  /// Retains the supplied [communication] before session establishment.
  ///
  /// Construction does not execute the communication lifecycle.
  _OwnedConnection({required this.communication});

  /// Communication subsystem owned by this lifecycle.
  final Communication communication;

  /// Authenticated session, when establishment has succeeded.
  MessageSession? session;

  /// Whether the session currently admits application requests.
  bool available = false;
}
