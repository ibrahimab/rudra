/// Explicit installation operation requested by trusted composition.
enum HostInstallOperation {
  /// Establishes or repairs managed installation resources.
  install,

  /// Removes managed installation resources while retaining user data.
  uninstall,
}

/// Current condition of a step relative to the requested operation.
enum HostInstallDisposition {
  /// The requested resource state is already satisfied.
  satisfied,

  /// The requested resource state requires an explicit change.
  change_required,

  /// A prerequisite or safety condition prevents execution.
  blocked,
}

/// Read-only inspection result for an installation step.
///
/// Describes the observed resource condition and any required changes.
///
/// Example:
/// ```dart
/// const inspection = HostInstallInspection(
///   disposition: HostInstallDisposition.change_required,
///   description: 'The managed executable must be installed.',
/// );
/// ```
final class HostInstallInspection {
  /// Creates an inspection with the observed [disposition]
  /// and a human-readable [description].
  const HostInstallInspection({
    required this.disposition,
    required this.description,
  });

  /// Condition relative to the requested installation operation.
  final HostInstallDisposition disposition;

  /// Description of the observed condition or intended change.
  final String description;
}

/// Contributes one independently managed installation responsibility.
///
/// Native implementations own resource inspection, mutation,
/// permission validation and verification.
///
/// Step identifiers and prerequisites remain stable throughout
/// the lifetime of an installer.
///
/// Example:
/// ```dart
/// final class ExampleInstallStep implements HostInstallStep {
///   @override
///   String get id => 'example';
///
///   @override
///   Set<String> get prerequisites => const {};
///
///   @override
///   Future<HostInstallInspection> inspect(
///     HostInstallOperation operation,
///   ) async {
///     return const HostInstallInspection(
///       disposition: HostInstallDisposition.satisfied,
///       description: 'Resource state is already satisfied.',
///     );
///   }
///
///   @override
///   Future<void> install() async {}
///
///   @override
///   Future<void> uninstall() async {}
/// }
/// ```
abstract interface class HostInstallStep {
  /// Stable identifier of this installation responsibility.
  String get id;

  /// Identifiers of steps that must precede this step during installation.
  ///
  /// Uninstallation reverses this dependency ordering.
  Set<String> get prerequisites;

  /// Inspects the resource state for [operation].
  ///
  /// Returns the observed condition and intended changes without
  /// modifying native resources.
  ///
  /// During planning, resources that earlier registered steps will
  /// establish may still be absent. Their absence alone does not
  /// constitute a blocked plan.
  ///
  /// Inspection failures propagate to the caller.
  Future<HostInstallInspection> inspect(HostInstallOperation operation);

  /// Establishes the managed resources owned by this step.
  ///
  /// Revalidates native prerequisites and resource ownership before
  /// mutation. Repeated execution must be safe or explicitly rejected.
  ///
  /// Completes after the requested changes have been attempted.
  /// The installer subsequently verifies the actual resource state.
  ///
  /// Execution failures propagate to the caller.
  Future<void> install();

  /// Removes explicitly managed resources owned by this step.
  ///
  /// Revalidates native prerequisites and ownership before mutation.
  /// Workflow persistence, journal history and user data are retained.
  ///
  /// Completes after the requested changes have been attempted.
  /// Execution failures propagate to the caller.
  Future<void> uninstall();
}
