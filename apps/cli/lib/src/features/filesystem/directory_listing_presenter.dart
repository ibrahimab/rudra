import 'package:rudra_sdk/rudra_sdk.dart';

import '../../core/rendering/theme.dart';

import 'presentation/widgets/directory_listing/directory_listing_view_model.dart';
import 'presentation/widgets/directory_inspection_issues/directory_inspection_issues_view_model.dart';

/// Prepares SDK directory observations for CLI presentation.
///
/// The presenter converts platform-independent filesystem
/// observations into immutable [DirectoryListingViewModel] data.
///
/// It owns presentation-specific transformations:
/// - Entry ordering for the requested layout.
/// - Directory-relative display names.
/// - Human-readable entry kinds and logical sizes.
/// - Observed POSIX permission formatting.
/// - UTC timestamp formatting.
/// - Semantic entry roles.
/// - Typed inspection diagnostic presentation.
///
/// The compact layout preserves SDK entry ordering.
/// The detailed layout sorts directories first, followed
/// by case-insensitive display-name order.
///
/// The presenter does not:
/// - Inspect or modify the filesystem.
/// - Construct navigation paths.
/// - Resolve symbolic links.
/// - Perform terminal I/O.
/// - Generate ANSI formatting.
/// - Manage sessions or authorize cleanup.
///
/// Example:
/// ```dart
/// const presenter = DirectoryListingPresenter();
///
/// final view_model = presenter.present(
///   listing,
///   layout: DirectoryListingLayout.detailed,
/// );
/// ```
final class DirectoryListingPresenter {
  /// Creates a stateless filesystem presenter.
  const DirectoryListingPresenter();

  /// Prepares an SDK listing for the requested presentation.
  ///
  /// [listing] must originate from the configured SDK.
  ///
  /// [layout] determines whether SDK entry ordering is
  /// preserved or detailed display ordering is applied.
  ///
  /// Successfully observed entries remain available when
  /// the listing is incomplete.
  ///
  /// All original target-native paths are preserved.
  ///
  /// The source listing and its collections are not mutated.
  DirectoryListingViewModel present(
    DirectoryListing listing, {
    DirectoryListingLayout layout = DirectoryListingLayout.detailed,
  }) {
    final entries = List<FilesystemEntry>.of(listing.entries);

    if (layout == DirectoryListingLayout.detailed) {
      entries.sort(
        (left, right) => _compare_entries(
          left,
          right,
          listing.directory,
        ),
      );
    }

    final rows = [
      for (final entry in entries)
        DirectoryEntryViewModel(
          path: entry.path.value,
          name: _display_name(entry, listing.directory),
          compact_type: entry.kind.name,
          type_label: _entry_type(entry.kind),
          logical_bytes: entry.metadata.logical_size_bytes?.toString() ?? '?',
          size_label: _display_size(entry),
          permissions: _permissions(entry),
          modified_utc: _modified_at(
            entry.metadata.modified_at,
          ),
          role: _entry_role(entry.kind),
        ),
    ];

    final issues = [
      for (final issue in listing.issues)
        DirectoryInspectionIssueViewModel(
          operation: issue.operation.name,
          code: issue.code.name,
          path: issue.path.value,
          message: issue.message,
        ),
    ];

    return DirectoryListingViewModel(
      layout: layout,
      directory_path: listing.directory.value,
      target_id: listing.target_id,
      is_complete: listing.is_complete,
      rows: rows,
      issues: issues,
    );
  }

  /// Orders directories before other observed entry kinds.
  ///
  /// Within each group, display names are compared without
  /// case sensitivity first.
  ///
  /// Original paths provide deterministic tie-breaking.
  ///
  /// This mirrors the established detailed listing ordering.
  static int _compare_entries(
    FilesystemEntry left,
    FilesystemEntry right,
    TargetPath directory,
  ) {
    final left_directory = left.kind == FilesystemEntryKind.directory;

    final right_directory = right.kind == FilesystemEntryKind.directory;

    if (left_directory != right_directory) {
      return left_directory ? -1 : 1;
    }

    final left_name = _entry_name(
      left,
      directory,
    ).toLowerCase();

    final right_name = _entry_name(
      right,
      directory,
    ).toLowerCase();

    final comparison = left_name.compareTo(right_name);

    return comparison != 0
        ? comparison
        : left.path.value.compareTo(right.path.value);
  }

  /// Derives the display name relative to the observed parent.
  ///
  /// Preserves the established directory-relative naming behavior
  /// of the detailed filesystem listing.
  ///
  /// Unexpected paths remain unchanged instead of being
  /// normalized or interpreted using host filesystem rules.
  ///
  /// The result is display-only and must never be used
  /// to construct a filesystem operation.
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

  /// Produces a friendly display name for an entry.
  ///
  /// Directories receive a trailing slash.
  /// Symbolic links are not followed or resolved.
  static String _display_name(
    FilesystemEntry entry,
    TargetPath directory,
  ) {
    final name = _entry_name(entry, directory);

    return entry.kind == FilesystemEntryKind.directory ? '$name/' : name;
  }

  /// Converts an observed entry kind into a readable label.
  static String _entry_type(FilesystemEntryKind kind) {
    return switch (kind) {
      FilesystemEntryKind.directory => 'Directory',
      FilesystemEntryKind.regularFile => 'File',
      FilesystemEntryKind.symbolicLink => 'Link',
      FilesystemEntryKind.other => 'Other',
    };
  }

  /// Associates an observed entry kind with a semantic role.
  ///
  /// The role identifies meaning, not terminal-specific colors.
  static TerminalRole _entry_role(FilesystemEntryKind kind) {
    return switch (kind) {
      FilesystemEntryKind.directory => TerminalRole.directory,
      FilesystemEntryKind.regularFile => TerminalRole.regular_file,
      FilesystemEntryKind.symbolicLink => TerminalRole.symbolic_link,
      FilesystemEntryKind.other => TerminalRole.other_entry,
    };
  }

  /// Formats an entry's observed logical size.
  ///
  /// Directory sizes are not recursively calculated.
  ///
  /// An unavailable size remains '?'.
  ///
  /// The unit conversion preserves the existing welcome
  /// listing's binary-unit formatting.
  ///
  /// This value does not represent recoverable disk space.
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

    const units = [
      'KiB',
      'MiB',
      'GiB',
      'TiB',
      'PiB',
      'EiB',
    ];

    var value = bytes.toDouble();
    var unit_index = -1;

    while (value >= 1024 && unit_index < units.length - 1) {
      value /= 1024;
      unit_index++;
    }

    return '${value.toStringAsFixed(1)} ${units[unit_index]}';
  }

  /// Formats observed POSIX permission bits.
  ///
  /// The leading character represents the entry kind.
  ///
  /// Missing permission information is displayed using
  /// question marks rather than inferred access rights.
  ///
  /// Special mode bits are represented using s/S or t/T.
  ///
  /// These are observations, not cleanup authorization.
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

        result.write(
          executable ? marker : marker.toUpperCase(),
        );
      } else {
        result.write(executable ? 'x' : '-');
      }
    }

    return result.toString();
  }

  /// Formats an observed modification timestamp in UTC.
  ///
  /// Missing timestamps remain '?'.
  ///
  /// The format matches the established detailed listing:
  /// YYYY-MM-DD HH:MM.
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
