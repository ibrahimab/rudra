/// Defines the macOS runtime locations shared by host and communication.
///
/// Example:
/// ```dart
/// final runtime = MacOsResourceLayout.user_runtime(macos_effective_uid());
/// print(runtime);
/// ```
abstract final class MacOsResourceLayout {
  /// Machine-wide data directory, provisioned by an administrator.
  static const data_directory = '/Library/Application Support/Rudra';

  /// Name of the shared runtime parent in the data directory.
  static const runtime_name = 'runtime';

  /// Administrator-owned parent of the private per-user runtime directories.
  static const runtime_directory = '$data_directory/$runtime_name';

  /// Returns the private runtime pathname for the supplied native [uid].
  static String user_runtime(int uid) => '$runtime_directory/$uid';
}
