import 'dart:io';

/// Resolves one trusted effective macOS user for host and Unix peer checks.
Future<int> macos_effective_uid() async {
  if (!Platform.isMacOS) {
    throw UnsupportedError('Rudra native resources require macOS.');
  }

  final result = await Process.run('/usr/bin/id', ['-u']);
  final uid = int.tryParse((result.stdout as String).trim());
  if (result.exitCode != 0 || uid == null || uid < 0) {
    throw StateError('Unable to resolve the effective macOS UID.');
  }
  return uid;
}

/// Reads the effective and supplementary macOS groups for this process.
Future<Set<int>> macos_group_ids() async {
  final result = await Process.run('/usr/bin/id', ['-G']);
  if (result.exitCode != 0) {
    throw StateError('Unable to resolve macOS group membership.');
  }
  return (result.stdout as String)
      .trim()
      .split(RegExp(r'\s+'))
      .map(int.parse)
      .toSet();
}

/// Formats a kernel-provided [uid] in the application's macOS namespace.
String macos_user_id(int uid) => 'macos-uid:$uid';

/// Defines the machine-wide macOS layout shared by native capabilities.
///
/// ### Example
///
/// ```dart
/// final uid = await macos_effective_uid();
/// final runtime = MacOsResourceLayout.user_runtime(uid);
/// print(runtime);
/// ```
abstract final class MacOsResourceLayout {
  /// Machine-wide data directory, provisioned by an administrator.
  static const data_directory = '/Library/Application Support/Rudra';

  /// The single shared production SQLite file.
  static const database_path = '$data_directory/rudra.sqlite';

  /// Administrator-owned parent of the private per-user runtime directories.
  static const runtime_directory = '$data_directory/runtime';

  /// Stable ownership resource inside the user's private directory.
  static const lock_filename = 'rudra.lock';

  /// Default IPC endpoint inside the user's private directory.
  static const socket_filename = 'rudra.sock';

  /// Resolves the private runtime pathname for [uid].
  static String user_runtime(int uid) => '$runtime_directory/$uid';
}

/// Native metadata used to validate provisioned filesystem resources.
///
/// Reads the entry itself, including its uid, gid, type, mode and link count.
Future<({int uid, int gid, int mode, int links})> macos_resource_stat(
  String path,
) async {
  final result = await Process.run('/usr/bin/stat', [
    '-f',
    '%u %g %p %l',
    path,
  ]);
  if (result.exitCode != 0) {
    throw FileSystemException('Unable to inspect Rudra resource.', path);
  }
  final fields = (result.stdout as String).trim().split(' ');
  // Require plain POSIX permissions. Extended ACLs can override the mode
  // bits that protect shared resources and private runtime entries.
  final listing = await Process.run('/bin/ls', ['-blde', path]);
  if (listing.exitCode != 0 ||
      (listing.stdout as String).trimRight().contains('\n')) {
    throw FileSystemException(
      'Rudra resources must use plain POSIX permissions.',
      path,
    );
  }
  return (
    uid: int.parse(fields[0]),
    gid: int.parse(fields[1]),
    mode: int.parse(fields[2], radix: 8),
    links: int.parse(fields[3]),
  );
}

/// Requires a canonical, user-owned 0700 directory for runtime resources.
///
/// Provisioning is external. The returned directory has no symbolic link
/// components and grants the effective [uid] exclusive directory access.
Future<Directory> require_macos_private_directory(String path, int uid) async {
  final directory = Directory(path);
  if (!directory.isAbsolute || path.contains('\u0000')) {
    throw ArgumentError.value(
      path,
      'path',
      'Expected an absolute native path.',
    );
  }
  final resource = await macos_resource_stat(path);
  if (resource.uid != uid ||
      resource.mode != 0x41c0 || // Directory with mode 0700.
      await directory.resolveSymbolicLinks() != path) {
    throw FileSystemException(
      'Rudra requires a canonical, user-owned 0700 runtime directory.',
      path,
    );
  }
  return directory;
}
