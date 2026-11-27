import 'host_install_step.dart';

/// Inspection of one registered installation responsibility.
final class HostInstallPlanEntry {
  /// Associates [inspection] with the registered [step_id].
  const HostInstallPlanEntry({required this.step_id, required this.inspection});

  /// Identifier of the inspected installation step.
  final String step_id;

  /// Observed resource condition and intended changes.
  final HostInstallInspection inspection;
}

/// Immutable observation of a requested installation operation.
///
/// Plans describe resource conditions at inspection time.
/// Execution performs fresh inspection before mutation.
///
/// Example:
/// ```dart
/// final plan = await installer.plan();
///
/// if (plan.can_execute) {
///   for (final entry in plan.entries) {
///     print(entry.inspection.description);
///   }
/// }
/// ```
final class HostInstallPlan {
  /// Creates a plan for [operation] from ordered [entries].
  ///
  /// The supplied entries are copied into an immutable collection.
  HostInstallPlan({
    required this.operation,
    required Iterable<HostInstallPlanEntry> entries,
  }) : entries = List<HostInstallPlanEntry>.unmodifiable(entries);

  /// Requested installation or uninstallation operation.
  final HostInstallOperation operation;

  /// Resource inspections in dependency execution order.
  final List<HostInstallPlanEntry> entries;

  /// Whether the inspected operation contains no blocked steps.
  bool get can_execute => entries.every(
    (entry) => entry.inspection.disposition != HostInstallDisposition.blocked,
  );

  /// Whether every resource already satisfies the requested operation.
  bool get is_satisfied => entries.every(
    (entry) => entry.inspection.disposition == HostInstallDisposition.satisfied,
  );
}
