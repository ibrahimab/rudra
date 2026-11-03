/// Identifies a filesystem inspection feature.
///
/// Features describe optional information or operations that a
/// target adapter may support.
///
/// Required TargetInspector operations are not represented here.
/// Their failures are communicated through typed inspection errors.
///
/// The availability of a feature does not guarantee that the
/// corresponding metadata exists for every filesystem entry.
///
/// Example:
/// ```dart
/// final feature = TargetInspectionFeature.allocatedSize;
///
/// print(feature.name);
/// // allocatedSize
/// ```
enum TargetInspectionFeature {
  /// Reporting the apparent size of an individual file.
  logicalFileSize,

  /// Reporting filesystem-allocated storage for an entry.
  ///
  /// This does not guarantee that the reported amount is
  /// recoverable by deleting the entry.
  allocatedSize,

  /// Reporting an entry's creation or birth timestamp.
  creationTime,

  /// Reporting an entry's modification timestamp.
  modificationTime,

  /// Reporting an entry's last-access timestamp.
  accessTime,

  /// Reporting filesystem object identities.
  ///
  /// Identities must follow the FilesystemIdentity contract.
  filesystemIdentity,

  /// Reporting POSIX permission and special bits.
  posixMode,

  /// Reporting effective access observations for the
  /// inspecting security principal.
  ///
  /// This does not imply permission to delete an entry.
  effectiveAccess,

  /// Reading the raw stored destination of a symbolic link.
  ///
  /// This feature does not imply that symbolic links are
  /// followed during inspection.
  symbolicLinkTarget,
}
