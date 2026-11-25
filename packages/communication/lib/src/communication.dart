import 'sessions/connection_service.dart';
import 'transport/contracts/transport.dart';
import 'transport/contracts/transport_connection.dart';
import 'transport/contracts/transport_listener.dart';
import 'transport/local_transport.dart';

/// Coordinates authenticated communication for an application.
///
/// Owns transport initialization, concurrent connection execution
/// and resource disposal behind a portable application-facing API.
///
/// Application-specific behavior is supplied by the consumer.
/// Communication has no dependency on application domain models,
/// persistence implementations or host orchestration.
///
/// Each instance represents one communication execution lifecycle.
///
/// Example:
/// ```dart
/// final communication = Communication();
///
/// await communication.run(
///   scope_directory: scope,
///   os_user_id: trusted_owner,
///   shutdown: shutdown.future,
///   handle_connection: handle_connection,
/// );
///
/// assert(communication.resources_released);
/// ```
abstract interface class Communication {
  /// Creates a communication instance with internally owned components.
  ///
  /// [transport] optionally substitutes the default local transport.
  /// The supplied implementation must satisfy the transport ownership
  /// and resource disposal contracts.
  ///
  /// Construction does not bind endpoints or acquire native resources.
  factory Communication({Transport? transport}) =>
      _Communication(transport: transport);

  /// Whether all resources owned by communication have been released.
  ///
  /// Returns true before execution and after confirmed disposal.
  /// Returns false during initialization, active execution or after
  /// unsuccessful resource disposal.
  ///
  /// Consumers may inspect this property after failed execution to
  /// determine whether external ownership resources can be released.
  bool get resources_released;

  /// Executes one authenticated communication lifecycle.
  ///
  /// [scope_directory] identifies the exclusively owned communication
  /// directory prepared by trusted application composition.
  /// [os_user_id] identifies the trusted operating-system owner.
  /// [shutdown] supplies the external termination notification.
  /// [handle_connection] executes an individual authenticated session.
  /// [on_startup] optionally initializes application resources after
  /// endpoint binding and before connection acceptance.
  ///
  /// Returns after communication resources have been disposed of
  /// and outstanding session handlers have terminated.
  ///
  /// Throws [StateError] for repeated execution or [UnsupportedError]
  /// when the default transport cannot support the current platform.
  ///
  /// Initialization, listener and resource disposal failures propagate.
  Future<void> run({
    required String scope_directory,
    required String os_user_id,
    required Future<void> shutdown,
    required Future<void> Function(TransportConnection) handle_connection,
    Future<void> Function()? on_startup,
  });
}

/// Implements the default communication subsystem.
///
/// Retains one transport and one connection lifecycle coordinator,
/// delegating native initialization and session execution to their
/// respective components.
///
/// Example:
/// ```dart
/// final communication = _Communication();
/// assert(communication.resources_released);
/// ```
final class _Communication implements Communication {
  /// Creates the default communication implementation.
  ///
  /// [transport] optionally replaces native transport selection.
  /// The connection service is constructed and owned internally.
  ///
  /// Construction performs no external resource acquisition.
  _Communication({Transport? transport})
    : _transport = transport ?? const LocalTransport();

  /// Transport responsible for authenticated endpoint establishment.
  final Transport _transport;

  /// Internally owned concurrent connection lifecycle coordinator.
  final ConnectionService _connection_service = ConnectionService();

  /// Records whether this instance has entered its lifecycle.
  bool _has_run = false;

  /// Records whether communication resource disposal is confirmed.
  bool _resources_released = true;

  /// Whether initialization and execution resources have been released.
  @override
  bool get resources_released => _resources_released;

  /// Executes the configured communication lifecycle.
  ///
  /// [scope_directory] identifies the caller's exclusively owned scope.
  /// [os_user_id] supplies the trusted authorization identity.
  /// [shutdown] supplies the external termination notification.
  /// [handle_connection] processes an authenticated session.
  /// [on_startup] initializes the consumer before accepting connections.
  ///
  /// Returns after confirmed connection service disposal.
  /// Initialization, execution and disposal failures propagate.
  ///
  /// Throws [StateError] if this instance has already been executed.
  @override
  Future<void> run({
    required String scope_directory,
    required String os_user_id,
    required Future<void> shutdown,
    required Future<void> Function(TransportConnection) handle_connection,
    Future<void> Function()? on_startup,
  }) async {
    if (_has_run) {
      throw StateError('Communication has already been run.');
    }

    // Claim the lifecycle before asynchronous endpoint initialization.
    _has_run = true;
    _resources_released = false;

    // Observe early shutdown failures while the transport initializes.
    // The connection service still receives the original notification.
    shutdown.ignore();

    final TransportListener listener;

    try {
      listener = await _transport.listen(
        scope_directory: scope_directory,
        os_user_id: os_user_id,
      );
    } catch (_) {
      // Failed initialization retains no acquired listener according
      // to the transport contract.
      _resources_released = true;
      rethrow;
    }

    try {
      // Ownership of the acquired listener transfers to the
      // connection service for the remainder of this lifecycle.
      await _connection_service.run(
        listener: listener,
        shutdown: shutdown,
        handle_connection: handle_connection,
        on_startup: on_startup,
      );
    } finally {
      // Preserve the disposal result independently of execution
      // success so the application can safely release its own resources.
      _resources_released = _connection_service.resources_released;
    }
  }
}
