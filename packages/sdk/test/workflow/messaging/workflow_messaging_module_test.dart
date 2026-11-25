import 'dart:convert';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies workflow messaging registration and public composition.
void main() {
  final receipt = EventSubmissionReceipt(
    event_id: 'event-001',
    correlation_id: 'correlation-001',
  );

  final resolution = WorkflowSubmissionResolution(
    receipt: receipt,
    state: WorkflowSubmissionState.pending,
  );

  final start_request = WorkflowStartRequest(
    target_id: 'local-macos',
    root: TargetPath('/workspace'),
    idempotency_key: 'operation-001',
  );

  final stop_request = WorkflowStopRequest(
    workflow_id: 'workflow-001',
    idempotency_key: 'operation-002',
  );

  final submission_request = WorkflowSubmissionRequest(receipt: receipt);

  group('workflow messaging contribution', () {
    test('contributes codecs without finalizing configuration', () {
      const module = WorkflowMessagingModule();
      final registry = MessageCodecRegistry();

      expect(module.module_id, 'rudra.workflow.messaging');

      module.register_codecs(registry);

      expect(registry.is_frozen, isFalse);

      registry.freeze();

      expect(registry.is_frozen, isTrue);

      expect(registry.response_type_for(start_request), WorkflowStartResponse);

      expect(registry.response_type_for(stop_request), WorkflowStopResponse);

      expect(
        registry.response_type_for(submission_request),
        WorkflowSubmissionResponse,
      );
    });

    test('is included in standard application messaging composition', () {
      final modules = standard_messaging_modules();

      final workflow_modules = modules.whereType<WorkflowMessagingModule>();

      expect(workflow_modules, hasLength(1));

      expect(workflow_modules.single.module_id, 'rudra.workflow.messaging');
    });

    test('supports explicit workflow-only messaging composition', () {
      final registry = create_application_message_codecs(
        modules: [const WorkflowMessagingModule()],
      );

      expect(registry.is_frozen, isTrue);

      expect(registry.response_type_for(start_request), WorkflowStartResponse);

      expect(registry.response_type_for(stop_request), WorkflowStopResponse);

      expect(
        registry.response_type_for(submission_request),
        WorkflowSubmissionResponse,
      );
    });
  });

  group('standard workflow messaging configuration', () {
    test('preserves all concrete request-to-response relationships', () {
      final registry = create_application_message_codecs();

      expect(registry.is_frozen, isTrue);

      expect(registry.response_type_for(start_request), WorkflowStartResponse);

      expect(registry.response_type_for(stop_request), WorkflowStopResponse);

      expect(
        registry.response_type_for(submission_request),
        WorkflowSubmissionResponse,
      );
    });

    test('exchanges all workflow messages across independent registries', () {
      final client_codecs = create_application_message_codecs();
      final host_codecs = create_application_message_codecs();

      expect(identical(client_codecs, host_codecs), isFalse);

      final messages = <(Message, String)>[
        (start_request, 'rudra.workflow.start.request.v1'),
        (
          WorkflowStartResponse(
            outcome: WorkflowOperationResolved(resolution: resolution),
          ),
          'rudra.workflow.start.response.v1',
        ),
        (stop_request, 'rudra.workflow.stop.request.v1'),
        (
          const WorkflowStopResponse(
            outcome: WorkflowOperationIdempotencyConflict(),
          ),
          'rudra.workflow.stop.response.v1',
        ),
        (submission_request, 'rudra.workflow.submission.request.v1'),
        (
          WorkflowSubmissionResponse(resolution: resolution),
          'rudra.workflow.submission.response.v1',
        ),
        (
          const WorkflowSubmissionResponse(resolution: null),
          'rudra.workflow.submission.response.v1',
        ),
      ];

      for (final (message, type_id) in messages) {
        // Requests originate from the client and responses from the
        // host, using independently assembled codec configurations.
        final is_request = message is Request<Response>;

        final sender = is_request ? client_codecs : host_codecs;
        final receiver = is_request ? host_codecs : client_codecs;

        final encoded = sender.encode(message);

        expect(encoded.type_id, type_id);

        final payload = jsonDecode(jsonEncode(encoded.payload));

        final decoded = receiver.decode(encoded.type_id, payload);

        expect(decoded.runtimeType, message.runtimeType);

        final reencoded = receiver.encode(decoded);

        expect(reencoded.type_id, encoded.type_id);
        expect(reencoded.payload, encoded.payload);
      }
    });

    test('supports codec configuration without local execution handlers', () {
      final codecs = create_application_message_codecs();
      final handlers = RequestHandlerRegistry();

      handlers.freeze(codecs: codecs);

      expect(codecs.is_frozen, isTrue);
      expect(handlers.is_frozen, isTrue);
    });

    test('excludes workflow messaging when standard modules are replaced', () {
      final registry = create_application_message_codecs(modules: []);

      expect(registry.is_frozen, isTrue);

      final requests = <Message>[
        start_request,
        stop_request,
        submission_request,
      ];

      for (final request in requests) {
        expect(() => registry.encode(request), throwsArgumentError);
      }
    });
  });
}
