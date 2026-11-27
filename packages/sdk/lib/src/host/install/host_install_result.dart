import 'host_install_step.dart';

/// Observed execution outcome of an installation step.
enum HostInstallStepStatus {
  /// The requested state was already satisfied.
  unchanged,

  /// Execution completed and the requested state was verified.
  applied,

  /// A prerequisite or safety condition prevented execution.
  blocked,

  /// Inspection, execution or subsequent verification failed.
  failed,

  /// Execution was not attempted because another step prevented it.
  not_attempted,
}

/// Execution evidence for one installation responsibility.
///
/// A failed step may have partially modified its managed resources.
/// Its actual condition must be inspected before subsequent execution.
final class HostInstallStepResult {
  /// Creates an outcome for [step_id] with the supplied [status].
  ///
  /// [description] describes the observed outcome.
  /// [error] and [stack_trace] optionally retain failure diagnostics.
  const HostInstallStepResult({
    required this.step_id,
    required this.status,
    required this.description,
    this.error,
    this.stack_trace,
  });

  /// Identifier of the installation step.
  final String step_id;

  /// Observed execution outcome.
  final HostInstallStepStatus status;

  /// Description of the outcome or encountered failure.
  final String description;

  /// Original failure, when execution raised an exception.
  final Object? error;

  /// Original failure stack trace, when available.
  final StackTrace? stack_trace;

  /// Whether the requested resource state was confirmed.
  bool get is_successful =>
      status == HostInstallStepStatus.unchanged ||
      status == HostInstallStepStatus.applied;
}

/// Immutable execution report for an explicit installation operation.
///
/// Contains one outcome for every registered step, including steps
/// that could not be attempted following an earlier failure.
///
/// Example:
/// ```dart
/// final result = await installer.install();
///
/// for (final entry in result.entries) {
///   print('${entry.step_id}: ${entry.status.name}');
/// }
/// ```
final class HostInstallResult {
  /// Creates an execution report for [operation].
  ///
  /// [entries] are copied into an immutable collection in
  /// dependency execution order.
  HostInstallResult({
    required this.operation,
    required Iterable<HostInstallStepResult> entries,
  }) : entries = List<HostInstallStepResult>.unmodifiable(entries);

  /// Operation explicitly requested by the caller.
  final HostInstallOperation operation;

  /// Execution outcomes in dependency execution order.
  final List<HostInstallStepResult> entries;

  /// Whether every step confirmed its requested resource state.
  bool get is_successful => entries.every((entry) => entry.is_successful);
}
