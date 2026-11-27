import 'dart:async';

import 'package:rudra_sdk/rudra_sdk.dart';

import '../presentation/explorer_view_model.dart';
import '../terminal/terminal_key.dart';

import 'explorer_action_registry.dart';
import 'explorer_model.dart';

/// Coordinates Explorer navigation, interaction state and registered actions.
///
/// Filesystem observations and verified application state come from the public
/// SDK. Actions and presentation use the same retained application snapshot.
///
/// Example:
/// ```dart
/// final explorer = await ExplorerController.create(
///   sdk: sdk,
///   starting_directory: TargetPath('/workspace'),
/// );
///
/// await explorer.start();
/// await explorer.handle_key(TerminalSpecialKey.down);
/// final view = explorer.view_model(visible_row_limit: 12);
/// explorer.quit();
/// ```
final class ExplorerController {
  /// Loads verified application state and creates a controller.
  ///
  /// [sdk] is the invocation's authenticated SDK, borrowed for application I/O.
  /// [starting_directory] is supplied by application composition.
  /// Its target-native spelling is preserved.
  /// [action_registry] supplies feature actions and their presentation.
  ///
  /// Returns an initialized controller ready for [start]. SDK state-read
  /// failures propagate before any directory inspection or terminal setup.
  static Future<ExplorerController> create({
    required RudraSdk sdk,
    required TargetPath starting_directory,
    ExplorerActionRegistry? action_registry,
  }) async {
    final state = await sdk.read_state();
    return ExplorerController._(
      sdk,
      starting_directory,
      action_registry ?? ExplorerActionRegistry(const []),
      state,
    );
  }

  ExplorerController._(
    this._sdk,
    this._root_directory,
    this._actions,
    this._application_state,
  );

  /// Borrowed SDK for filesystem observations and state reads.
  final RudraSdk _sdk;

  /// Original navigation root, immutable for this controller.
  final TargetPath _root_directory;

  /// Validated, feature-owned action and presentation contributions.
  final ExplorerActionRegistry _actions;

  /// Default bindings for local navigation and interaction lifecycle.
  late final Map<TerminalKey, FutureOr<ExplorerModel> Function()>
  _interaction_bindings = {
    TerminalSpecialKey.up: () => move_selection(-1),
    TerminalSpecialKey.down: () => move_selection(1),
    TerminalSpecialKey.enter: open_selected,
    TerminalSpecialKey.left: back,
    TerminalSpecialKey.backspace: back,
    const TerminalCharacterKey('q'): quit,
    const TerminalCharacterKey('Q'): quit,
    TerminalSpecialKey.interrupt: quit,
  };

  /// Last verified application snapshot, shared by presentation and dispatch.
  RudraState _application_state;

  /// Latest committed Explorer navigation state.
  ExplorerModel? _model;

  /// Prevents overlapping inspections, actions and post-action state reads.
  bool _is_busy = false;

  /// First entry shown in the current directory viewport.
  int _first_visible_index = 0;

  /// Current navigation snapshot, or null before the initial inspection.
  ExplorerModel? get model => _model;

  /// Whether the current interaction has ended.
  bool get is_closed => _model?.is_closed ?? false;

  /// Whether an inspection or feature action is in progress.
  bool get is_busy => _is_busy;

  /// Whether any visited directory returned an incomplete SDK observation.
  bool get encountered_incomplete => _encountered_incomplete;
  bool _encountered_incomplete = false;

  /// Handles a decoded terminal [key] and reports whether to redraw.
  ///
  /// Waits for a registered action and its verified state refresh before
  /// allowing another input. Unknown keys and Quit request no redraw.
  /// Throws [StateError] outside an active interaction or during another
  /// operation. Action, inspection and state-read errors propagate.
  Future<bool> handle_key(TerminalKey key) async {
    final current = _require_active();
    final interaction = _interaction_bindings[key];
    if (interaction != null) {
      final next = await interaction();
      return !next.is_closed && !identical(current, next);
    }

    final action = _actions.resolve(key);
    if (action == null) return false;

    _is_busy = true;
    try {
      await action.execute(current, _application_state);
      _application_state = await _sdk.read_state();
    } finally {
      _is_busy = false;
    }

    return true;
  }

  /// Returns an immutable presentation of the current interaction.
  ///
  /// [visible_row_limit] is the number of rows available for directory entries.
  /// Throws [RangeError] for a negative limit and [StateError] if the Explorer
  /// is inactive or busy. The view model adjusts scrolling to keep the selected
  /// entry visible within the supplied limit.
  ExplorerViewModel view_model({required int visible_row_limit}) {
    final view = ExplorerViewModel.from_navigation(
      explorer: _require_active(),
      contributions: _actions.features.map(
        (feature) => feature.present(_application_state),
      ),
      visible_row_limit: visible_row_limit,
      first_visible_index: _first_visible_index,
    );
    _first_visible_index = view.directory.first_visible_index;
    return view;
  }

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

    return _load(directory: _root_directory, history: const []);
  }

  /// Moves selection by [offset] entries.
  ///
  /// Positive offsets move forward; negative offsets move back.
  /// The selection is clamped to the available entry range.
  ///
  /// Empty directories retain a null selection.
  ///
  /// Throws [StateError] before startup, after quit, or while
  /// another operation is running.
  ExplorerModel move_selection(int offset) {
    final current = _require_active();

    if (current.entries.isEmpty) {
      return current;
    }

    final previous_index = current.selected_index!;

    final next_index = (previous_index + offset)
        .clamp(0, current.entries.length - 1)
        .toInt();

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
      history: [...current.history, current.current_directory],
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

    return _load(directory: previous_directory, history: previous_history);
  }

  /// Ends the current in-memory explorer interaction.
  ///
  /// Does not delete, cancel, or persist a Rudra session.
  /// No filesystem operations are performed.
  ///
  /// Throws [StateError] before startup, after quit, or
  /// during an active operation.
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
    if (_is_busy) {
      throw StateError('An Explorer operation is already in progress.');
    }

    _is_busy = true;

    try {
      final listing = await _sdk.filesystem.list(directory: directory);

      // The initial inspection establishes the navigation target. Later
      // observations must match it and the requested directory.
      final current_target = _model?.listing.target_id;
      if ((current_target != null && listing.target_id != current_target) ||
          listing.directory.value != directory.value) {
        throw StateError('SDK returned a listing for an unexpected directory.');
      }

      final next = ExplorerModel(
        root_directory: _root_directory,
        listing: listing,
        history: history,
      );

      if (_model?.current_directory.value != next.current_directory.value) {
        _first_visible_index = 0;
      }
      _encountered_incomplete = _encountered_incomplete || next.is_incomplete;
      _model = next;
      return next;
    } finally {
      _is_busy = false;
    }
  }

  /// Requires a started, active Explorer with no operation in progress.
  ///
  /// Centralizes lifecycle validation for navigation operations.
  ExplorerModel _require_active() {
    if (_is_busy) {
      throw StateError('An Explorer operation is already in progress.');
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
