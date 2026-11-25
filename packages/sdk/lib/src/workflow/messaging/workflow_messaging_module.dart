import 'package:rudra_communication/rudra_communication.dart';

import '../../messaging/application_messaging_module.dart';

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
/// resolution message contracts for use by host and client configurations.
///
/// Example:
/// ```dart
/// final codecs = create_application_message_codecs(
///   modules: [const WorkflowMessagingModule()],
/// );
/// ```
final class WorkflowMessagingModule implements ApplicationMessagingModule {
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
}
