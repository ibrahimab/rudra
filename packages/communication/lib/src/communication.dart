import 'dart:async';
import 'dart:io';

import 'messaging/message_codec_registry.dart';
import 'messaging/request_handler_registry.dart';
import 'sessions/connection_service.dart';
import 'sessions/default_message_session.dart';
import 'sessions/message_session.dart';
import 'sessions/message_session_options.dart';
import 'transport/connection_params.dart';
import 'transport/contracts/transport.dart';
import 'transport/contracts/transport_connection.dart';
import 'transport/contracts/transport_listener.dart';
import 'transport/transport_configuration.dart';
import 'transport/transport_registry.dart';

/// Coordinates authenticated object-level application communication.
///
/// Owns messaging configuration, session execution and
/// communication resource disposal.
///
/// Communication selects native local connectivity by default. Consumers
/// supply application codecs and handlers and can enable configured endpoints.
///
/// Each instance owns one execution lifecycle, either a listening
/// endpoint or an independently connected client session.
///
/// Example:
/// ```dart
/// final communication = Communication(
///   codecs: codecs,
///   handlers: handlers,
/// );
///
/// final session = await communication.connect();
///
/// try {
///   final response = await session.request(
///     const EchoRequest('Hello'),
///   );
/// } finally {
///   try {
///     await session.close();
///   } finally {
///     await communication.done;
///   }
/// }
/// ```
abstract interface class Communication {
  /// Creates communication with internally owned execution components.
  ///
  /// [transport_configuration] enables listeners in activation order. The
  /// default enables only native local connectivity.
  /// [transport_registry] optionally substitutes the implementation catalog
  /// used to resolve listeners and the default client transport.
  ///
  /// [codecs] supplies application message codec configuration.
  /// When absent, communication constructs an empty registry.
  ///
  /// [handlers] supplies application request handler configuration.
  /// When absent, communication constructs an empty registry.
  ///
  /// Supplied registries are frozen before execution begins.
  ///
  /// [options] optionally configures session limits and deadlines.
  ///
  /// Construction does not bind endpoints, establish connections
  /// or execute application handlers.
  factory Communication({
    TransportConfiguration transport_configuration,
    TransportRegistry? transport_registry,
    MessageCodecRegistry? codecs,
    RequestHandlerRegistry? handlers,
    MessageSessionOptions options,
  }) = _Communication;

  /// Whether all owned communication resources have been released.
  ///
  /// Returns true before execution and after successful disposal.
  ///
  /// Returns false during native resource acquisition, active
  /// communication, outstanding handler draining or following
  /// unsuccessful resource disposal.
  ///
  /// Execution failures do not independently prevent successful
  /// resource release.
  bool get resources_released;

  /// Completion of the entire owning communication lifecycle.
  ///
  /// Completes after communication disposal and termination of
  /// previously admitted application handlers.
  ///
  /// Initialization, terminal execution and resource disposal
  /// failures propagate through this future.
  ///
  /// Remains pending until this communication instance executes.
  ///
  /// Application handlers must not await completion of their
  /// own owning communication lifecycle.
  Future<void> get done;

  /// Executes the configured authenticated listening endpoint.
  ///
  /// [shutdown] supplies the external termination notification.
  ///
  /// [on_startup] optionally initializes application resources
  /// after endpoint binding and before connection acceptance.
  ///
  /// Returns after listener disposal, session disposal and
  /// completion of previously admitted application handlers.
  ///
  /// Throws [StateError] for repeated execution or incompatible
  /// messaging configuration, and [ArgumentError] for invalid
  /// execution limits.
  ///
  /// Initialization, listener and resource disposal failures
  /// propagate to the caller.
  Future<void> run({
    required Future<void> shutdown,
    Future<void> Function()? on_startup,
  });

