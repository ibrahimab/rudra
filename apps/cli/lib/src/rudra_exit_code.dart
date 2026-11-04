/// Defines process exit statuses owned by the Rudra application.
///
/// Rudra commands return numeric process statuses because operating
/// systems and the Dart command runner communicate using integers.
///
/// Application-owned statuses must originate from this enum rather
/// than from unexplained numeric literals.
///
/// Exit value 1 indicates an incomplete filesystem inspection.
///
/// Exit values 64, 70, and 78 follow BSD sysexits conventions.
/// Their meaning is documented here so callers do not have to rely
/// on platform-specific knowledge.
///
/// External subprocess exit codes are not represented by this enum.
/// Those codes must be preserved when reporting subprocess failures.
///
/// Example:
/// ```dart
/// exitCode = RudraExitCode.success.value;
/// ```
enum RudraExitCode {
  /// The requested command completed successfully.
  success(0),

  /// A filesystem inspection could not complete successfully.
  ///
  /// The operation may have returned useful partial observations,
  /// but those observations must not be treated as a complete
  /// filesystem inventory.
  ///
  /// Examples include:
  /// - Permission-denied errors.
  /// - Files disappearing during inspection.
  /// - Interrupted directory enumeration.
  /// - Temporarily unavailable target storage.
  ///
  /// This status does not imply an internal software defect.
  ///
  /// No cleanup authorization or execution is implied.
  inspection_incomplete(1),

  /// The command was invoked with invalid arguments or options.
  invalid_usage(64),

  /// A required input file, manifest, or repository resource is missing.
  missing_input(66),

  /// An internal application or tool execution failure occurred.
  software_error(70),

  /// Required application configuration was invalid or unavailable.
  configuration_error(78);

  /// Associates a Rudra exit status with its process-level value.
  const RudraExitCode(this.value);

  /// Numeric exit status communicated to the operating system.
  final int value;
}
