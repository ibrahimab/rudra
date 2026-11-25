import 'package:rudra_communication/rudra_communication.dart';

import '../../messaging/application_request_context.dart';
import '../../messaging/application_request_handler_module.dart';

import 'start/workflow_start_request.dart';
import 'start/workflow_start_response.dart';
import 'start/codecs/workflow_start_request_codec.dart';
import 'start/codecs/workflow_start_response_codec.dart';

import 'stop/workflow_stop_request.dart';
import 'stop/workflow_stop_response.dart';
import 'stop/codecs/workflow_stop_request_codec.dart';
import 'stop/codecs/workflow_stop_response_codec.dart';

import 'submission/workflow_submission_request.dart';
import 'submission/workflow_submission_response.dart';
import 'submission/codecs/workflow_submission_request_codec.dart';
import 'submission/codecs/workflow_submission_response_codec.dart';

/// Contributes the messaging capabilities owned by the workflow feature.
///
/// Registers workflow establishment, termination and durable submission
/// resolution codecs together with their local application handlers.
///
/// Clients consume the codecs independently of handler registration.
/// Hosts bind the handlers to their authoritative application.
///
/// Example:
/// ```dart
/// final codecs = create_application_message_codecs(
///   modules: [const WorkflowMessagingModule()],
/// );
/// ```
final class WorkflowMessagingModule implements ApplicationRequestHandlerModule {
  /// Creates the stateless workflow messaging module.
  const WorkflowMessagingModule();

  /// Stable identifier of the workflow messaging contribution.
  @override
  String get module_id => 'rudra.workflow.messaging';

  /// Contributes workflow message codecs to [registry].
  ///
  /// Registers each request together with its concrete response contract.
  /// The application composition boundary validates and freezes the
  /// completed configuration.
  ///
  /// Registration failures propagate from the supplied registry.
  @override
  void register_codecs(MessageCodecRegistry registry) {
    registry
      ..register_request<WorkflowStartResponse, WorkflowStartRequest>(
        const WorkflowStartRequestCodec(),
      )
      ..register_response<WorkflowStartResponse>(
        const WorkflowStartResponseCodec(),
      )
      ..register_request<WorkflowStopResponse, WorkflowStopRequest>(
        const WorkflowStopRequestCodec(),
      )
      ..register_response<WorkflowStopResponse>(
        const WorkflowStopResponseCodec(),
      )
      ..register_request<WorkflowSubmissionResponse, WorkflowSubmissionRequest>(
        const WorkflowSubmissionRequestCodec(),
      )
      ..register_response<WorkflowSubmissionResponse>(
        const WorkflowSubmissionResponseCodec(),
      );
  }

  /// Contributes authoritative workflow request handlers to [registry].
  ///
  /// [context] supplies the retained application and trusted target
  /// validation capability.
  ///
  /// Every request verifies its authenticated peer before accessing
  /// application operations. Expected application outcomes are returned
  /// as typed responses; infrastructure failures propagate.
  ///
  /// Registration does not execute workflow operations.
  @override
  void register_handlers(
    RequestHandlerRegistry registry,
    ApplicationRequestContext context,
  ) {
    registry
      ..register<WorkflowStartResponse, WorkflowStartRequest>((
        request,
        session,
      ) async {
        context.require_authorized_peer(session);

        context.validate_start(request.target_id, request.root);

        final outcome = await context.application.start(
          target_id: request.target_id,
          root: request.root,
          idempotency_key: request.idempotency_key,
        );

        return WorkflowStartResponse(outcome: outcome);
      })
      ..register<WorkflowStopResponse, WorkflowStopRequest>((
        request,
        session,
      ) async {
        context.require_authorized_peer(session);

        final outcome = await context.application.stop(
          workflow_id: request.workflow_id,
          idempotency_key: request.idempotency_key,
        );

        return WorkflowStopResponse(outcome: outcome);
      })
      ..register<WorkflowSubmissionResponse, WorkflowSubmissionRequest>((
        request,
        session,
      ) async {
        context.require_authorized_peer(session);

        final resolution = await context.application.status_for(
          request.receipt,
        );

        return WorkflowSubmissionResponse(resolution: resolution);
      });
  }
}
