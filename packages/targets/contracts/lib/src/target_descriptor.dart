import 'target_capability.dart';

/// Describes a filesystem target available to Rudra.
///
/// A target is the environment being inspected, which may differ from the
/// machine running the frontend.
///
/// The descriptor exposes stable identification and supported capabilities.
/// It does not perform filesystem operations and does not grant permission
/// to modify any files.
///
/// Instances are immutable. The supplied capability set is defensively
/// copied so callers cannot modify the descriptor after construction.
///
/// Example:
/// ```dart
/// final target = TargetDescriptor(
///   target_id: 'local-macos',
///   display_name: 'Local macOS filesystem',
///   platform: TargetPlatform.macos,
///   capabilities: {
///     TargetCapability.list_directory,
///     TargetCapability.inspect_metadata,
///   },
/// );
///
/// assert(target.supports(TargetCapability.list_directory));
/// ```
final class TargetDescriptor {
  /// Creates an immutable description of a filesystem target.
  ///
  /// [target_id] uniquely identifies a target within its configured
  /// registry. It must not be empty or contain only whitespace.
  ///
  /// [display_name] provides a human-readable name for the target.
  /// It must not be empty or contain only whitespace.
  ///
  /// [platform] describes the target operating-system family.
  ///
  /// [capabilities] contains the operations supported by the adapter.
  /// An empty set represents a target without available operations.
  ///
  /// Throws [ArgumentError] if either identifier or display name is blank.
  TargetDescriptor({
    required String target_id,
    required String display_name,
    required this.platform,
    required Set<TargetCapability> capabilities,
  }) : target_id = _require_non_blank(target_id, 'target_id'),
       display_name = _require_non_blank(display_name, 'display_name'),
       capabilities = Set<TargetCapability>.unmodifiable(capabilities);

  /// Unique identifier of this target within its configured registry.
  ///
  /// Uniqueness must be enforced by the registry constructing descriptors.
  final String target_id;

  /// Human-readable target name for display in application interfaces.
  final String display_name;

  /// Operating-system family of the target.
  final TargetPlatform platform;

  /// Immutable set of operations supported by this target.
  ///
  /// A supported operation may still fail due to permissions, unavailable
  /// resources, or changes in the filesystem.
  final Set<TargetCapability> capabilities;

  /// Returns whether the target advertises [capability].
  ///
  /// This is a capability check, not an authorization check.
  ///
  /// A return value of `true` does not guarantee that an individual
  /// filesystem operation will succeed.
  ///
  /// Example:
  /// ```dart
  /// if (target.supports(TargetCapability.measure_usage)) {
  ///   // The application may offer the user a disk usage scan.
  /// }
  /// ```
  bool supports(TargetCapability capability) {
    return capabilities.contains(capability);
  }

  /// Validates that a required string is not blank.
  ///
  /// Preserves the original value rather than silently modifying it.
  ///
  /// Throws [ArgumentError] if [value] is empty or whitespace-only.
  static String _require_non_blank(String value, String parameter_name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        parameter_name,
        'Must not be empty or contain only whitespace.',
      );
    }

    return value;
  }
}
