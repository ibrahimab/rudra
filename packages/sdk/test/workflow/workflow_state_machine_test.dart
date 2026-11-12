import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies the deterministic, side-effect-free workflow state machine.
///
/// All tests operate entirely on in-memory domain objects.
///
/// No filesystem adapter, event store, database, or application
/// frontend is constructed.
void main() {
  const machine = WorkflowStateMachine();

  group('WorkflowStateMachine.transition', () {
    test('transitions from initial to start requested', () {
      const initial = WorkflowInitialState();
      final event = _start_event();

      final result = machine.transition(
        state: initial,
        event: event,
      );

      expect(result, isA<WorkflowStartRequestedState>());

      final requested = result as WorkflowStartRequestedState;

      expect(requested.version, 1);
      expect(requested.target_id, event.target_id);
      expect(requested.root, same(event.root));

      // Applying an event cannot modify the previous state.
      expect(initial.version, 0);
    });

    test('a start request does not activate a workflow', () {
      final result = machine.transition(
        state: const WorkflowInitialState(),
        event: _start_event(),
      );

      expect(result, isA<WorkflowStartRequestedState>());
      expect(result, isNot(isA<WorkflowActiveState>()));
    });

    test('transitions from requested to active', () {
      final requested = _requested_state();
      final identity = _create_identity();

      final result = machine.transition(
        state: requested,
        event: WorkflowStartedEvent(identity: identity),
      );

      expect(result, isA<WorkflowActiveState>());

      final active = result as WorkflowActiveState;

      expect(active.version, 2);
      expect(active.identity, same(identity));

      // Existing state snapshots remain unchanged.
      expect(requested.version, 1);
      expect(requested.target_id, 'local-macos');
    });

    test('accepts separately constructed equivalent root paths', () {
      final requested = _requested_state();

      final identity = _create_identity(
        root: '/Users/example/Downloads',
      );

      // The identity has a different TargetPath instance
      // containing the same target-native path.
      expect(identity.root, isNot(same(requested.root)));

      final result = machine.transition(
        state: requested,
        event: WorkflowStartedEvent(identity: identity),
      );

      expect(result, isA<WorkflowActiveState>());
      expect(result.version, 2);
    });

    test('transitions from active to ended', () {
      final identity = _create_identity();
      final active = _active_state(identity: identity);

      final result = machine.transition(
        state: active,
        event: WorkflowEndedEvent(
          workflow_id: identity.workflow_id,
        ),
      );

      expect(result, isA<WorkflowEndedState>());

      final ended = result as WorkflowEndedState;

      expect(ended.version, 3);
      expect(ended.identity, same(identity));
      expect(active.version, 2);
    });

    test('rejects a different target at workflow start', () {
      final requested = _requested_state();

      final event = WorkflowStartedEvent(
        identity: _create_identity(
          target_id: 'local-windows',
        ),
      );

      _expect_transition_error(
        machine,
        requested,
        event,
        WorkflowTransitionErrorCode.target_mismatch,
      );

      expect(requested.version, 1);
    });

    test('rejects changes to the original root', () {
      final requested = _requested_state();

      final event = WorkflowStartedEvent(
        identity: _create_identity(
          root: '/Users/example/Documents',
        ),
      );

      _expect_transition_error(
        machine,
        requested,
        event,
        WorkflowTransitionErrorCode.root_mismatch,
      );

      expect(requested.root.value, '/Users/example/Downloads');
      expect(requested.version, 1);
    });

    test('preserves target-native path spelling', () {
      final requested = WorkflowStartRequestedState(
        target_id: 'local-windows',
        root: TargetPath(r'C:\Users\example\Downloads'),
        version: 1,
      );

      final identity = _create_identity(
        target_id: 'local-windows',
        root: r'C:\Users\example\Downloads',
      );

      final result = machine.transition(
        state: requested,
        event: WorkflowStartedEvent(identity: identity),
      );

      expect(result, isA<WorkflowActiveState>());

      final active = result as WorkflowActiveState;

      expect(
        active.identity.root.value,
        r'C:\Users\example\Downloads',
      );
    });

    test('rejects ending another workflow', () {
      final active = _active_state();

      final event = WorkflowEndedEvent(
        workflow_id: 'different-workflow',
      );

      _expect_transition_error(
        machine,
        active,
        event,
        WorkflowTransitionErrorCode.workflow_id_mismatch,
      );

      expect(active.version, 2);
    });

    test('rejects every unspecified lifecycle transition', () {
      const initial = WorkflowInitialState();
      final requested = _requested_state();
      final active = _active_state();
      final ended = _ended_state();

      final invalid_cases = <(WorkflowState, WorkflowEvent)>[
        // A workflow cannot start without a request.
        (initial, WorkflowStartedEvent(identity: _create_identity())),

        // A workflow cannot end before it starts.
        (initial, WorkflowEndedEvent(workflow_id: 'workflow-1')),

        // A pending request cannot be submitted again.
        (requested, _start_event()),

        // A pending request cannot be ended directly.
        (requested, WorkflowEndedEvent(workflow_id: 'workflow-1')),

        // An active workflow cannot be started again.
        (active, _start_event()),

        // An active workflow cannot receive a second started outcome.
        (active, WorkflowStartedEvent(identity: _create_identity())),

        // Terminal workflows cannot be restarted or ended again.
        (ended, _start_event()),
        (ended, WorkflowStartedEvent(identity: _create_identity())),
        (ended, WorkflowEndedEvent(workflow_id: 'workflow-1')),
      ];

      for (final (state, event) in invalid_cases) {
        _expect_transition_error(
          machine,
          state,
          event,
          WorkflowTransitionErrorCode.invalid_transition,
        );
      }

      expect(initial.version, 0);
      expect(requested.version, 1);
      expect(active.version, 2);
      expect(ended.version, 3);
    });

    test('rejects unsupported event implementations', () {
      final states = <WorkflowState>[
        const WorkflowInitialState(),
        _requested_state(),
        _active_state(),
        _ended_state(),
      ];

      final event = _UnknownWorkflowEvent();

      for (final state in states) {
        _expect_transition_error(
          machine,
          state,
          event,
          WorkflowTransitionErrorCode.unsupported_event,
        );
      }
    });
  });

  group('WorkflowStateMachine.replay', () {
    test('empty history produces initial state', () {
      final result = machine.replay(const <WorkflowEvent>[]);

      expect(result, isA<WorkflowInitialState>());
      expect(result.version, 0);
    });

    test('replays a complete workflow history', () {
      final result = machine.replay(_valid_history());

      expect(result, isA<WorkflowEndedState>());
      expect(result.version, 3);

      final ended = result as WorkflowEndedState;

      expect(ended.identity.workflow_id, 'workflow-1');
      expect(ended.identity.os_user_id, 'user-1');
      expect(ended.identity.target_id, 'local-macos');

      expect(
        ended.identity.root.value,
        '/Users/example/Downloads',
      );
    });

    test('replays incomplete workflow histories', () {
      final events = _valid_history();

      final requested = machine.replay(events.take(1));
      final active = machine.replay(events.take(2));
      final ended = machine.replay(events);

      expect(requested, isA<WorkflowStartRequestedState>());
      expect(active, isA<WorkflowActiveState>());
      expect(ended, isA<WorkflowEndedState>());

      expect(requested.version, 1);
      expect(active.version, 2);
      expect(ended.version, 3);
    });

    test('replay and individual transitions produce equivalent state', () {
      final events = _valid_history();

      WorkflowState state = const WorkflowInitialState();

      for (final event in events) {
        state = machine.transition(
          state: state,
          event: event,
        );
      }

      final replayed = machine.replay(events);

      expect(replayed.runtimeType, state.runtimeType);
      expect(replayed.version, state.version);

      final direct = state as WorkflowEndedState;
      final reconstructed = replayed as WorkflowEndedState;

      expect(
        reconstructed.identity.workflow_id,
        direct.identity.workflow_id,
      );

      expect(
        reconstructed.identity.os_user_id,
        direct.identity.os_user_id,
      );

      expect(
        reconstructed.identity.target_id,
        direct.identity.target_id,
      );

      expect(
        reconstructed.identity.root.value,
        direct.identity.root.value,
      );
    });

    test('repeating replay is deterministic', () {
      final events = _valid_history();

      final first = machine.replay(events);
      final second = machine.replay(events);

      expect(first.runtimeType, second.runtimeType);
      expect(first.version, second.version);

      final first_ended = first as WorkflowEndedState;
      final second_ended = second as WorkflowEndedState;

      expect(
        first_ended.identity.workflow_id,
        second_ended.identity.workflow_id,
      );

      expect(
        first_ended.identity.root.value,
        second_ended.identity.root.value,
      );
    });

    test('rejects contradictory history with event index', () {
      final events = <WorkflowEvent>[
        _start_event(),
        WorkflowStartedEvent(
          identity: _create_identity(
            root: '/different-root',
          ),
        ),
      ];

      expect(
        () => machine.replay(events),
        throwsA(
          isA<WorkflowReplayException>()
              .having(
                (error) => error.event_index,
                'event_index',
                1,
              )
              .having(
                (error) => error.cause.code,
                'cause.code',
                WorkflowTransitionErrorCode.root_mismatch,
              )
              .having(
                (error) => error.cause.state.version,
                'applied version',
                1,
              ),
        ),
      );
    });

    test('rejects an outcome without its preceding request', () {
      final events = <WorkflowEvent>[
        WorkflowStartedEvent(identity: _create_identity()),
      ];

      expect(
        () => machine.replay(events),
        throwsA(
          isA<WorkflowReplayException>()
              .having(
                (error) => error.event_index,
                'event_index',
                0,
              )
              .having(
                (error) => error.cause.code,
                'cause.code',
                WorkflowTransitionErrorCode.invalid_transition,
              ),
        ),
      );
    });

    test('rejects history containing events after termination', () {
      final events = <WorkflowEvent>[
        ..._valid_history(),
        _start_event(),
      ];

      expect(
        () => machine.replay(events),
        throwsA(
          isA<WorkflowReplayException>()
              .having(
                (error) => error.event_index,
                'event_index',
                3,
              )
              .having(
                (error) => error.cause.code,
                'cause.code',
                WorkflowTransitionErrorCode.invalid_transition,
              ),
        ),
      );
    });

    test('rejects unsupported events during replay', () {
      final events = <WorkflowEvent>[
        _start_event(),
        _UnknownWorkflowEvent(),
      ];

      expect(
        () => machine.replay(events),
        throwsA(
          isA<WorkflowReplayException>()
              .having(
                (error) => error.event_index,
                'event_index',
                1,
              )
              .having(
                (error) => error.cause.code,
                'cause.code',
                WorkflowTransitionErrorCode.unsupported_event,
              ),
        ),
      );
    });
  });
}

