import 'dart:io';

import 'package:rudra_platform_macos/rudra_platform_macos.dart';

/// Resolves and validates the provisioned machine-wide macOS database.
///
/// Example:
/// ```dart
/// const storage = MacOsHostStorage();
/// final database = await storage.resolve();
/// print(database.path);
/// ```
final class MacOsHostStorage {
  /// Creates an inactive native storage capability.
  const MacOsHostStorage();

  /// Returns the shared database after checking the production layout.
  ///
  /// Throws [FileSystemException] for missing or unsafe provisioned resources.
  /// SQLite creates missing auxiliary files using the shared database mode.
  Future<File> resolve() => validate_macos_storage(
    data_directory: MacOsResourceLayout.data_directory,
    administrator_uid: _root_uid,
    resolve_groups: _macos_group_ids,
  );

  /// Effective UID of the administrator who provisions production resources.
  static const _root_uid = 0;

  /// Returns the native directory-service groups of the process user.
  ///
  /// Apple id -G resolves supplemental groups through Directory Services,
  /// including memberships outside the fixed POSIX process group array.
  /// Its underlying group enumeration SPI is private, so use the system tool.
  static Future<Set<int>> _macos_group_ids() async {
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
}

/// Validates a provisioned [data_directory] using native Darwin metadata.
///
/// The [administrator_uid] must own the data directory, runtime parent and
/// database. [resolve_groups] supplies the current user's authorized groups.
/// Returns the checked database path, without creating or opening the database.
///
/// Throws [FileSystemException] for unsafe resources. Membership resolution
/// failures propagate before storage is opened.
///
/// Example:
/// ```dart
/// final database = await validate_macos_storage(
///   data_directory: provisioned_directory,
///   administrator_uid: uid,
///   resolve_groups: () async => {gid},
/// );
/// ```
Future<File> validate_macos_storage({
  required String data_directory,
  required int administrator_uid,
  required Future<Set<int>> Function() resolve_groups,
}) async {
  final native = DarwinLStat();
  final data = native.inspect_security(data_directory);
  if (data.has_extended_acl ||
      data.metadata.uid != administrator_uid ||
      data.metadata.type != DarwinFileType.directory ||
      data.metadata.permissions != _data_permissions ||
      await Directory(data_directory).resolveSymbolicLinks() !=
          data_directory) {
    throw FileSystemException(
      'Rudra requires a canonical, administrator-owned 1770 data directory.',
      data_directory,
    );
  }

  final group = data.metadata.gid;
  if (!(await resolve_groups()).contains(group)) {
    throw FileSystemException(
      'The effective user is outside the authorized Rudra group.',
      data_directory,
    );
  }

  final runtime_path = '$data_directory/${MacOsResourceLayout.runtime_name}';
  final runtime = native.inspect_security(runtime_path);
  if (runtime.has_extended_acl ||
      runtime.metadata.uid != administrator_uid ||
      runtime.metadata.gid != group ||
      runtime.metadata.type != DarwinFileType.directory ||
      runtime.metadata.permissions != _runtime_permissions) {
    throw FileSystemException(
      'Rudra requires a protected 0750 runtime parent.',
      runtime_path,
    );
  }

  final database = '$data_directory/rudra.sqlite';
  for (final path in [database, '$database-wal', '$database-shm']) {
    if (path != database &&
        await FileSystemEntity.type(path, followLinks: false) ==
            FileSystemEntityType.notFound) {
      continue;
    }

    final resource = native.inspect_security(path);
    if (resource.has_extended_acl ||
        resource.metadata.gid != group ||
        resource.metadata.type != DarwinFileType.regular_file ||
        resource.metadata.permissions != _database_permissions ||
        resource.metadata.links != 1 ||
        (path == database && resource.metadata.uid != administrator_uid)) {
      throw FileSystemException(
        'Rudra requires an authorized group-accessible 0660 database file.',
        path,
      );
    }
  }

  return File(database);
}

/// POSIX 0750 for the administrator-owned runtime parent.
const _runtime_permissions =
    DarwinMode.owner_read_write |
    DarwinMode.owner_execute |
    DarwinMode.group_read |
    DarwinMode.group_execute;

/// POSIX 1770 for shared database storage under a sticky directory.
const _data_permissions =
    _runtime_permissions | DarwinMode.group_write | DarwinMode.sticky;

/// POSIX 0660 for the database and SQLite auxiliary files.
const _database_permissions =
    DarwinMode.owner_read_write |
    DarwinMode.group_read |
    DarwinMode.group_write;
