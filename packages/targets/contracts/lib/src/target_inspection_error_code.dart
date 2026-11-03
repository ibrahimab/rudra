/// Classifies a filesystem inspection failure independently of the
/// underlying operating system.
///
/// Target adapters translate native filesystem errors into these
/// categories before exposing them to the SDK.
///
/// Error codes describe the observed failure. They do not prescribe
/// whether an SDK workflow should retry, stop, or preserve partial
/// results.
///
/// Example:
/// ```dart
/// final code = TargetInspectionErrorCode.permissionDenied;
///
/// if (code == TargetInspectionErrorCode.permissionDenied) {
///   print('Access to the filesystem entry was denied.');
/// }
/// ```
enum TargetInspectionErrorCode {
  /// The requested filesystem entry does not exist.
  ///
  /// This may also occur when an entry disappears during inspection.
  notFound,

  /// The inspecting principal was denied access.
  ///
  /// This does not establish whether another principal could access
  /// the same entry.
  permissionDenied,

  /// An operation required a directory but received another kind
  /// of filesystem entry.
  notDirectory,

  /// An operation required a symbolic link but received another
  /// kind of filesystem entry.
  notSymbolicLink,

  /// The target platform rejected the supplied path.
  ///
  /// This is distinct from an entry that simply does not exist.
  invalidPath,

  /// The requested operation is not supported by the target.
  ///
  /// A missing capability is not necessarily an inspection failure
  /// until an unsupported operation is actually requested.
  unsupportedFeature,

  /// Filesystem path resolution encountered a symbolic-link cycle.
  ///
  /// This does not authorize an adapter to follow symbolic links
  /// implicitly.
  symbolicLinkLoop,

  /// The target filesystem or volume is currently unavailable.
  ///
  /// Examples may include an unavailable mount or disconnected
  /// external storage device.
  targetUnavailable,

  /// A filesystem I/O operation failed for another reason.
  ///
  /// Adapters should prefer a more specific code when the native
  /// failure can be classified reliably.
  ioFailure,
}
