import 'host_install_plan.dart';
import 'host_install_registry.dart';
import 'host_install_result.dart';
import 'host_install_step.dart';

/// Coordinates explicit host installation and removal.
///
/// Trusted composition supplies installation contributions.
/// The installer validates dependency ordering, inspects resource
/// conditions, executes required changes and verifies their results.
///
/// Native resource mutation remains the responsibility of each step.
///
/// Example:
/// ```dart
/// final installer = HostInstaller(steps: native_steps);
///
/// final plan = await installer.plan();
///
/// if (plan.can_execute) {
///   final result = await installer.install();
///   print(result.is_successful);
/// }
/// ```
final class HostInstaller {
  /// Creates an inactive installer from the supplied [steps].
  ///
  /// Registration validates identifiers and dependencies.
  /// Construction performs no resource inspection or mutation.
  ///
  /// Invalid registration metadata propagates from the registry.
  HostInstaller({required Iterable<HostInstallStep> steps})
    : _registry = HostInstallRegistry(steps);

  /// Validated installation contributions and dependency ordering.
  final HostInstallRegistry _registry;

  /// Whether an inspection or execution operation is outstanding.
  bool _is_busy = false;

  /// Inspects the current resource state for [operation].
  ///
  /// Defaults to planning installation. Returns the observed conditions
  /// in the corresponding dependency order.
  ///
  /// Throws [StateError] while another operation is outstanding.
  /// Inspection failures propagate without modifying resources.
  Future<HostInstallPlan> plan({
    HostInstallOperation operation = HostInstallOperation.install,
  }) {
    return _exclusive(() => _inspect(operation));
  }

  /// Verifies the current installation without modifying resources.
  ///
  /// Returns an installation plan whose satisfaction indicates
  /// whether every managed resource meets its installation contract.
  ///
  /// Concurrent operation and inspection failures propagate.
  Future<HostInstallPlan> verify() => plan();

  /// Explicitly establishes the configured installation resources.
  ///
  /// Returns verified execution outcomes for all registered steps.
  ///
  /// A blocked preflight prevents mutation. Failures during execution
  /// stop subsequent steps and retain previously completed changes.
  ///
  /// Initial inspection failures propagate before mutation begins.
  /// Throws [StateError] while another operation is outstanding.
  Future<HostInstallResult> install() {
    return _exclusive(() => _execute(HostInstallOperation.install));
  }

  /// Explicitly removes the configured managed installation resources.
  ///
  /// Steps execute in reverse dependency order. Native implementations
  /// retain workflow persistence and other user data.
  ///
  /// Returns verified execution outcomes, including partial failures.
  ///
  /// Initial inspection failures propagate before mutation begins.
  /// Throws [StateError] while another operation is outstanding.
  Future<HostInstallResult> uninstall() {
    return _exclusive(() => _execute(HostInstallOperation.uninstall));
  }

  /// Executes one [operation] exclusively within this installer.
  ///
  /// Returns the operation's result and releases the local operation
  /// guard on success or failure.
  ///
  /// Throws [StateError] when another operation is outstanding.
  ///
  /// Native implementations remain responsible for coordinating
  /// independent installer processes.
  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    if (_is_busy) {
      throw StateError('A host installation operation is already in progress.');
    }

    _is_busy = true;

    try {
      return await operation();
    } finally {
      _is_busy = false;
    }
  }

  /// Inspects all registered steps for [operation].
  ///
  /// Returns immutable observations in dependency order.
  /// Inspection failures propagate without mutation.
  Future<HostInstallPlan> _inspect(HostInstallOperation operation) async {
    final entries = <HostInstallPlanEntry>[];

    for (final step in _registry.ordered_for(operation)) {
      entries.add(
        HostInstallPlanEntry(
          step_id: step.id,
          inspection: await step.inspect(operation),
        ),
      );
    }

    return HostInstallPlan(operation: operation, entries: entries);
  }

  /// Executes [operation] against freshly inspected resources.
  ///
  /// Returns complete execution evidence in dependency order.
  ///
  /// A blocked preflight prevents all mutation. A later failure
  /// stops further execution without rolling back earlier steps.
  Future<HostInstallResult> _execute(HostInstallOperation operation) async {
    final preflight = await _inspect(operation);
    final results = <HostInstallStepResult>[];

    if (!preflight.can_execute) {
      for (final entry in preflight.entries) {
        final blocked =
            entry.inspection.disposition == HostInstallDisposition.blocked;

        results.add(
          HostInstallStepResult(
            step_id: entry.step_id,
            status: blocked
                ? HostInstallStepStatus.blocked
                : HostInstallStepStatus.not_attempted,
            description: blocked
                ? entry.inspection.description
                : 'Installation preflight was blocked.',
          ),
        );
      }

      return HostInstallResult(operation: operation, entries: results);
    }

    final steps = _registry.ordered_for(operation);

    for (final step in steps) {
      final result = await _execute_step(step, operation);

      results.add(result);

      if (!result.is_successful) {
        // Preserve explicit outcomes for steps that were never attempted.
        for (final remaining in steps.skip(results.length)) {
          results.add(
            HostInstallStepResult(
              step_id: remaining.id,
              status: HostInstallStepStatus.not_attempted,
              description: 'Execution stopped at ${step.id}.',
            ),
          );
        }

        break;
      }
    }

    return HostInstallResult(operation: operation, entries: results);
  }

  /// Reinspects and conditionally executes [step] for [operation].
  ///
  /// Returns a successful outcome only when inspection confirms
  /// the requested resource state.
  ///
  /// Inspection and execution failures are retained in the result.
  Future<HostInstallStepResult> _execute_step(
    HostInstallStep step,
    HostInstallOperation operation,
  ) async {
    try {
      final inspection = await step.inspect(operation);

      switch (inspection.disposition) {
        case HostInstallDisposition.satisfied:
          return HostInstallStepResult(
            step_id: step.id,
            status: HostInstallStepStatus.unchanged,
            description: inspection.description,
          );

        case HostInstallDisposition.blocked:
          return HostInstallStepResult(
            step_id: step.id,
            status: HostInstallStepStatus.blocked,
            description: inspection.description,
          );

        case HostInstallDisposition.change_required:
          break;
      }

      switch (operation) {
        case HostInstallOperation.install:
          await step.install();

        case HostInstallOperation.uninstall:
          await step.uninstall();
      }

      // Successful execution alone does not establish resource state.
      final verification = await step.inspect(operation);

      if (verification.disposition != HostInstallDisposition.satisfied) {
        return HostInstallStepResult(
          step_id: step.id,
          status: HostInstallStepStatus.failed,
          description:
              'Resource verification failed: '
              '${verification.description}',
        );
      }

      return HostInstallStepResult(
        step_id: step.id,
        status: HostInstallStepStatus.applied,
        description: verification.description,
      );
    } catch (error, stack_trace) {
      return HostInstallStepResult(
        step_id: step.id,
        status: HostInstallStepStatus.failed,
        description: 'Installation step ${step.id} failed.',
        error: error,
        stack_trace: stack_trace,
      );
    }
  }
}
