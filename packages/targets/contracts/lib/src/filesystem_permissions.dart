/// Describes available permission information for a filesystem entry.
///
/// Permission information is observational and may be incomplete.
///
/// [posix_mode] contains only the low 12 POSIX permission and special
/// bits, excluding file-type bits.
///
/// Effective access fields describe access observed for the
/// inspecting security principal at inspection time. They must not
/// be inferred from POSIX mode bits alone.
///
/// A null field means the information is unavailable or unknown.
/// It must not be interpreted as permission being denied.
///
/// Permission observations are not authorization guarantees.
/// Filesystem ACLs, ownership, mount settings, and concurrent
/// changes can affect actual access.
///
/// In particular, write access to a file does not imply that the
/// file can be deleted.
///
/// Example:
/// ```dart
/// final permissions = FilesystemPermissions(
///   posix_mode: 0x1A4,
///   effective_readable: true,
/// );
///
/// print(permissions.posix_mode);
/// // 420, equivalent to octal 0644
///
/// print(permissions.effective_writable);
/// // null: not determined
/// ```
final class FilesystemPermissions {
  /// Creates an immutable permission observation.
  ///
  /// [posix_mode], when provided, must be between zero and
  /// 0x0FFF inclusive.
  ///
  /// Effective access observations are independent of [posix_mode].
  /// They may be true, false, or null when unknown.
  ///
  /// Throws [RangeError] when [posix_mode] is outside its valid range.
  ///
  /// Example:
  /// ```dart
  /// final permissions = FilesystemPermissions(
  ///   posix_mode: 0x1A4,
  /// );
  /// ```
  FilesystemPermissions({
    this.posix_mode,
    this.effective_readable,
    this.effective_writable,
    this.effective_executable,
  }) {
    if (posix_mode != null && (posix_mode! < 0 || posix_mode! > 0x0FFF)) {
      throw RangeError.range(
        posix_mode!,
        0,
        0x0FFF,
        'posix_mode',
        'Invalid POSIX permission bits.',
      );
    }
  }

  /// The POSIX permission and special bits, when available.
  ///
  /// This excludes the file-type bits of a native POSIX mode value.
  final int? posix_mode;

  /// Whether read access was observed for the inspecting principal.
  ///
  /// Null means that effective read access was not determined.
  final bool? effective_readable;

  /// Whether write access was observed for the inspecting principal.
  ///
  /// This does not establish whether deletion is permitted.
  /// Null means that effective write access was not determined.
  final bool? effective_writable;

  /// Whether execute or traversal access was observed.
  ///
  /// Interpretation depends on the entry type and target platform.
  /// Null means that effective access was not determined.
  final bool? effective_executable;
}
