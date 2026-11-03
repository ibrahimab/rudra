import 'target_capability_status.dart';
import 'target_inspection_feature.dart';

/// Describes the inspection capabilities reported for a target scope.
///
/// A TargetCapabilities object is an immutable snapshot.
///
/// Capabilities may differ between filesystems, mounted volumes,
/// remote shares, and target environments.
///
/// Instances contain no filesystem implementation details and do
/// not perform filesystem I/O.
///
/// Features absent from [statuses] are treated as unknown.
///
/// A supported feature means the adapter can provide that feature
/// where applicable. It does not guarantee that every entry will
/// have a corresponding metadata value.
///
/// A capability snapshot may become stale if the underlying target
/// environment changes.
///
/// Example:
/// ```dart
/// final capabilities = TargetCapabilities(
///   statuses: {
///     TargetInspectionFeature.allocatedSize:
///         TargetCapabilityStatus.supported,
///   },
/// );
///
/// print(
///   capabilities.status_for(
///     TargetInspectionFeature.allocatedSize,
///   ),
/// );
/// // TargetCapabilityStatus.supported
/// ```
final class TargetCapabilities {
  /// Creates an immutable capability snapshot.
  ///
  /// [statuses] maps inspection features to their observed support
  /// status.
  ///
  /// Features not present in the map default to unknown when
  /// queried through [status_for].
  ///
  /// The supplied map is defensively copied and made unmodifiable.
  /// Subsequent modifications to the original map do not affect
  /// this object.
  ///
  /// An empty map represents entirely unknown capabilities.
  ///
  /// Example:
  /// ```dart
  /// final capabilities = TargetCapabilities();
  ///
  /// print(
  ///   capabilities.status_for(
  ///     TargetInspectionFeature.filesystemIdentity,
  ///   ),
  /// );
  /// // TargetCapabilityStatus.unknown
  /// ```
  TargetCapabilities({
    Map<TargetInspectionFeature, TargetCapabilityStatus> statuses = const {},
  }) : statuses =
            Map<TargetInspectionFeature, TargetCapabilityStatus>.unmodifiable(
          statuses,
        );

  /// The explicitly reported capability statuses.
  ///
  /// This map is immutable.
  ///
  /// Features omitted from the map are implicitly unknown.
  /// Consumers should use [status_for] when querying support.
  final Map<TargetInspectionFeature, TargetCapabilityStatus> statuses;

  /// Returns the reported status of an inspection feature.
  ///
  /// Returns [TargetCapabilityStatus.unknown] when the feature has
  /// not been explicitly reported.
  ///
  /// This method does not perform filesystem I/O.
  ///
  /// Example:
  /// ```dart
  /// final capabilities = TargetCapabilities();
  ///
  /// final status = capabilities.status_for(
  ///   TargetInspectionFeature.posixMode,
  /// );
  ///
  /// assert(status == TargetCapabilityStatus.unknown);
  /// ```
  TargetCapabilityStatus status_for(
    TargetInspectionFeature feature,
  ) {
    return statuses[feature] ?? TargetCapabilityStatus.unknown;
  }
}
