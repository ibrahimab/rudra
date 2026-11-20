import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests the immutable, single-engine workflow runtime configuration.
void main() {
  test('registers exact command handlers and committed outcome rules', () {
    final runtime = WorkflowRuntime.standard();
    expect(runtime.command_behaviors[WorkflowStartEvent], isNotNull);
    expect(runtime.command_behaviors[WorkflowStopEvent], isNotNull);
    expect(runtime.outcome_transitions, hasLength(2));
    expect(runtime.outcome_transitions.map((rule) => rule.event_type).toSet(), {
      WorkflowStartedEvent,
      WorkflowEndedEvent,
    });
    expect(runtime.lifecycles['rudra.workflow.active']!.is_terminal, isFalse);
    expect(runtime.lifecycles['rudra.workflow.ended']!.is_terminal, isTrue);
  });

  test('serializes durable commands through the shared runtime codec', () {
    final runtime = WorkflowRuntime.standard();
    final command = WorkflowStartEvent(
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );
    final decoded = runtime.codec.decode(
      event_type: command.event_type,
      payload_json: runtime.codec.encode(command),
    );
    expect(decoded, isA<WorkflowStartEvent>());
    expect(() => runtime.command_behaviors.clear(), throwsUnsupportedError);
    expect(() => runtime.outcome_transitions.clear(), throwsUnsupportedError);
  });
}
