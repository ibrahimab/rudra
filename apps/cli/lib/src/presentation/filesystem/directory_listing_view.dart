import 'package:rudra_sdk/rudra_sdk.dart';

/// Renders SDK directory observations for the CLI frontend.
///
/// Supports the original machine-friendly listing and a more
/// readable welcome-screen presentation.
///
/// Rendering never inspects or modifies the filesystem.
final class DirectoryListingView {
  /// Creates a stateless directory listing renderer.
  const DirectoryListingView();

  /// Renders the existing TYPE, LOGICAL_BYTES, PATH layout.
  ///
  /// Preserves the explicit unknown-size marker and target paths.
  void render_compact(
    DirectoryListing listing, {
    required StringSink output,
  }) {
    const type_header = 'TYPE';
    const size_header = 'LOGICAL_BYTES';
    const path_header = 'PATH';
    const spacing = '  ';

    final type_width = listing.entries.fold<int>(
      type_header.length,
      (width, entry) {
        final length = entry.kind.name.length;
        return length > width ? length : width;
      },
    );

    final size_width = listing.entries.fold<int>(
      size_header.length,
      (width, entry) {
        final size = entry.metadata.logical_size_bytes?.toString() ?? '?';
        return size.length > width ? size.length : width;
      },
    );

    output.writeln(
      '${type_header.padRight(type_width)}$spacing'
      '${size_header.padLeft(size_width)}$spacing'
      '$path_header',
    );

    for (final entry in listing.entries) {
      final size = entry.metadata.logical_size_bytes?.toString() ?? '?';

      output.writeln(
        '${entry.kind.name.padRight(type_width)}$spacing'
        '${size.padLeft(size_width)}$spacing'
        '${entry.path.value}',
      );
    }
  }

  /// Renders a readable, sorted directory listing.
  ///
  /// Directories are listed first, followed by other entries
  /// in case-insensitive name order.
  ///
  /// Directory sizes are not recursively calculated.
  /// Unknown metadata remains visibly unknown.
  void render_detailed(
    DirectoryListing listing, {
    required StringSink output,
  }) {
    final entries = List<FilesystemEntry>.of(listing.entries)
      ..sort((left, right) {
        final left_directory = left.kind == FilesystemEntryKind.directory;
        final right_directory = right.kind == FilesystemEntryKind.directory;

        if (left_directory != right_directory) {
          return left_directory ? -1 : 1;
        }

        final left_name = _entry_name(left, listing.directory).toLowerCase();
        final right_name = _entry_name(right, listing.directory).toLowerCase();

        final comparison = left_name.compareTo(right_name);
        return comparison != 0
            ? comparison
            : left.path.value.compareTo(right.path.value);
      });

    const name_header = 'NAME';
    const type_header = 'TYPE';
    const size_header = 'SIZE';
    const permissions_header = 'PERMISSIONS';

    final name_width = entries.fold<int>(
      name_header.length,
      (width, entry) {
        final name = _display_name(entry, listing.directory);
        return name.length > width ? name.length : width;
      },
    );

    output.writeln(
      '  ${name_header.padRight(name_width)}  '
      '${type_header.padRight(9)}  '
      '${size_header.padLeft(9)}  '
      '${permissions_header.padRight(11)}  '
      'MODIFIED (UTC)',
    );

    output.writeln(
      '  ${''.padRight(name_width, '─')}  '
      '${''.padRight(9, '─')}  '
      '${''.padRight(9, '─')}  '
      '${''.padRight(11, '─')}  '
      '${''.padRight(16, '─')}',
    );

    for (final entry in entries) {
      output.writeln(
        '  ${_display_name(entry, listing.directory).padRight(name_width)}  '
        '${_entry_type(entry.kind).padRight(9)}  '
        '${_display_size(entry).padLeft(9)}  '
        '${_permissions(entry).padRight(11)}  '
        '${_modified_at(entry.metadata.modified_at)}',
      );
    }

    output.writeln();
    output.writeln(
      '  ${entries.length} observed entries'
      ' · immediate children only',
    );

    if (!listing.is_complete) {
      output.writeln(
        '  WARNING: This directory listing is incomplete.',
      );
    }
  }

