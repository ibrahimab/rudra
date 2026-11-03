import 'filesystem_entry.dart';
import 'target_capabilities.dart';
import 'target_inspection_error_code.dart';
import 'target_inspection_exception.dart';
import 'target_inspection_operation.dart';
import 'target_path.dart';

/// Defines read-only filesystem inspection operations for a target.
///
/// TargetInspector is the boundary between Rudra's platform-independent
/// SDK and platform-specific filesystem implementations.
///
/// Implementations must use the target platform's filesystem semantics.
/// They must not reinterpret paths using the host platform's rules when
/// the inspected target differs from the host.
///
/// All input paths must be absolute in the target's native syntax.
/// Implementations must reject invalid or relative input paths with
/// [TargetInspectionErrorCode.invalidPath].
///
/// Inspection operations must not create, modify, move, or delete
/// filesystem entries.
///
/// Symbolic links must not be implicitly followed when inspecting the
/// final component of a path.
///
/// The interface does not perform recursive traversal, calculate
/// aggregate directory sizes, or determine whether cleanup is safe.
///
/// Filesystem observations are not atomic snapshots. Entries may
/// change or disappear between operations.
///
/// Implementations translate filesystem failures into
/// [TargetInspectionException], using the corresponding
/// [TargetInspectionOperation].
///
/// Example:
/// ```dart
/// Future<void> inspect_cache(
///   TargetInspector inspector,
///   TargetPath cache_path,
/// ) async {
///   final entry = await inspector.inspect(cache_path);
///
///   print(entry.kind);
///
///   await for (final child_path
///       in inspector.list_directory(cache_path)) {
///     print(child_path.value);
///   }
/// }
/// ```
abstract interface class TargetInspector {
  /// Discovers inspection capabilities for the filesystem at [path].
  ///
  /// The returned [TargetCapabilities] describes the capabilities
  /// applicable to the supplied location.
  ///
  /// Capabilities may vary between mounted filesystems and volumes.
  /// They must not be assumed to apply to every path on the target.
  ///
  /// The operation must not recursively inspect directory contents.
  ///
  /// A returned unknown status means support has not been
  /// established. It must not be used to conceal an operation failure.
  ///
  /// Completes with [TargetInspectionException] when capability
  /// discovery fails because the path cannot be addressed.
  ///
  /// The exception's operation must be
  /// [TargetInspectionOperation.capabilitiesFor].
  ///
  /// Example:
  /// ```dart
  /// final capabilities = await inspector.capabilities_for(
  ///   TargetPath('/Users/example'),
  /// );
  ///
  /// final status = capabilities.status_for(
  ///   TargetInspectionFeature.allocatedSize,
  /// );
  /// ```
  Future<TargetCapabilities> capabilities_for(
    TargetPath path,
  );

  /// Inspects a single filesystem entry at [path].
  ///
  /// The final path component must not be followed when it is a
  /// symbolic link. The returned entry then describes the link
  /// itself, including its own metadata and identity.
  ///
  /// A dangling symbolic link is a valid inspection result.
  ///
  /// The returned metadata contains only observed information.
  /// Unavailable fields remain null.
  ///
  /// This operation must not recurse into directories.
  ///
  /// Completes with [TargetInspectionException] on failure.
  ///
  /// Common error codes include:
  /// - [TargetInspectionErrorCode.notFound]
  /// - [TargetInspectionErrorCode.permissionDenied]
  /// - [TargetInspectionErrorCode.invalidPath]
  /// - [TargetInspectionErrorCode.ioFailure]
  ///
  /// The exception's operation must be
  /// [TargetInspectionOperation.inspect].
  ///
  /// Example:
  /// ```dart
  /// final entry = await inspector.inspect(
  ///   TargetPath('/Users/example/cache.bin'),
  /// );
  ///
  /// print(entry.metadata.logical_size_bytes);
  /// ```
  Future<FilesystemEntry> inspect(
    TargetPath path,
  );

  /// Lazily enumerates the immediate children of a directory.
  ///
  /// Each emitted [TargetPath] identifies one discovered child
  /// using the target platform's native path syntax.
  ///
  /// Emitted paths must be absolute and directly contained within
  /// the requested directory according to target path semantics.
  ///
  /// This operation must not:
  /// - Recurse into child directories.
  /// - Inspect child metadata.
  /// - Follow symbolic links.
  /// - Include synthetic "." or ".." directory entries.
  /// - Modify filesystem contents.
  ///
  /// Enumeration order is unspecified.
  ///
  /// The stream must be single-subscription and lazy, beginning
  /// enumeration when a listener subscribes.
  ///
  /// Cancellation must stop further enumeration as promptly as
  /// the underlying platform permits and release held resources.
  ///
  /// An enumeration failure must be emitted as a
  /// [TargetInspectionException] stream error, followed by closure
  /// of the stream. It must not be converted into an empty result.
  ///
  /// Successfully emitted paths remain partial observations if
  /// enumeration later fails.
  ///
  /// The exception's operation must be
  /// [TargetInspectionOperation.listDirectory].
  ///
  /// A symbolic link to a directory must be rejected with
  /// [TargetInspectionErrorCode.notDirectory] rather than followed.
  ///
  /// Example:
  /// ```dart
  /// await for (final child_path in inspector.list_directory(
  ///   TargetPath('/Users/example/Library/Caches'),
  /// )) {
  ///   final entry = await inspector.inspect(child_path);
  ///
  ///   print(entry.kind);
  /// }
  /// ```
  Stream<TargetPath> list_directory(
    TargetPath path,
  );

  /// Reads the raw stored destination of a symbolic link.
  ///
  /// [path] must identify a symbolic link.
  ///
  /// The returned [TargetPath] preserves the stored destination
  /// without resolving it. It may be relative or absolute.
  ///
  /// This operation must not follow the link or verify that the
  /// destination exists.
  ///
  /// Completes with [TargetInspectionException] on failure.
  ///
  /// A non-symbolic-link entry must produce
  /// [TargetInspectionErrorCode.notSymbolicLink].
  ///
  /// The exception's operation must be
  /// [TargetInspectionOperation.readSymbolicLink].
  ///
  /// Example:
  /// ```dart
  /// final destination = await inspector.read_symbolic_link(
  ///   TargetPath('/Users/example/cache-link'),
  /// );
  ///
  /// print(destination.value);
  /// ```
  Future<TargetPath> read_symbolic_link(
    TargetPath path,
  );
}
