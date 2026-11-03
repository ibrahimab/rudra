import 'filesystem_entry_kind.dart';
import 'filesystem_metadata.dart';
import 'target_path.dart';

/// Represents one observed filesystem entry on a target platform.
///
/// A filesystem entry combines its target-native path, entry kind,
/// and available metadata.
///
/// The object is an immutable observation, not a live reference
/// to a filesystem object.
///
/// Filesystem state may change after the observation was created.
/// Consumers must not treat this object as a guarantee that an
/// entry still exists or retains the same properties.
///
/// Symbolic links are represented as symbolic links. Their
/// destinations must not be followed implicitly.
///
/// Entry paths are interpreted using target-platform semantics.
///
/// Example:
/// ```dart
/// final entry = FilesystemEntry(
///   path: TargetPath('/Users/example/cache.bin'),
///   kind: FilesystemEntryKind.regularFile,
///   metadata: FilesystemMetadata(
///     logical_size_bytes: 1024,
///   ),
/// );
///
/// print(entry.metadata.logical_size_bytes);
/// // 1024
/// ```
final class FilesystemEntry {
  /// Creates an immutable filesystem entry observation.
  ///
  /// The [path] identifies the observed entry using the target's
  /// native path syntax.
  ///
  /// The [kind] describes the entry without implicitly resolving
  /// symbolic links.
  ///
  /// The [metadata] contains whatever information was available
  /// during inspection. Use an empty [FilesystemMetadata] when
  /// no metadata fields could be determined.
  ///
  /// This constructor performs no filesystem I/O.
  ///
  /// Example:
  /// ```dart
  /// final entry = FilesystemEntry(
  ///   path: TargetPath('/tmp'),
  ///   kind: FilesystemEntryKind.directory,
  ///   metadata: FilesystemMetadata(),
  /// );
  /// ```
  FilesystemEntry({
    required this.path,
    required this.kind,
    required this.metadata,
  });

  /// The target-native path of the observed entry.
  final TargetPath path;

  /// The observed kind of the filesystem entry.
  final FilesystemEntryKind kind;

  /// The metadata observed for this entry.
  final FilesystemMetadata metadata;
}