/// Creates a valid workflow-start event.
///
/// Parameters allow tests to customize the requested bindings.
WorkflowStartEvent _start_event({
  String target_id = 'local-macos',
  String root = '/Users/example/Downloads',
}) {
  return WorkflowStartEvent(
    target_id: target_id,
    root: TargetPath(root),
  );
}

/// Creates an established workflow identity for test fixtures.
///
/// The default bindings match [_start_event].
WorkflowIdentity _create_identity({
  String workflow_id = 'workflow-1',
  String os_user_id = 'user-1',
  String target_id = 'local-macos',
  String root = '/Users/example/Downloads',
}) {
  return WorkflowIdentity(
    workflow_id: workflow_id,
    os_user_id: os_user_id,
    target_id: target_id,
    root: TargetPath(root),
  );
}

/// Creates a valid pending workflow state.
WorkflowStartRequestedState _requested_state() {
  return WorkflowStartRequestedState(
    target_id: 'local-macos',
    root: TargetPath('/Users/example/Downloads'),
    version: 1,
  );
}

/// Creates a valid active workflow state.
WorkflowActiveState _active_state({
  WorkflowIdentity? identity,
}) {
  return WorkflowActiveState(
    identity: identity ?? _create_identity(),
    version: 2,
  );
}

/// Creates a valid terminal workflow state.
WorkflowEndedState _ended_state() {
  return WorkflowEndedState(
    identity: _create_identity(),
    version: 3,
  );
}

/// Creates a complete, valid workflow event history.
///
/// The list represents three committed events in order.
List<WorkflowEvent> _valid_history() {
  return [
    _start_event(),
    WorkflowStartedEvent(
      identity: _create_identity(),
    ),
    WorkflowEndedEvent(
      workflow_id: 'workflow-1',
    ),
  ];
}

/// Verifies that a transition is rejected with the expected type.
///
/// Both the original state and event must remain available through
/// the exception for diagnostics.
void _expect_transition_error(
  WorkflowStateMachine machine,
  WorkflowState state,
  WorkflowEvent event,
  WorkflowTransitionErrorCode code,
) {
  expect(
    () => machine.transition(
      state: state,
      event: event,
    ),
    throwsA(
      isA<WorkflowTransitionException>()
          .having(
            (error) => error.code,
            'code',
            code,
          )
          .having(
            (error) => error.state,
            'state',
            same(state),
          )
          .having(
            (error) => error.event,
            'event',
            same(event),
          ),
    ),
  );
}

/// A deliberately unsupported workflow event.
///
/// Its existence verifies that unrelated implementations cannot
/// bypass typed event dispatch.
final class _UnknownWorkflowEvent implements WorkflowEvent {
  @override
  String get event_type => 'workflow.unknown';
}
