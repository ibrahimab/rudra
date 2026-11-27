import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../../client/client_connection.dart';

import '../application/outcomes/workflow_operation_outcome.dart';
import '../event_submission_receipt.dart';
import '../processing/workflow_submission_resolution.dart';

import '../messaging/start/workflow_start_request.dart';
import '../messaging/stop/workflow_stop_request.dart';
import '../messaging/submission/workflow_submission_request.dart';

/// Provides host-backed workflow operations for a configured SDK.
///
/// Translates application operations into typed requests over the
/// shared authenticated connection.
///
/// Authoritative workflow processing, persistence and business
/// validation remain the responsibility of the connected host.
///
/// Example:
/// ```dart
/// final outcome = await sdk.workflows.start(
///   root: TargetPath('/workspace'),
///   idempotency_key: operation_id,
/// );
///
/// if (outcome is WorkflowOperationResolved) {
///   print(outcome.resolution.state);
/// }
/// ```
final class WorkflowService {
  /// Creates a service using the authenticated [connection].
  ///
  /// The owning SDK establishes and disposes the connection.
  /// Construction performs no application operations.
  WorkflowService({required ClientConnection connection})
    : _connection = connection;

  /// Borrowed authenticated application request capability.
  ///
  /// Connection establishment, replacement and disposal remain
  /// responsibilities of the owning SDK.
  final ClientConnection _connection;

  /// Requests workflow establishment at the specified [root].
  ///
  /// [root] preserves the requested target-native filesystem path.
  ///
  /// [idempotency_key] identifies the logical Start operation
  /// within the host's trusted durable submission scope.
  ///
  /// Returns the authoritative outcome of the requested operation,
  /// including durable rejection, quarantine or idempotency conflict.
  ///
  /// Throws [ArgumentError] for a blank operation key or
  /// [StateError] when the SDK connection is unavailable.
  /// Communication and remote execution failures propagate.
  ///
  /// A failed response does not establish whether the operation
  /// committed. Explicit retries within the same durable scope
  /// must preserve the original key and root. The host supplies its target.
  ///
  /// Example:
  /// ```dart
  /// final outcome = await sdk.workflows.start(
  ///   root: TargetPath('/workspace'),
  ///   idempotency_key: operation_id,
  /// );
  /// ```
  Future<WorkflowOperationOutcome> start({
    required TargetPath root,
    required String idempotency_key,
  }) async {
    final response = await _connection.request(
      WorkflowStartRequest(root: root, idempotency_key: idempotency_key),
    );

    return response.outcome;
  }

  /// Requests termination of the specified [workflow_id].
  ///
  /// [idempotency_key] identifies the logical Stop operation
  /// within the host's trusted durable submission scope.
  ///
  /// The supplied workflow identity remains fixed throughout
  /// execution, even if another workflow becomes active.
  ///
  /// Returns the authoritative outcome of the requested operation,
  /// independently of the current workflow lifecycle.
  ///
  /// Throws [ArgumentError] for blank identifiers or [StateError]
  /// when the SDK connection is unavailable.
  /// Communication and remote execution failures propagate.
  ///
  /// Explicit retries within the same durable scope must preserve
  /// both the original operation key and workflow identity.
  ///
  /// Example:
  /// ```dart
  /// final outcome = await sdk.workflows.stop(
  ///   workflow_id: displayed_workflow.identity.workflow_id,
  ///   idempotency_key: operation_id,
  /// );
  /// ```
  Future<WorkflowOperationOutcome> stop({
    required String workflow_id,
    required String idempotency_key,
  }) async {
    final response = await _connection.request(
      WorkflowStopRequest(
        workflow_id: workflow_id,
        idempotency_key: idempotency_key,
      ),
    );

    return response.outcome;
  }

  /// Retrieves the durable resolution associated with [receipt].
  ///
  /// Returns the authoritative submission resolution, or null when
  /// no matching submission is accessible within the trusted scope.
  ///
  /// Throws [StateError] when the SDK connection is unavailable.
  /// Communication, restoration and remote execution failures propagate.
  ///
  /// Querying does not submit or repeat an application operation.
  ///
  /// Example:
  /// ```dart
  /// final resolution = await sdk.workflows.status_for(receipt);
  ///
  /// print(resolution?.state);
  /// ```
  Future<WorkflowSubmissionResolution?> status_for(
    EventSubmissionReceipt receipt,
  ) async {
    final response = await _connection.request(
      WorkflowSubmissionRequest(receipt: receipt),
    );

    return response.resolution;
  }
}