  /// Writes typed SDK inspection issues to a diagnostic sink.
  ///
  /// Does not discard valid entries or convert incomplete
  /// observations into a successful inspection.
  void render_issues(
    DirectoryListing listing, {
    required StringSink output,
  }) {
    for (final issue in listing.issues) {
      output.writeln(
        '${issue.operation.name}: '
        '${issue.code.name}: '
        '${issue.path.value}: '
        '${issue.message}',
      );
    }

    if (!listing.is_complete && listing.issues.isEmpty) {
      output.writeln(
        'Filesystem inspection did not complete.',
      );
    }
  }

  /// Derives a displayed name relative to the inspected directory.
  ///
  /// Uses the observed parent path rather than guessing which
  /// separator convention the target uses.
  ///
  /// Unexpected paths are preserved instead of being rewritten.
  static String _entry_name(
    FilesystemEntry entry,
    TargetPath directory,
  ) {
    final path = entry.path.value;
    final parent = directory.value;

    if (!path.startsWith(parent)) {
      return path;
    }

    final suffix = path.substring(parent.length);

    if (suffix.startsWith('/') || suffix.startsWith('\\')) {
      return suffix.substring(1);
    }

    if ((parent.endsWith('/') || parent.endsWith('\\')) && suffix.isNotEmpty) {
      return suffix;
    }

    return path;
  }

  /// Marks an observed directory without following links.
  static String _display_name(
    FilesystemEntry entry,
    TargetPath directory,
  ) {
    final name = _entry_name(entry, directory);

    return entry.kind == FilesystemEntryKind.directory ? '$name/' : name;
  }

  /// Converts a typed entry kind into a friendly label.
  static String _entry_type(FilesystemEntryKind kind) {
    return switch (kind) {
      FilesystemEntryKind.directory => 'Directory',
      FilesystemEntryKind.regularFile => 'File',
      FilesystemEntryKind.symbolicLink => 'Link',
      FilesystemEntryKind.other => 'Other',
    };
  }

  /// Formats the individual entry's logical size.
  ///
  /// Directory sizes are omitted because they are not
  /// recursively calculated. Null file sizes remain unknown.
  static String _display_size(FilesystemEntry entry) {
    if (entry.kind == FilesystemEntryKind.directory) {
      return '—';
    }

    final bytes = entry.metadata.logical_size_bytes;

    if (bytes == null) {
      return '?';
    }

    if (bytes < 1024) {
      return '$bytes B';
    }

    const units = ['KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB'];

    var value = bytes.toDouble();
    var unit_index = -1;

    while (value >= 1024 && unit_index < units.length - 1) {
      value /= 1024;
      unit_index++;
    }

    return '${value.toStringAsFixed(1)} ${units[unit_index]}';
  }

  /// Formats observed POSIX mode bits, including special bits.
  ///
  /// Missing modes are not inferred from effective access.
  static String _permissions(FilesystemEntry entry) {
    final kind = switch (entry.kind) {
      FilesystemEntryKind.directory => 'd',
      FilesystemEntryKind.regularFile => '-',
      FilesystemEntryKind.symbolicLink => 'l',
      FilesystemEntryKind.other => '?',
    };

    final mode = entry.metadata.permissions?.posix_mode;

    if (mode == null) {
      return '$kind?????????';
    }

    final result = StringBuffer(kind);

    for (var index = 0; index < 3; index++) {
      final shift = 6 - index * 3;

      final readable = (mode & (4 << shift)) != 0;
      final writable = (mode & (2 << shift)) != 0;
      final executable = (mode & (1 << shift)) != 0;
      final special = (mode & (0x800 >> index)) != 0;

      result.write(readable ? 'r' : '-');
      result.write(writable ? 'w' : '-');

      if (special) {
        final marker = index == 2 ? 't' : 's';
        result.write(executable ? marker : marker.toUpperCase());
      } else {
        result.write(executable ? 'x' : '-');
      }
    }

    return result.toString();
  }

  /// Formats an observed modification timestamp in UTC.
  static String _modified_at(DateTime? value) {
    if (value == null) {
      return '?';
    }

    final date = value.toUtc();

    String pad(int part) => part.toString().padLeft(2, '0');

    return '${date.year.toString().padLeft(4, '0')}-'
        '${pad(date.month)}-${pad(date.day)} '
        '${pad(date.hour)}:${pad(date.minute)}';
  }
}
