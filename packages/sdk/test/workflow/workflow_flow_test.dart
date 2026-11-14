import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies immutable workflow transition registration.
///
/// Tests cover deterministic dispatch, configuration failures,
/// extension without engine changes, and incorrect rule results.
///
/// All tests operate on in-memory domain objects only.
void main() {
  group('WorkflowFlow', () {
    test('standard flow registers the three lifecycle transitions', () {
      final flow = WorkflowFlow.standard();

      expect(flow.transitions, hasLength(3));

      final cases = <(Type, Type, Type)>[
        (WorkflowInitialState, WorkflowStartEvent, WorkflowStartRequestedState),
        (
          WorkflowStartRequestedState,
          WorkflowStartedEvent,
          WorkflowActiveState,
        ),
        (WorkflowActiveState, WorkflowEndedEvent, WorkflowEndedState),
      ];

      for (final (from_state, event_type, to_state) in cases) {
        final rule = flow.transition_for(
          state_type: from_state,
          event_type: event_type,
        );

        expect(rule, isNotNull);
        expect(rule!.destination_state_type, to_state);
        expect(flow.supports_event_type(event_type), isTrue);
      }
    });

    test('rejects duplicate state and event registrations', () {
      final first =
          WorkflowTransition<
            WorkflowInitialState,
            WorkflowStartEvent,
            WorkflowStartRequestedState
          >(
            apply: (state, event, version) {
              return WorkflowStartRequestedState(
                target_id: event.target_id,
                root: event.root,
                version: version,
              );
            },
          );

      final second =
          WorkflowTransition<
            WorkflowInitialState,
            WorkflowStartEvent,
            WorkflowActiveState
          >(
            apply: (state, event, version) {
              return WorkflowActiveState(
                identity: _identity(),
                version: version,
              );
            },
          );

      expect(
        () => WorkflowFlow(transitions: [first, second]),
        throwsA(
          isA<WorkflowFlowException>()
              .having(
                (error) => error.code,
                'code',
                WorkflowFlowErrorCode.duplicate_transition,
              )
              .having(
                (error) => error.source_state_type,
                'source_state_type',
                WorkflowInitialState,
              )
              .having(
                (error) => error.trigger_event_type,
                'trigger_event_type',
                WorkflowStartEvent,
              ),
        ),
      );
    });

    test('defensively copies and freezes registrations', () {
      final original = <WorkflowTransitionDefinition>[
        ...WorkflowFlow.standard().transitions,
      ];

      final flow = WorkflowFlow(transitions: original);

      original.clear();

      expect(flow.transitions, hasLength(3));

      expect(() => flow.transitions.clear(), throwsUnsupportedError);

      expect(
        flow.transition_for(
          state_type: WorkflowInitialState,
          event_type: WorkflowStartEvent,
        ),
        isNotNull,
      );
    });

    test('registration order does not affect replay', () {
      final standard = WorkflowFlow.standard();

      final reversed = WorkflowFlow(
        transitions: standard.transitions.reversed.toList(),
      );

      final events = <WorkflowEvent>[
        _start_event(),
        WorkflowStartedEvent(identity: _identity()),
        WorkflowEndedEvent(workflow_id: 'workflow-1'),
      ];

      final first = WorkflowStateMachine(flow: standard).replay(events);

      final second = WorkflowStateMachine(flow: reversed).replay(events);

      expect(first, isA<WorkflowEndedState>());
      expect(second, isA<WorkflowEndedState>());
      expect(first.version, second.version);

      expect(
        (first as WorkflowEndedState).identity.workflow_id,
        (second as WorkflowEndedState).identity.workflow_id,
      );
    });

    test('does not select transitions using event type strings', () {
      final machine = WorkflowStateMachine();

      final spoofed_event = _SpoofedStartEvent();

      // The identifier is deliberately equal to a registered
      // event's identifier, but the concrete Dart type differs.
      expect(spoofed_event.event_type, WorkflowStartEvent.type_id);

      expect(
        () => machine.transition(
          state: const WorkflowInitialState(),
          event: spoofed_event,
        ),
        throwsA(
          isA<WorkflowTransitionException>().having(
            (error) => error.code,
            'code',
            WorkflowTransitionErrorCode.unsupported_event,
          ),
        ),
      );
    });

    test('supports new states and events without engine changes', () {
      final extended_flow = WorkflowFlow(
        transitions: [
          ...WorkflowFlow.standard().transitions,
          WorkflowTransition<
            WorkflowActiveState,
            _ReviewRequestedEvent,
            _ReviewState
          >(
            apply: (state, event, next_version) {
              return _ReviewState(
                identity: state.identity,
                version: next_version,
              );
            },
          ),
        ],
      );

      final machine = WorkflowStateMachine(flow: extended_flow);

      final result = machine.replay([
        _start_event(),
        WorkflowStartedEvent(identity: _identity()),
        _ReviewRequestedEvent(),
      ]);

      expect(result, isA<_ReviewState>());
      expect(result.version, 3);

      final review_state = result as _ReviewState;

      expect(review_state.identity.workflow_id, 'workflow-1');
      expect(review_state.identity.os_user_id, 'user-1');
      expect(review_state.identity.root.value, '/tmp');

      expect(extended_flow.supports_event_type(_ReviewRequestedEvent), isTrue);
    });

    test('rejects a rule returning an undeclared state type', () {
      final rule =
          WorkflowTransition<
            WorkflowInitialState,
            WorkflowStartEvent,
            WorkflowState
          >(
            apply: (state, event, next_version) {
              // Deliberately declares WorkflowState as its destination
              // while returning a different concrete state type.
              return WorkflowStartRequestedState(
                target_id: event.target_id,
                root: event.root,
                version: next_version,
              );
            },
          );

      final machine = WorkflowStateMachine(
        flow: WorkflowFlow(transitions: [rule]),
      );

      expect(
        () => machine.transition(
          state: const WorkflowInitialState(),
          event: _start_event(),
        ),
        throwsA(
          isA<WorkflowTransitionException>().having(
            (error) => error.code,
            'code',
            WorkflowTransitionErrorCode.result_state_mismatch,
          ),
        ),
      );
    });

    test('rejects a rule producing the wrong version', () {
      final rule =
          WorkflowTransition<
            WorkflowInitialState,
            WorkflowStartEvent,
            WorkflowStartRequestedState
          >(
            apply: (state, event, next_version) {
              return WorkflowStartRequestedState(
                target_id: event.target_id,
                root: event.root,
                version: next_version + 1,
              );
            },
          );

      final machine = WorkflowStateMachine(
        flow: WorkflowFlow(transitions: [rule]),
      );

      expect(
        () => machine.transition(
          state: const WorkflowInitialState(),
          event: _start_event(),
        ),
        throwsA(
          isA<WorkflowTransitionException>().having(
            (error) => error.code,
            'code',
            WorkflowTransitionErrorCode.result_version_mismatch,
          ),
        ),
      );
    });

    test('does not reopen terminal states with a custom rule', () {
      final rule =
          WorkflowTransition<
            WorkflowEndedState,
            WorkflowStartEvent,
            WorkflowStartRequestedState
          >(
            apply: (state, event, next_version) {
              return WorkflowStartRequestedState(
                target_id: event.target_id,
                root: event.root,
                version: next_version,
              );
            },
          );

      final machine = WorkflowStateMachine(
        flow: WorkflowFlow(transitions: [rule]),
      );

      final ended = WorkflowEndedState(identity: _identity(), version: 3);

      expect(ended.is_terminal, isTrue);

      expect(
        () => machine.transition(state: ended, event: _start_event()),
        throwsA(
          isA<WorkflowTransitionException>().having(
            (error) => error.code,
            'code',
            WorkflowTransitionErrorCode.invalid_transition,
          ),
        ),
      );

      expect(ended.version, 3);
    });

    test('wraps malformed transition results during replay', () {
      final rule =
          WorkflowTransition<
            WorkflowInitialState,
            WorkflowStartEvent,
            WorkflowStartRequestedState
          >(
            apply: (state, event, next_version) {
              return WorkflowStartRequestedState(
                target_id: event.target_id,
                root: event.root,
                version: next_version + 1,
              );
            },
          );

      final machine = WorkflowStateMachine(
        flow: WorkflowFlow(transitions: [rule]),
      );

      expect(
        () => machine.replay([_start_event()]),
        throwsA(
          isA<WorkflowReplayException>()
              .having((error) => error.event_index, 'event_index', 0)
              .having(
                (error) => error.cause.code,
                'cause.code',
                WorkflowTransitionErrorCode.result_version_mismatch,
              ),
        ),
      );
    });
  });
}

/// Creates the standard workflow-start test event.
WorkflowStartEvent _start_event() {
  return WorkflowStartEvent(target_id: 'local-macos', root: TargetPath('/tmp'));
}

/// Creates authoritative workflow identity for tests.
WorkflowIdentity _identity() {
  return WorkflowIdentity(
    workflow_id: 'workflow-1',
    os_user_id: 'user-1',
    target_id: 'local-macos',
    root: TargetPath('/tmp'),
  );
}

/// An illustrative event added without changing the engine.
final class _ReviewRequestedEvent implements WorkflowEvent {
  @override
  String get event_type => 'workflow.review_requested';
}

/// An illustrative state added without changing the engine.
final class _ReviewState extends WorkflowState {
  /// Creates an immutable additional lifecycle state.
  _ReviewState({required this.identity, required int version})
    : version = WorkflowState.require_positive_version(version);

  /// Original established workflow identity.
  final WorkflowIdentity identity;

  @override
  final int version;
}

/// An event that attempts to impersonate a known semantic type.
///
/// This must not match the registered WorkflowStartEvent rule.
final class _SpoofedStartEvent implements WorkflowEvent {
  @override
  String get event_type => WorkflowStartEvent.type_id;
}