  /// Establishes an authenticated object-level client session.
  ///
  /// Returns an executing session providing typed messaging
  /// through the transport selected by [params]. Omit the parameters to
  /// connect through the registered native default.
  ///
  /// The caller may terminate communication through its close
  /// operation.
  ///
  /// This communication instance retains lifecycle coordination
  /// and reports complete handler draining through [done].
  ///
  /// Throws [StateError] for repeated execution or incompatible
  /// configuration, and [ArgumentError] for invalid limits.
  ///
  /// Connection, authentication and session initialization
  /// failures propagate to the caller.
  ///
  /// Connection establishment preserves listener ownership.
  Future<MessageSession> connect([
    ConnectionParams params = const ConnectionParams(),
  ]);
}

/// Implements communication's default ownership and execution model.
///
/// Constructs intrinsic dependencies internally and coordinates
/// their lifecycles without exposing concrete protocol components.
///
/// Example:
/// ```dart
/// final communication = _Communication(
/// );
///
/// assert(communication.resources_released);
/// ```
final class _Communication implements Communication {
  /// Creates the default communication implementation.
  ///
  /// [transport_configuration] selects enabled listening endpoints.
  /// [transport_registry] supplies available transport implementations.
  ///
  /// [codecs] supplies the application message codec registry.
  /// [handlers] supplies the application request handler registry.
  ///
  /// [options] defines session execution limits.
  ///
  /// Absent messaging registries are constructed internally.
  /// Construction performs no external resource acquisition.
  _Communication({
    TransportConfiguration transport_configuration =
        const TransportConfiguration.native(),
    TransportRegistry? transport_registry,
    MessageCodecRegistry? codecs,
    RequestHandlerRegistry? handlers,
    MessageSessionOptions options = const MessageSessionOptions(),
  }) : _transport_configuration = transport_configuration,
       _transport_registry = transport_registry ?? TransportRegistry.standard,
       _codecs = codecs ?? MessageCodecRegistry(),
       _handlers = handlers ?? RequestHandlerRegistry(),
       _options = options {
    // Lifecycle failure may occur before the owner awaits done.
    // Observe the future without changing its retained result.
    _completion.future.ignore();
  }

  /// Host-owned configuration for the listening lifecycle.
  final TransportConfiguration _transport_configuration;

  /// Available implementations for listening and native client connectivity.
  final TransportRegistry _transport_registry;

  /// Constructs the current platform's inactive native local transport.
  Transport _native_transport() =>
      _transport_registry.create_default(Platform.operatingSystem);

  /// Application codec configuration owned by communication.
  final MessageCodecRegistry _codecs;

  /// Application handler configuration owned by communication.
  final RequestHandlerRegistry _handlers;

  /// Immutable execution limits shared by independently owned sessions.
  final MessageSessionOptions _options;

  /// Internally owned concurrent server session coordinator.
  final ConnectionService _connection_service = ConnectionService();

  /// Completion source for the entire owning lifecycle.
  final Completer<void> _completion = Completer<void>();

  /// Whether this instance has claimed its execution lifecycle.
  bool _has_run = false;

  /// Whether resource disposal has been successfully confirmed.
  bool _resources_released = true;

  /// Whether all communication resources have been released.
  @override
  bool get resources_released => _resources_released;

  /// Final owning communication lifecycle result.
  @override
  Future<void> get done => _completion.future;

  /// Claims the single execution lifecycle.
  ///
  /// Throws [StateError] after any previous execution attempt.
  void _claim_lifecycle() {
    if (_has_run) {
      throw StateError('Communication has already been executed.');
    }

    _has_run = true;
  }

  /// Validates execution configuration and freezes registration.
  ///
  /// Performs validation before acquiring native resources.
  /// Configuration failures propagate without endpoint creation.
  void _prepare() {
    _options.validate();

    _codecs.freeze();
    _handlers.freeze(codecs: _codecs);
  }

  /// Opens an executing session over the authenticated [connection].
  ///
  /// Returns a session using the retained messaging configuration.
  /// Successful opening transfers connection ownership to it.
  ///
  /// If opening fails, connection ownership remains with the caller.
  DefaultMessageSession _open_session(TransportConnection connection) {
    return DefaultMessageSession.open(
      connection: connection,
      codecs: _codecs,
      handlers: _handlers,
      options: _options,
    );
  }

