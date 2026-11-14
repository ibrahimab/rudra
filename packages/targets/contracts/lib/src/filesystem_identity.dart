/// Identifies a filesystem object within a target's identity namespace.
///
/// A filesystem object may be referenced by multiple paths. For example,
/// two hard links may identify the same regular file.
///
/// Both identifiers are opaque strings. Consumers must not assume they
/// contain POSIX device numbers, inode numbers, or platform-native paths.
///
/// Equality is based on both [filesystem_id] and [entry_id].
///
/// Identity comparisons are meaningful only within the same target's
/// identity namespace. Identifiers may be reused after filesystem
/// objects are removed, so identities must not be treated as permanent
/// authorization keys.
///
/// An identity does not establish how many hard links exist or how much
/// disk space would be recovered by removing an entry.
///
/// Example:
/// ```dart
/// final first = FilesystemIdentity(
///   filesystem_id: 'volume-a',
///   entry_id: '12345',
/// );
///
/// final second = FilesystemIdentity(
///   filesystem_id: 'volume-a',
///   entry_id: '12345',
/// );
///
/// print(first == second);
/// // true
/// ```
final class FilesystemIdentity {
  /// Creates a filesystem identity.
  ///
  /// Neither identifier may be empty or contain only whitespace.
  /// The original identifier strings are preserved unchanged.
  ///
  /// Throws [ArgumentError] if either identifier is blank.
  ///
  /// Example:
  /// ```dart
  /// final identity = FilesystemIdentity(
  ///   filesystem_id: 'volume-a',
  ///   entry_id: '42',
  /// );
  /// ```
  FilesystemIdentity({required this.filesystem_id, required this.entry_id}) {
    if (filesystem_id.trim().isEmpty) {
      throw ArgumentError.value(
        filesystem_id,
        'filesystem_id',
        'Filesystem identity must not be blank.',
      );
    }

    if (entry_id.trim().isEmpty) {
      throw ArgumentError.value(
        entry_id,
        'entry_id',
        'Entry identity must not be blank.',
      );
    }
  }

  /// Opaque identifier of the containing filesystem or volume.
  ///
  /// The target adapter determines its representation.
  final String filesystem_id;

  /// Opaque identifier of the observed filesystem object.
  ///
  /// For a symbolic link, this must identify the link itself,
  /// not the object to which it points.
  final String entry_id;

  /// Compares both identity components.
  ///
  /// Equality does not imply that observations from different
  /// targets refer to the same physical filesystem object.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilesystemIdentity &&
          filesystem_id == other.filesystem_id &&
          entry_id == other.entry_id;

  /// Hash code derived from both identity components.
  ///
  /// Equal identities always produce equal hash codes.
  @override
  int get hashCode => Object.hash(filesystem_id, entry_id);
}
