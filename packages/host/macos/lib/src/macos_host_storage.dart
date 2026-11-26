import 'dart:io';

import 'package:rudra_platform_macos/rudra_platform_macos.dart';

/// Resolves and validates the provisioned machine-wide macOS database.
///
/// ### Example
///
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
  Future<File> resolve() async {
    const data = MacOsResourceLayout.data_directory;
    const runtime = MacOsResourceLayout.runtime_directory;
    const database = MacOsResourceLayout.database_path;

    final directory = await macos_resource_stat(data);
    if (directory.uid != 0 ||
        directory.mode != 0x43f8 || // Directory with mode 1770.
        await Directory(data).resolveSymbolicLinks() != data) {
      throw FileSystemException(
        'Rudra requires a root-owned 1770 data directory.',
        data,
      );
    }

    if (!(await macos_group_ids()).contains(directory.gid)) {
      throw FileSystemException(
        'The effective user is outside the authorized Rudra group.',
        data,
      );
    }

    final runtime_parent = await macos_resource_stat(runtime);
    if (runtime_parent.uid != 0 ||
        runtime_parent.gid != directory.gid ||
        runtime_parent.mode != 0x41e8) {
      // Directory with mode 0750.
      throw FileSystemException(
        'Rudra requires a protected 0750 runtime parent.',
        runtime,
      );
    }

    for (final path in [database, '$database-wal', '$database-shm']) {
      if (path != database &&
          await FileSystemEntity.type(path, followLinks: false) ==
              FileSystemEntityType.notFound) {
        continue;
      }

      final resource = await macos_resource_stat(path);
      if (resource.gid != directory.gid ||
          resource.mode != 0x81b0 || // Regular file with mode 0660.
          resource.links != 1 ||
          (path == database && resource.uid != 0)) {
        throw FileSystemException(
          'Rudra requires an authorized group-accessible 0660 database file.',
          path,
        );
      }
    }

    return File(database);
  }
}
