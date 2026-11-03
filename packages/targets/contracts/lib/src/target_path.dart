/// Represents a filesystem path using the target platform's native syntax.
///
/// A [TargetPath] preserves the exact string supplied by its caller.
/// It does not normalize separators, resolve relative components, expand
/// home directories, or inspect the filesystem.
///
/// Paths may be absolute or relative. The operation receiving a
/// [TargetPath] determines whether a relative path is acceptable.
///
/// Invariants:
/// - The path must not be empty.
/// - The path must not contain a NUL character.
/// - The original spelling is preserved without modification.
///
/// Two paths with different spellings may still refer to the same
/// filesystem entry. Callers must not use string comparisons as a
/// substitute for filesystem identity or canonicalization.
///
/// Example:
/// ```dart
/// final path = TargetPath('/Users/example/Library/Caches');
///
/// print(path.value);
/// // /Users/example/Library/Caches
/// ```
final class TargetPath {
  /// Creates a target-native filesystem path.
  ///
  /// The [value] is preserved exactly as provided.
  ///
  /// Throws [ArgumentError] if [value] is empty or contains a NUL
  /// character.
  ///
  /// This constructor performs no platform-specific path validation.
  ///
  /// Example:
  /// ```dart
  /// final path = TargetPath(r'C:\Users\example\AppData');
  /// ```
  TargetPath(this.value) {
    if (value.isEmpty) {
      throw ArgumentError.value(
        value,
        'value',
        'A target path must not be empty.',
      );
    }

    if (value.contains('\u0000')) {
      throw ArgumentError.value(
        value,
        'value',
        'A target path must not contain a NUL character.',
      );
    }
  }

  /// The unmodified, target-native filesystem path.
  ///
  /// This value must be interpreted using the target adapter's path
  /// semantics, never the host platform's path semantics.
  final String value;
}
