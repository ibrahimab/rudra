/// Identifies the type of a filesystem entry.
///
/// The kind describes the entry itself, without following symbolic
/// links or interpreting the type of a linked destination.
///
/// A target adapter determines this value using the target
/// platform's filesystem semantics.
///
/// Example:
/// ```dart
/// final kind = FilesystemEntryKind.symbolicLink;
///
/// if (kind == FilesystemEntryKind.symbolicLink) {
///   print('Symbolic link detected.');
/// }
/// ```
enum FilesystemEntryKind {
  /// A regular filesystem file.
  ///
  /// This does not imply that the file can be read or deleted.
  regularFile,

  /// A directory containing filesystem entries.
  ///
  /// This does not imply that enumeration is permitted.
  directory,

  /// A symbolic link.
  ///
  /// The destination is not automatically inspected or followed.
  symbolicLink,

  /// A recognized filesystem entry of another type.
  ///
  /// Examples include sockets, named pipes, and device nodes.
  ///
  /// This value must not be used merely because an adapter
  /// failed to determine an entry's type.
  other,
}
