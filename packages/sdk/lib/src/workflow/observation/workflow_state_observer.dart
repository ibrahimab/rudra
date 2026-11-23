import 'dart:async';

import '../../state/rudra_state.dart';
import 'workflow_commit_channel.dart';

/// Observes authoritative SDK application state after committed changes.
///
/// Each subscription registers for notifications before restoring its initial
/// state. A change overlapping restoration causes another authoritative read.
///
/// State is reconstructed by the supplied SDK reader, not by independently
/// applying workflow events in this observer.
///
/// Observation never processes commands or modifies persistence.
///
/// Example:
/// ```dart
/// final observer = WorkflowStateObserver(
///   read_state: application.read_state,
///   commits: persistence.workflow_commit_subscriber,
///   os_user_id: trusted_os_user_id,
/// );
///
/// final subscription = observer.observe().listen((state) {
///   print(state.workflows.current_workflow?.identity.workflow_id);
/// });
///
/// await subscription.cancel();
/// ```
final class WorkflowStateObserver {
  /// Creates an SDK application-state observer.
  ///
  /// [read_state] restores validated, committed application state.
  /// [commits] supplies owner-scoped persistence change notifications.
  /// [os_user_id] is an authenticated owner from trusted composition.
  ///
  /// Throws [ArgumentError] when [os_user_id] is blank.
  /// Construction does not subscribe, read persistence or process commands.
  WorkflowStateObserver({
    required Future<RudraState> Function() read_state,
    required WorkflowCommitSubscriber commits,
    required String os_user_id,
  }) : _read_state = read_state,
       _commits = commits,
       _os_user_id = os_user_id {
    if (os_user_id.trim().isEmpty) {
      throw ArgumentError.value(os_user_id, 'os_user_id');
    }
  }

  /// Authoritative, read-only SDK state restoration operation.
  final Future<RudraState> Function() _read_state;

  /// Persistence-backed notification source for committed workflow changes.
  final WorkflowCommitSubscriber _commits;

  /// Authenticated owner used to scope commit notifications.
  final String _os_user_id;

  /// Observes verified initial state and subsequent committed changes.
  ///
  /// Each listener owns its subscription and reconciliation lifecycle.
  /// Rapid changes may be coalesced into the latest verified snapshot.
  ///
  /// Restoration or notification-source failures are emitted as stream
  /// errors and terminate that subscription. Cancellation stops listening
  /// without submitting commands or modifying persistence.
  Stream<RudraState> observe() {
    return Stream<RudraState>.multi((controller) {
      var active = true;
      var change_number = 0;
      var reconciling = false;

      late final StreamSubscription<void> commit_subscription;

      Future<void> fail(Object error, StackTrace stack_trace) async {
        if (!active) return;

        active = false;
        controller.addError(error, stack_trace);

        try {
          await commit_subscription.cancel();
        } finally {
          controller.close();
        }
      }

      Future<void> reconcile() async {
        if (!active || reconciling) return;

        reconciling = true;

        try {
          while (active) {
            final observed_change_number = change_number;
            final state = await _read_state();

            if (!active) return;

            // A commit overlapped restoration. Discard this potentially
            // stale result and reconstruct from authoritative evidence.
            if (observed_change_number != change_number) {
              continue;
            }

            controller.add(state);
            return;
          }
        } catch (error, stack_trace) {
          await fail(error, stack_trace);
        } finally {
          reconciling = false;
        }
      }

      try {
        // Register before the initial read to close the startup race.
        commit_subscription = _commits
            .watch(os_user_id: _os_user_id)
            .listen(
              (_) {
                change_number++;
                unawaited(reconcile());
              },
              onError: (Object error, StackTrace stack_trace) {
                unawaited(fail(error, stack_trace));
              },
              onDone: () {
                unawaited(
                  fail(
                    StateError(
                      'Workflow commit observation became unavailable.',
                    ),
                    StackTrace.current,
                  ),
                );
              },
            );
      } catch (error, stack_trace) {
        controller.addError(error, stack_trace);
        controller.close();
        return;
      }

      controller.onCancel = () async {
        active = false;
        await commit_subscription.cancel();
      };

      unawaited(reconcile());
    });
  }
}
