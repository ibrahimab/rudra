/// Describes whether an inspection feature is available within
/// a target filesystem's capability scope.
///
/// A supported feature may still produce missing metadata for an
/// individual entry.
///
/// An unsupported feature is known to be unavailable within the
/// reported scope.
///
/// An unknown feature has not been reliably classified.
///
/// Capability states are observations, not authorization guarantees.
///
/// Example:
/// ```dart
/// final status = TargetCapabilityStatus.unknown;
///
/// if (status == TargetCapabilityStatus.unknown) {
///   print('Capability support has not been established.');
/// }
/// ```
enum TargetCapabilityStatus {
  /// The adapter can provide the feature where applicable.
  ///
  /// Individual filesystem entries may still have missing values.
  supported,

  /// The feature is known to be unavailable in this scope.
  unsupported,

  /// The adapter has not established whether the feature is
  /// supported or unsupported.
  ///
  /// Consumers must not interpret this value as unsupported.
  unknown,
}
