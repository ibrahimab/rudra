import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart'
    show ConnectionParams;

import 'client/client_connection.dart';

import 'filesystem/filesystem_service.dart';

import 'state/messaging/read/state_read_request.dart';
import 'state/observation/remote_state_observer.dart';
import 'state/observation/state_synchronization_status.dart';
import 'state/rudra_state.dart';

import 'workflow/services/workflow_service.dart';
import 'workflow/workflow_runtime.dart';

/// Public application facade for Rudra's shared SDK.
///
/// All application operations execute through one authenticated
/// host connection owned by this SDK.
///
/// The selected target identifies a filesystem environment on the host.
///
/// Construction retains configuration without acquiring external
/// resources or executing application operations.
///
/// Example:
/// ```dart
/// final sdk = RudraSdk();
///
/// try {
///   await sdk.connect();
///
///   final listing = await sdk.filesystem.list(
///     directory: TargetPath('/workspace'),
///   );
///
///   final state = await sdk.read_state();
///
///   print(listing.is_complete);
///   print(state.workflows.current_workflow);
/// } finally {
///   await sdk.close();
/// }
/// ```
final class RudraSdk {
  /// Creates an SDK configured for one filesystem target.
  ///
  /// [target_id] identifies the selected filesystem environment. The host
  /// validates it on application operations.
  ///
  /// [workflow_runtime] optionally supplies application messaging
  /// serialization configuration. The standard runtime is selected
  /// when omitted.
  ///
  /// [communication_factory] optionally substitutes default
  /// communication construction.
  ///
  /// Throws [ArgumentError] for a blank target identifier.
  /// Application messaging configuration failures propagate.
  ///
  /// Construction does not acquire external resources.
  RudraSdk({
    this.target_id = local_macos_target_id,
    WorkflowRuntime? workflow_runtime,
    ClientCommunicationFactory? communication_factory,
  }) {
    if (target_id.trim().isEmpty) {
      throw ArgumentError.value(
        target_id,
        'target_id',
        'The target identifier must not be blank.',
      );
    }

    _connection = ClientConnection(
      runtime: workflow_runtime ?? WorkflowRuntime.standard(),
      communication_factory: communication_factory,
      register_handlers: _state_observer.register_handlers,
      on_session_available: _state_observer.attach_session,
      on_session_unavailable: _state_observer.detach_session,
    );

    filesystem = FilesystemService(
      target_id: target_id,
      connection: _connection,
    );

    workflows = WorkflowService(target_id: target_id, connection: _connection);
  }

  /// Identifier of the selected filesystem environment.
  ///
  /// The identifier is scoped to the host's configured targets.
  final String target_id;

  /// Provides host-backed read-only filesystem operations.
  ///
  /// Its identity remains stable across communication replacement.
  late final FilesystemService filesystem;

  /// Provides host-backed workflow application operations.
  ///
  /// Its identity remains stable across communication replacement.
  late final WorkflowService workflows;

  /// Shared authenticated application connection owned by this SDK.
  late final ClientConnection _connection;

  /// Remote state observation owned by this SDK.
  ///
  /// Borrows authenticated sessions from the shared connection owner
  /// and distributes verified state to independent local listeners.
  final RemoteStateObserver _state_observer = RemoteStateObserver();

  /// Whether an authenticated host connection is available.
  bool get is_connected => _connection.is_connected;

  /// Whether owned communication resources have been released.
  bool get resources_released => _connection.resources_released;

  /// Establishes an authenticated host connection using [params].
  /// Omitting parameters selects the native local transport.
  ///
  /// Returns after successful connection establishment.
  ///
  /// Throws [StateError] when already connected, permanently closed
  /// or a connection lifecycle operation is executing.
  ///
  /// Configuration, authentication and connection failures propagate.
  /// Connecting does not start or install a host service.
  ///
  /// Example:
  /// ```dart
  /// await sdk.connect(const ConnectionParams(
  ///   transport: MacOsUnixTransport(socket_path: '/private/tmp/example/rudra.sock'),
  /// ));
  /// ```
  Future<void> connect([
    ConnectionParams params = const ConnectionParams(),
  ]) async {
    await _connection.connect(params);
  }

  /// Replaces the current host communication lifecycle.
  ///
  /// Omitted [params] reuse the previous attempt's selection. An explicit
  /// empty [ConnectionParams] restores native local connectivity.
  ///
  /// Returns after previous resources have been released and an
  /// independent authenticated connection has been established.
  ///
  /// Throws [StateError] when permanently closed or a connection
  /// lifecycle operation is executing.
  ///
  /// Connection and resource disposal failures propagate.
  /// Previously submitted application requests are not repeated.
  Future<void> reconnect([ConnectionParams? params]) async {
    await _connection.reconnect(params);
  }

  /// Reads the latest verified composite application state.
  ///
  /// Returns an authoritative [RudraState]. A null current workflow
  /// represents verified absence of an unfinished workflow.
  ///
  /// Each invocation performs an independent authoritative query.
  ///
  /// Throws [StateError] when authenticated connectivity is unavailable.
  /// Communication, restoration and remote execution failures propagate.
  ///
  /// Reading does not initialize absent workflow persistence.
  ///
  /// Example:
  /// ```dart
  /// final state = await sdk.read_state();
  /// print(state.workflows.current_workflow);
  /// ```
  Future<RudraState> read_state() async {
    final response = await _connection.request(const StateReadRequest());

    return response.state;
  }

  /// Current availability of authoritative application-state observation.
  ///
  /// Independent of domain workflow state and connection availability.
  StateSynchronizationStatus get synchronization_status =>
      _state_observer.status;

  /// Observes initial and subsequent verified application state.
  ///
  /// Returns an independent local observation stream sharing the SDK's
  /// remote subscription. Rapid publications may be coalesced.
  ///
  /// Communication and synchronization failures terminate affected
  /// observations with an error.
  ///
  /// Following reconnection, consumers establish fresh observations.
  /// Cancelling the last listener retires the remote subscription.
  ///
  /// Example:
  /// ```dart
  /// final subscription = sdk.observe_state().listen((state) {
  ///   print(state.workflows.current_workflow);
  /// });
  ///
  /// await subscription.cancel();
  /// ```
  Stream<RudraState> observe_state() {
    return _state_observer.observe();
  }

  /// Observes current and subsequent synchronization availability.
  ///
  /// Returns an independent local status stream. Intermediate status
  /// changes may be coalesced for slow or paused listeners.
  ///
  /// Status observation remains available across connection
  /// replacement and terminates upon permanent SDK closure.
  ///
  /// Example:
  /// ```dart
  /// final subscription = sdk
  ///     .observe_synchronization_status()
  ///     .listen((status) {
  ///       print(status.name);
  ///     });
  ///
  /// await subscription.cancel();
  /// ```
  Stream<StateSynchronizationStatus> observe_synchronization_status() {
    return _state_observer.observe_status();
  }

  /// Permanently closes owned host communication resources.
  ///
  /// Returns after communication and admitted application handlers
  /// have drained and local observation has terminated.
  ///
  /// Paused frontend listeners do not delay resource disposal.
  /// Repeated successful closure has no additional effect.
  ///
  /// Resource disposal failures propagate.
  /// Closing a frontend connection does not terminate RudraHost.
  Future<void> close() async {
    await _connection.close();

    _state_observer.close();
  }
}

/// Host-validated identity of Rudra's local macOS filesystem target.
const local_macos_target_id = 'local-macos';
