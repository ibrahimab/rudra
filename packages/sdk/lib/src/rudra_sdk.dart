import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import 'client/client_connection.dart';
import 'client/contracts/client_connection_setup.dart';

import 'filesystem/filesystem_service.dart';

import 'workflow/workflow_runtime.dart';

/// Public application facade for Rudra's shared SDK.
///
/// Exposes application capabilities consumed by CLI, Flutter and
/// other frontends through one configured SDK instance.
///
/// Filesystem inspection uses the supplied target adapter.
/// Host-backed application capabilities share an authenticated
/// connection owned by this SDK.
///
/// Trusted application composition supplies target configuration
/// and optional host connection resolution.
///
/// Construction performs no filesystem inspection, connection
/// establishment, persistence access or host service activation.
///
/// Example:
/// ```dart
/// final sdk = RudraSdk(
///   target_id: 'local-macos',
///   inspector: target_inspector,
///   connection_setup: resolve_host_connection,
/// );
///
/// try {
///   await sdk.connect();
///
///   final listing = await sdk.filesystem.list(
///     directory: TargetPath('/workspace'),
///   );
///
///   print(listing.is_complete);
/// } finally {
///   await sdk.close();
/// }
/// ```
final class RudraSdk {
  /// Creates an SDK configured for one filesystem target.
  ///
  /// [target_id] identifies the configured target environment.
  /// [inspector] supplies its read-only filesystem observation capability.
  ///
  /// [connection_setup] optionally configures trusted host endpoint
  /// resolution. Omitting it configures independent local filesystem
  /// inspection without host-backed application capabilities.
  ///
  /// [workflow_runtime] optionally supplies application messaging
  /// serialization configuration for host-backed capabilities.
  /// The standard workflow runtime is used when omitted.
  ///
  /// [communication_factory] optionally substitutes default
  /// communication construction for configured host connectivity.
  ///
  /// Throws [ArgumentError] for a blank target identifier or
  /// connection-specific options without a connection setup capability.
  ///
  /// Application messaging configuration failures propagate.
  /// Construction does not acquire external resources.
  RudraSdk({
    required String target_id,
    required TargetInspector inspector,
    ClientConnectionSetup? connection_setup,
    WorkflowRuntime? workflow_runtime,
    ClientCommunicationFactory? communication_factory,
  }) : filesystem = FilesystemService(
         target_id: target_id,
         inspector: inspector,
       ),
       _connection = connection_setup == null
           ? null
           : ClientConnection(
               setup: connection_setup,
               runtime: workflow_runtime ?? WorkflowRuntime.standard(),
               communication_factory: communication_factory,
             ) {
    if (connection_setup == null &&
        (workflow_runtime != null || communication_factory != null)) {
      throw ArgumentError(
        'Host communication options require a connection setup capability.',
      );
    }
  }

  /// Provides platform-independent filesystem operations.
  ///
  /// The service performs read-only inspection through the configured
  /// target adapter and exposes standardized filesystem results.
  ///
  /// Accessing this property performs no filesystem operations.
  final FilesystemService filesystem;

  /// Shared connection lifecycle for host-backed application capabilities.
  ///
  /// Absent when the SDK is configured exclusively for independent
  /// local filesystem inspection.
  final ClientConnection? _connection;

  /// Identifies the filesystem target associated with this SDK.
  ///
  /// Delegates to the configured filesystem service.
  /// The identifier is scoped to the application's configured targets.
  String get target_id => filesystem.target_id;

  /// Whether this SDK has an available authenticated host connection.
  bool get is_connected => _connection?.is_connected ?? false;

  /// Whether owned host communication resources have been released.
  ///
  /// Returns true for an SDK without configured host connectivity.
  bool get resources_released => _connection?.resources_released ?? true;

  /// Establishes the configured authenticated host connection.
  ///
  /// Returns after successful connection establishment.
  ///
  /// Throws [StateError] when host connectivity is not configured,
  /// already connected, permanently closed or a connection lifecycle
  /// operation is executing.
  ///
  /// Configuration, authentication and connection failures propagate.
  /// Connecting does not start or install a host service.
  Future<void> connect() async {
    await _require_connection().connect();
  }

  /// Replaces the current host communication lifecycle.
  ///
  /// Returns after previous resources have been released and an
  /// independent authenticated connection has been established.
  ///
  /// Throws [StateError] when host connectivity is not configured,
  /// permanently closed or a lifecycle operation is executing.
  ///
  /// Connection and resource disposal failures propagate.
  /// Previously submitted application requests are not repeated.
  Future<void> reconnect() async {
    await _require_connection().reconnect();
  }

  /// Permanently closes owned host communication resources.
  ///
  /// Returns after communication and admitted application handlers
  /// have drained.
  ///
  /// Repeated successful closure has no additional effect.
  /// An SDK configured exclusively for local inspection has no
  /// communication resources to release.
  ///
  /// Connection resource disposal failures propagate.
  /// Closing a frontend connection does not terminate RudraHost.
  Future<void> close() async {
    await _connection?.close();
  }

  /// Returns the configured host connection capability.
  ///
  /// Throws [StateError] when host connectivity is not configured.
  ClientConnection _require_connection() {
    final connection = _connection;

    if (connection == null) {
      throw StateError('SDK host connectivity is not configured.');
    }

    return connection;
  }
}
