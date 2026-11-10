import 'package:rudra_sdk/rudra_sdk.dart';

import 'explorer_model.dart';

/// Coordinates read-only filesystem navigation for the CLI.
///
/// All filesystem observations are requested through the
/// public [RudraSdk.filesystem] application service.
///
/// The controller owns transient navigation state only.
///
/// It does not:
/// - Access TargetInspector directly.
/// - Resolve symbolic links.
/// - Construct child paths from terminal input.
/// - Create or modify persistent inspection sessions.
/// - Mark cleanup candidates.
/// - Authorize or execute cleanup.
///
/// Only one directory inspection may run at a time.
///
/// Example:
/// ```dart
/// final explorer = ExplorerController(
///   sdk: sdk,
///   starting_directory: TargetPath('/workspace'),
/// );
///
/// await explorer.start();
/// explorer.move_selection(1);
/// await explorer.open_selected();
/// await explorer.back();
/// explorer.quit();
/// ```
final class ExplorerController {
  /// Creates a controller bound to a configured SDK target.
  ///
  /// [starting_directory] is supplied by application composition.
  /// Its target-native spelling is preserved.
  ///
  /// Construction performs no filesystem inspection.
  ExplorerController({
    required RudraSdk sdk,
    required TargetPath starting_directory,
  })  : _sdk = sdk,
        _root_directory = starting_directory;

  /// SDK used for all read-only filesystem observations.
  final RudraSdk _sdk;

  /// Original navigation root, immutable for this controller.
  final TargetPath _root_directory;

  /// Latest committed explorer presentation state.
  ExplorerModel? _model;

  /// Prevents overlapping asynchronous inspection operations.
  bool _is_loading = false;

  /// Current presentation state, or null before initialization.
  ExplorerModel? get model => _model;

  /// Whether a filesystem inspection is in progress.
  bool get is_loading => _is_loading;

  /// Starts exploration at the configured root.
  ///
  /// Calls the SDK exactly once for the initial directory.
  ///
  /// Returns an immutable [ExplorerModel] containing the SDK
  /// listing, including any reported partial observations.
  ///
  /// Throws [StateError] if already started or currently loading.
  /// Unexpected SDK errors propagate without committing state.
  ///
  /// Starting does not create a persistent Rudra session.
  Future<ExplorerModel> start() async {
    if (_model != null) {
      throw StateError('The explorer has already started.');
    }

    return _load(
      directory: _root_directory,
      history: const [],
    );
  }

  /// Moves selection by [offset] entries.
  ///
  /// Positive offsets move forward; negative offsets move back.
  /// The selection is clamped to the available entry range.
  ///
  /// Empty directories retain a null selection.
  ///
  /// Throws [StateError] before startup, after quit, or while
  /// a directory inspection is running.
  ExplorerModel move_selection(int offset) {
    final current = _require_active();

    if (current.entries.isEmpty) {
      return current;
    }

    final previous_index = current.selected_index!;

    final next_index =
        (previous_index + offset).clamp(0, current.entries.length - 1).toInt();

    final next = current.with_selection(next_index);
    _model = next;

    return next;
  }

  /// Opens the currently selected directory.
  ///
  /// Only an entry reported by the current SDK listing and
  /// classified as a directory can be opened.
  ///
  /// Selecting a regular file, symbolic link, another entry
  /// type, or an empty listing does not navigate.
  ///
  /// On successful SDK return, the current directory is added
  /// to the history and the new listing is displayed.
  ///
  /// An incomplete listing is retained with its issues.
  /// Unexpected SDK failures leave the previous state intact.
  ///
  /// The directory may change after inspection. This method
  /// makes no cleanup authorization or containment guarantee.
  Future<ExplorerModel> open_selected() async {
    final current = _require_active();
    final selected = current.selected_entry;

    if (selected == null || selected.kind != FilesystemEntryKind.directory) {
      return current;
    }

    return _load(
      directory: selected.path,
      history: [
        ...current.history,
        current.current_directory,
      ],
    );
  }

  /// Returns to the previously visited directory.
  ///
  /// At the exploration root, this is a no-op.
  ///
  /// The previous directory is re-inspected through the SDK
  /// rather than restored from a potentially stale listing.
  ///
  /// If the SDK throws unexpectedly, the current navigation
  /// state and history remain unchanged.
  Future<ExplorerModel> back() async {
    final current = _require_active();

    if (!current.can_go_back) {
      return current;
    }

    final previous_directory = current.history.last;
    final previous_history = current.history.sublist(
      0,
      current.history.length - 1,
    );

    return _load(
      directory: previous_directory,
      history: previous_history,
    );
  }

  /// Ends the current in-memory explorer interaction.
  ///
  /// Does not delete, cancel, or persist a Rudra session.
  /// No filesystem operations are performed.
  ///
  /// Throws [StateError] before startup, after quit, or
  /// during an active inspection.
  ExplorerModel quit() {
    final current = _require_active();
    final closed = current.close();

    _model = closed;
    return closed;
  }

  /// Requests one directory listing and commits its result.
  ///
  /// [history] is the navigation history for the requested
  /// destination. It is committed only after the SDK returns.
  ///
  /// A failed SDK request never changes the current model.
  ///
  /// Partial SDK results are kept explicitly incomplete.
  Future<ExplorerModel> _load({
    required TargetPath directory,
    required List<TargetPath> history,
  }) async {
    if (_is_loading) {
      throw StateError(
        'A directory inspection is already in progress.',
      );
    }

    _is_loading = true;

    try {
      final listing = await _sdk.filesystem.list(
        directory: directory,
      );

      // Reject inconsistent SDK observations instead of
      // silently displaying another target or directory.
      if (listing.target_id != _sdk.target_id ||
          listing.directory.value != directory.value) {
        throw StateError(
          'SDK returned a listing for an unexpected directory.',
        );
      }

      final next = ExplorerModel(
        root_directory: _root_directory,
        listing: listing,
        history: history,
      );

      _model = next;
      return next;
    } finally {
      _is_loading = false;
    }
  }

  /// Requires a started, active, non-loading explorer.
  ///
  /// Centralizes lifecycle validation for navigation operations.
  ExplorerModel _require_active() {
    if (_is_loading) {
      throw StateError(
        'Navigation is unavailable during inspection.',
      );
    }

    final current = _model;

    if (current == null) {
      throw StateError('The explorer has not started.');
    }

    if (current.is_closed) {
      throw StateError('The explorer is closed.');
    }

    return current;
  }
}
