/// Identifies the type portion of a Darwin filesystem mode.
///
/// Example:
/// ```dart
/// final directory = DarwinLStat().inspect('/private/tmp');
/// assert(directory.type == DarwinFileType.directory);
/// ```
enum DarwinFileType {
  /// Named pipe.
  fifo(0x1000),

  /// Character device.
  character_device(0x2000),

  /// Directory.
  directory(0x4000),

  /// Block device.
  block_device(0x6000),

  /// Regular file.
  regular_file(0x8000),

  /// Symbolic link.
  symbolic_link(0xA000),

  /// Unix domain socket.
  socket(0xC000),

  /// Darwin whiteout entry.
  whiteout(0xE000),

  /// Unrecognized file type.
  unknown(0);

  const DarwinFileType(this._bits);

  /// Native bits for the file type in Darwin's mode field.
  final int _bits;

  /// Darwin S_IFMT, isolating the file type from permission flags.
  static const _type_mask = 0xF000;

  /// Returns the file type encoded by native [mode].
  static DarwinFileType from_mode(int mode) {
    final type = mode & _type_mask;
    return values.firstWhere(
      (entry) => entry._bits == type,
      orElse: () => unknown,
    );
  }
}

/// Darwin permission flags independent of the file type.
///
/// Example:
/// ```dart
/// const private_directory = DarwinMode.owner_read_write | DarwinMode.owner_execute;
/// assert(private_directory.toRadixString(8) == '700');
/// ```
abstract final class DarwinMode {
  /// Mask for permission and special bits, equivalent to POSIX 07777.
  static const permission_mask = 0x0FFF;

  /// Permission for the owner to read and write, equivalent to POSIX 0600.
  static const owner_read_write = 0x0180;

  /// Permission for the owner to execute or traverse, equivalent to POSIX 0100.
  static const owner_execute = 0x0040;

  /// Permission for the group to read, equivalent to POSIX 0040.
  static const group_read = 0x0020;

  /// Permission for the group to write, equivalent to POSIX 0020.
  static const group_write = 0x0010;

  /// Permission for the group to execute or traverse, equivalent to POSIX 0010.
  static const group_execute = 0x0008;

  /// Sticky bit, equivalent to POSIX 01000.
  static const sticky = 0x0200;
}
