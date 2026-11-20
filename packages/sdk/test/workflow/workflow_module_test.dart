import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/workflow/behaviors/workflow_start_behavior.dart';
import 'package:test/test.dart';

/// Verifies isolated command and domain module registration boundaries.
void main() {
  test('assembles standard command and outcome contracts', () {
    final runtime = WorkflowRuntime.standard();
    expect(runtime.command_behaviors, hasLength(2));
    expect(runtime.outcome_transitions, hasLength(2));
    expect(runtime.lifecycles, hasLength(2));
  });

  test('rejects duplicate module ownership atomically', () {
    final registry = WorkflowModuleRegistry()
      ..register(const LifecycleWorkflowModule());
    expect(
      () => registry.register(const LifecycleWorkflowModule()),
      throwsStateError,
    );
    expect(registry.command_behaviors, hasLength(2));
  });

  test('rejects duplicate concrete command handler types', () {
    final registry = WorkflowModuleRegistry()
      ..register(const LifecycleWorkflowModule());
    expect(
      () => registry.register(
        _TestModule('duplicate.commands', (registration) {
          registration.add(const WorkflowStartBehavior());
        }),
      ),
      throwsStateError,
    );
    expect(registry.command_behaviors, hasLength(2));
  });

  test('failed module leaves previously accepted state unchanged', () {
    final registry = WorkflowModuleRegistry();
    expect(
      () => registry.register(
        _TestModule('test.failed', (registration) {
          registration.add(const WorkflowStartBehavior());
          throw StateError('Simulated registration failure.');
        }),
      ),
      throwsStateError,
    );
    expect(registry.command_behaviors, isEmpty);
    registry.register(
      _TestModule('test.failed', (registration) {
        registration.add(const WorkflowStartBehavior());
      }),
    );
    expect(registry.command_behaviors, hasLength(1));
  });

  test('command registration cannot be changed after assembly', () {
    final registry = WorkflowModuleRegistry();
    final before = registry.command_behaviors;
    registry.register(const LifecycleWorkflowModule());
    expect(before, isEmpty);
    expect(registry.command_behaviors, hasLength(2));
    expect(() => registry.command_behaviors.clear(), throwsUnsupportedError);
  });

  test('start and stop handlers propose only domain outcomes', () {
    final runtime = WorkflowRuntime.standard();
    final identity = WorkflowIdentity(
      workflow_id: 'workflow-1',
      os_user_id: 'user-1',
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );
    final started = runtime.command_behaviors[WorkflowStartEvent]!
        .propose_outcomes(
          WorkflowStartEvent(
            target_id: identity.target_id,
            root: identity.root,
          ),
          identity: identity,
        );
    final ended = runtime.command_behaviors[WorkflowStopEvent]!
        .propose_outcomes(
          WorkflowStopEvent(workflow_id: identity.workflow_id),
          identity: identity,
        );
    expect(started, hasLength(1));
    expect(started.single, isA<WorkflowStartedEvent>());
    expect(ended, hasLength(1));
    expect(ended.single, isA<WorkflowEndedEvent>());
    expect(() => started.clear(), throwsUnsupportedError);
  });
}

/// One isolated synthetic workflow module.
final class _TestModule implements WorkflowModule {
  /// Creates a module with an explicit registration callback.
  const _TestModule(this.module_id, this.contribute);

  /// Stable synthetic module identifier.
  @override
  final String module_id;

  /// Pure registration callback for the test's capability.
  final void Function(WorkflowModuleRegistration) contribute;

  /// Contributes only the registered test capability.
  @override
  void register(WorkflowModuleRegistration registration) =>
      contribute(registration);
}
