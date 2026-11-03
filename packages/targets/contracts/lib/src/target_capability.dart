/// Describes a filesystem operation supported by a Rudra target.
///
/// Capabilities are advertised by target adapters and allow the shared SDK
/// to determine which operations are available without knowing the
/// operating system or implemenation details.
///
/// A capability describes technical support, not user authorization.
///
/// In particular, advertising a capability must never be interpreted as
/// permission to perform an operation automatically.
///
/// Example:
/// ```dart
/// const capability = TargetCapability.list_directory;
/// ```
enum TargetCapability {
  /// Enumerate the immediate children of a directory.
  ///
  /// This does not imply permission to recursively scan descendants.
  list_directory,

  /// Read filesystem metadata such as entry type, size, and timestamps.
  ///
  /// The exact metadata available depends on the target implementation.
  inspect_metadata,

  /// Calculate the storage consumed by filesystem entries.
  ///
  /// Measuring storage must not modify the inspected filesystem.
  /// Different target adapters may offer different measurement semantics.
  measure_usage,
}

/// Identifies the operating-system family of a Rudra target.
///
/// This describes the target environment, not necessarily the OS hosting
/// the Rudra frontend.
///
/// For example, a future Windows desktop frontend could inspect a Linux
/// filesystem through a remote target adapter.
///
/// Application policies must rely on [TargetCapability] rather than
/// assuming functionality from the operating-system family.
enum TargetPlatform {
  /// Apple's macOS operating system.
  macos,

  /// Microsoft Windows operating systems.
  windows,

  /// Linux-based operating systems.
  linux,

  /// A target that does not belong to a known operating-system family.
  other,
}
