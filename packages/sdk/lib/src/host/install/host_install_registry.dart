import 'host_install_step.dart';

/// Validates installation contributions and their dependency ordering.
///
/// The registry retains a deterministic installation order.
/// Uninstallation uses the reverse of that order.
///
/// Registration inspects contribution metadata without invoking
/// resource inspection or mutation methods.
///
/// Example:
/// ```dart
/// final registry = HostInstallRegistry([
///   storage_step,
///   executable_step,
///   service_step,
/// ]);
///
/// final ordered = registry.installation_order;
/// ```
final class HostInstallRegistry {
  /// Validates and orders the supplied [steps].
  ///
  /// Throws [ArgumentError] for blank identifiers.
  ///
  /// Throws [StateError] for duplicate identifiers, unknown
  /// prerequisites or cyclic dependencies.
  factory HostInstallRegistry(Iterable<HostInstallStep> steps) {
    final registrations = <String, HostInstallStep>{};
    final dependencies = <String, Set<String>>{};

    for (final step in steps) {
      final id = step.id;

      if (id.trim().isEmpty) {
        throw ArgumentError.value(id, 'id');
      }

      if (registrations.containsKey(id)) {
        throw StateError('Duplicate host installation step: $id');
      }

      registrations[id] = step;
      dependencies[id] = Set<String>.of(step.prerequisites);
    }

    // Resolve all prerequisite references before ordering the steps.
    for (final entry in dependencies.entries) {
      for (final prerequisite in entry.value) {
        if (!registrations.containsKey(prerequisite)) {
          throw StateError(
            'Unknown installation prerequisite: '
            '$prerequisite (step: ${entry.key})',
          );
        }
      }
    }

    final pending = registrations.keys.toList();
    final resolved = <String>{};
    final ordered = <HostInstallStep>[];

    // Select the first eligible contribution in registration order.
    // Dependencies always take precedence over registration order.
    while (pending.isNotEmpty) {
      final index = pending.indexWhere(
        (id) => dependencies[id]!.every(resolved.contains),
      );

      if (index == -1) {
        throw StateError(
          'Cyclic host installation dependencies: '
          '${pending.join(', ')}',
        );
      }

      final id = pending.removeAt(index);

      resolved.add(id);
      ordered.add(registrations[id]!);
    }

    return HostInstallRegistry._(List<HostInstallStep>.unmodifiable(ordered));
  }

  /// Retains the validated installation order.
  HostInstallRegistry._(this.installation_order);

  /// Immutable contributions ordered by installation prerequisites.
  final List<HostInstallStep> installation_order;

  /// Immutable contributions ordered for safe removal.
  ///
  /// Dependent resources precede their prerequisites.
  List<HostInstallStep> get uninstallation_order =>
      List<HostInstallStep>.unmodifiable(installation_order.reversed);

  /// Returns the ordered contributions for [operation].
  ///
  /// Installation follows dependency order. Uninstallation
  /// follows reverse dependency order.
  List<HostInstallStep> ordered_for(HostInstallOperation operation) {
    return switch (operation) {
      HostInstallOperation.install => installation_order,
      HostInstallOperation.uninstall => uninstallation_order,
    };
  }
}