  /// Executes the configured listening communication lifecycle.
  ///
  /// [shutdown] supplies the external termination notification.
  ///
  /// [on_startup] optionally initializes application resources
  /// before accepting connections.
  ///
  /// Returns after confirmed listener and session disposal.
  ///
  /// Initialization, execution and disposal failures propagate.
  @override
  Future<void> run({
    required Future<void> shutdown,
    Future<void> Function()? on_startup,
  }) async {
    _claim_lifecycle();

    // Observe early shutdown failures during configuration and
    // endpoint initialization.
    shutdown.ignore();

    try {
      _prepare();

      _resources_released = false;

      final listeners = await _activate_listeners();

      try {
        await _connection_service.run(
          listeners: listeners,
          shutdown: shutdown,
          open_session: _open_session,
          on_startup: on_startup,
        );
      } finally {
        _resources_released = _connection_service.resources_released;
      }

      _completion.complete();
    } catch (error, stack) {
      _completion.completeError(error, stack);

      rethrow;
    }
  }

  /// Activates all enabled endpoints before session admission.
  ///
  /// Rolls back bound listeners if a later activation fails. A failed cleanup
  /// is visible to the outer owner through [resources_released].
  Future<List<TransportListener>> _activate_listeners() async {
    final listeners = <TransportListener>[];
    try {
      // Resolve every configured endpoint before attempting any bind.
      final endpoints = _transport_configuration.endpoints;
      final enabled = endpoints == null
          ? [_native_transport()]
          : endpoints.map(_transport_registry.create).toList();
      if ((Set<Transport>.identity()..addAll(enabled)).length !=
          enabled.length) {
        throw ArgumentError(
          'Transport factories must return distinct listeners.',
        );
      }
      for (final transport in enabled) {
        listeners.add(await transport.listen());
      }
      return listeners;
    } catch (error) {
      try {
        await Future.wait(
          listeners.reversed.map((listener) async => listener.close()),
        );
      } catch (disposal_error) {
        throw TransportDisposalException(error, disposal_error);
      }
      _resources_released = error is! TransportDisposalException;
      rethrow;
    }
  }

  /// Establishes an authenticated client communication session.
  ///
  /// Returns an executing object-level session using the
  /// configured transport.
  ///
  /// Connection, authentication and session initialization
  /// failures propagate.
  @override
  Future<MessageSession> connect([
    ConnectionParams params = const ConnectionParams(),
  ]) async {
    _claim_lifecycle();

    try {
      _prepare();

      _resources_released = false;

      final TransportConnection connection;

      try {
        connection = await (params.transport ?? _native_transport()).connect();
      } catch (error) {
        // Failed outbound establishment retains no connection
        // resources according to the transport contract.
        _resources_released = error is! TransportDisposalException;

        rethrow;
      }

      final DefaultMessageSession session;

      try {
        session = _open_session(connection);
      } catch (_) {
        // Failed session opening did not transfer ownership.
        // Confirm disposal before permitting resource release.
        await connection.close();

        _resources_released = true;

        rethrow;
      }

      unawaited(_observe_client(session));

      return session;
    } catch (error, stack) {
      _completion.completeError(error, stack);

      rethrow;
    }
  }

  /// Observes the complete owning lifecycle of [session].
  ///
  /// Session execution and disposal failures remain observable
  /// independently of application-handler draining.
  ///
  /// Completes the communication lifecycle after all previously
  /// admitted handlers have finished.
  Future<void> _observe_client(DefaultMessageSession session) async {
    try {
      try {
        await session.done;
      } finally {
        try {
          await session.close();
        } finally {
          await session.handlers_done;
        }

        _resources_released = true;
      }

      _completion.complete();
    } catch (error, stack) {
      _completion.completeError(error, stack);
    }
  }
}
