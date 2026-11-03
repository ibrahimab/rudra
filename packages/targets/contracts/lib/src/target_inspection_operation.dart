/// Identifies the filesystem inspection operation associated with
/// a failure.
///
/// These values correspond to operations exposed by the
/// TargetInspector contract.
///
/// They are intended for diagnostics, error handling, and audit
/// observations without depending on CLI command names.
///
/// Example:
/// ```dart
/// final operation = TargetInspectionOperation.listDirectory;
///
/// print(operation.name);
/// // listDirectory
/// ```
enum TargetInspectionOperation {
  /// Discover available inspection capabilities for a target path.
  capabilitiesFor,

  /// Inspect a single filesystem entry.
  inspect,

  /// Enumerate the immediate children of a directory.
  listDirectory,

  /// Read the stored destination of a symbolic link.
  readSymbolicLink,
}
