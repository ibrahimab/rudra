import 'package:rudra_sdk/rudra_sdk.dart';

/// Immutable presentation state for the CLI filesystem explorer.
///
/// This is not a persistent Rudra inspection session.
///
/// The model stores observed directory data, selection state,
/// and a stack of previously visited directory paths.
///
/// Entries are ordered for presentation: directories first,
/// followed by case-insensitive path order.
///
/// No filesystem operations occur during construction.
final class ExplorerModel {
  /// Creates presentation state for an inspected directory.
  ///
  /// [root_directory] is the original exploration starting point.
  /// [listing] describes the currently displayed directory.
  /// [history] holds previously visited directories, beginning
  /// with the root when the explorer is inside a child directory.
  ///
  /// The selection starts at the first entry, or is null when
  /// the directory contains no successfully inspected entries.
  ///
  /// Throws [ArgumentError] when the navigation history does
  /// not agree with the configured exploration root.
  ///
  /// Example:
  /// ```dart
  /// final model = ExplorerModel(
  ///   root_directory: TargetPath('/workspace'),
  ///   listing: listing,
  /// );
  ///
  /// print(model.can_go_back);
  /// // false
  /// ```
  ExplorerModel({
    required this.root_directory,
    required this.listing,
    List<TargetPath> history = const [],
  })  : history = List<TargetPath>.unmodifiable(history),
        entries = List<FilesystemEntry>.unmodifiable(
          _sorted_entries(listing.entries),
        ),
        selected_index = listing.entries.isEmpty ? null : 0,
        is_closed = false {
    if (history.isEmpty && listing.directory.value != root_directory.value) {
      throw ArgumentError(
        'An explorer without history must display its root.',
      );
    }

    if (history.isNotEmpty && history.first.value != root_directory.value) {
      throw ArgumentError(
        'Navigation history must begin at the explorer root.',
      );
    }
  }

  /// Creates a new state while retaining immutable collections.
  ExplorerModel._({
    required this.root_directory,
    required this.listing,
    required this.history,
    required this.entries,
    required this.selected_index,
    required this.is_closed,
  });

  /// Original directory from which exploration began.
  final TargetPath root_directory;

  /// SDK observation of the currently displayed directory.
  ///
  /// An incomplete listing remains incomplete in the model.
  /// It must not be interpreted as an authoritative inventory.
  final DirectoryListing listing;

  /// Previously visited directory paths, oldest first.
  ///
  /// Paths retain their target-native spelling.
  /// The list is immutable.
  final List<TargetPath> history;

  /// Entries in stable presentation order.
  ///
  /// Only successfully inspected entries are included.
  /// This list is immutable and does not change [listing].
  final List<FilesystemEntry> entries;

  /// Index of the selected entry, or null for an empty listing.
  final int? selected_index;

  /// Whether the user has ended the current explorer interaction.
  ///
  /// Closing the explorer does not cancel, delete, or modify a
  /// persistent Rudra inspection session.
  final bool is_closed;

  /// Currently displayed target-native directory.
  TargetPath get current_directory => listing.directory;

  /// Whether a previous navigation location is available.
  bool get can_go_back => history.isNotEmpty;

  /// Whether the current SDK observation is incomplete.
  bool get is_incomplete => !listing.is_complete;

  /// Currently selected entry, if any.
  FilesystemEntry? get selected_entry {
    final index = selected_index;
    return index == null ? null : entries[index];
  }

  /// Returns a new model with the requested entry selected.
  ///
  /// Throws [RangeError] for an invalid index.
  /// Throws [StateError] if the explorer has been closed.
  ///
  /// Does not inspect filesystem entries.
  ExplorerModel with_selection(int index) {
    if (is_closed) {
      throw StateError('The explorer is closed.');
    }

    RangeError.checkValidIndex(index, entries, 'index');

    return ExplorerModel._(
      root_directory: root_directory,
      listing: listing,
      history: history,
      entries: entries,
      selected_index: index,
      is_closed: false,
    );
  }

  /// Returns a closed snapshot of the current presentation.
  ///
  /// Preserves the observed listing and navigation history.
  /// No filesystem operations or cleanup actions occur.
  ExplorerModel close() {
    return ExplorerModel._(
      root_directory: root_directory,
      listing: listing,
      history: history,
      entries: entries,
      selected_index: selected_index,
      is_closed: true,
    );
  }

  /// Sorts SDK observations without changing their paths.
  ///
  /// Sorting is a presentation concern. It does not establish
  /// filesystem identity, containment, or cleanup authorization.
  static List<FilesystemEntry> _sorted_entries(
    List<FilesystemEntry> source,
  ) {
    final sorted = List<FilesystemEntry>.of(source);

    sorted.sort((left, right) {
      final left_directory = left.kind == FilesystemEntryKind.directory;
      final right_directory = right.kind == FilesystemEntryKind.directory;

      if (left_directory != right_directory) {
        return left_directory ? -1 : 1;
      }

      final left_path = left.path.value;
      final right_path = right.path.value;

      final comparison =
          left_path.toLowerCase().compareTo(right_path.toLowerCase());

      return comparison != 0 ? comparison : left_path.compareTo(right_path);
    });

    return sorted;
  }
}
