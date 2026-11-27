import 'dart:async';

import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../core/rendering/theme.dart';
import '../../../core/rendering/widgets/terminal_widget.dart';

import '../presentation/explorer_view_model.dart';
import '../terminal/terminal_key.dart';

import 'explorer_action_registry.dart';
import 'explorer_model.dart';

/// Coordinates Explorer navigation, interaction state and registered actions.
///
/// Filesystem observations and verified application state come from the public
/// SDK. A feature action requires the latest verified state to match the
/// last successfully rendered presentation.
///
/// Example:
/// ```dart
/// final explorer = ExplorerController(
///   sdk: sdk,
///   starting_directory: TargetPath('/workspace'),
/// );
///
/// try {
///   await explorer.start();
///   await explorer.handle_key(TerminalSpecialKey.down);
///   final view = explorer.view_model(visible_row_limit: 12);
///   renderer.render(view);
///   explorer.acknowledge_render(view);
/// } finally {
///   await explorer.dispose();
/// }
/// ```
final class ExplorerController {
  /// Creates an inactive Explorer controller.
  ///
  /// [sdk] supplies authenticated application operations and observations.
  /// Its lifecycle remains owned by the enclosing product composition.
  ///
  /// [starting_directory] identifies the initial navigation root.
  /// Its target-native spelling is preserved.
  ///
  /// [action_registry] supplies registered feature actions and presentation.
  ///
  /// Construction does not establish observations or inspect directories.
  ExplorerController({
    required RudraSdk sdk,
    required TargetPath starting_directory,
    ExplorerActionRegistry? action_registry,
  }) : _sdk = sdk,
       _root_directory = starting_directory,
       _actions = action_registry ?? ExplorerActionRegistry(const []);

  /// Borrowed SDK for authenticated application operations and observations.
  final RudraSdk _sdk;

  /// Original navigation root, immutable for this controller.
  final TargetPath _root_directory;

  /// Validated, feature-owned action and presentation contributions.
  final ExplorerActionRegistry _actions;

  /// Default bindings for local navigation.
  late final Map<TerminalKey, FutureOr<ExplorerModel> Function()>
  _interaction_bindings = {
    TerminalSpecialKey.up: () => move_selection(-1),
    TerminalSpecialKey.down: () => move_selection(1),
    TerminalSpecialKey.enter: open_selected,
    TerminalSpecialKey.left: back,
    TerminalSpecialKey.backspace: back,
  };

  /// Latest application snapshot delivered by the SDK observation.
  RudraState? _latest_application_state;

  /// Application snapshot incorporated into the last successful render.
  ///
  /// Used to validate interaction consistency, not as execution authority.
  RudraState? _displayed_application_state;

  /// Prepared presentation awaiting successful rendering.
  ({ExplorerViewModel view, RudraState? state})? _prepared_frame;

  /// Owned subscription to authoritative application state.
  StreamSubscription<RudraState>? _state_subscription;

  /// Owned subscription to SDK synchronization availability.
  StreamSubscription<StateSynchronizationStatus>? _status_subscription;

  /// Publishes presentation invalidations to the terminal runner.
  final StreamController<void> _presentation_changes =
      StreamController<void>.broadcast(sync: true);

  /// Whether the controller's application observation has terminated.
  bool _observation_ended = false;

  /// Retained disposal operation shared by repeated calls.
  Future<void>? _disposal;

  /// Whether feature dispatch is waiting for state newer than its input.
  bool _awaiting_observation = false;

  /// Diagnostic presented following a rejected interaction.
  String? _interaction_notice;

  /// Observes changes requiring a new presentation.
  ///
  /// Notifications carry no domain state. Consumers obtain the current
  /// presentation through [view_model].
  Stream<void> get presentation_changes => _presentation_changes.stream;

  /// Latest verified state while authoritative synchronization is available.
  ///
  /// Returns null when observation is unavailable. Verified workflow
  /// absence remains represented by a non-null [RudraState].
  RudraState? get _verified_application_state {
    if (_observation_ended ||
        !_sdk.is_connected ||
        _sdk.synchronization_status !=
            StateSynchronizationStatus.synchronized) {
      return null;
    }

    return _latest_application_state;
  }

  /// Latest committed Explorer navigation state.
  ExplorerModel? _model;

  /// Prevents overlapping initialization, inspections and feature actions.
  bool _is_busy = false;

  /// First entry shown in the current directory viewport.
  int _first_visible_index = 0;

  /// Current navigation snapshot, or null before the initial inspection.
  ExplorerModel? get model => _model;

  /// Whether the current interaction has ended.
  bool get is_closed => _model?.is_closed ?? false;

  /// Whether startup, an inspection or a feature action is in progress.
  bool get is_busy => _is_busy;

  /// Whether any visited directory returned an incomplete SDK observation.
  bool get encountered_incomplete => _encountered_incomplete;
  bool _encountered_incomplete = false;

  /// Returns whether [key] requests termination, even during an operation.
  static bool is_exit_key(TerminalKey key) =>
      key == TerminalSpecialKey.interrupt ||
      key == const TerminalCharacterKey('q') ||
      key == const TerminalCharacterKey('Q');

  /// Handles a decoded terminal [key] and reports whether to redraw.
  ///
  /// Registered actions require synchronized application state matching
  /// the last successfully displayed snapshot.
  ///
  /// An interaction against outdated presentation is rejected locally
  /// without submitting an application operation.
  ///
  /// Throws [StateError] outside an active interaction or while another
  /// operation is executing. Application and inspection failures propagate.
  FutureOr<bool> handle_key(TerminalKey key) {
    final current = _require_active();
    if (is_exit_key(key)) {
      quit();
      return false;
    }

    final interaction = _interaction_bindings[key];

    if (interaction != null) {
      final next = interaction();
      if (next is Future<ExplorerModel>) {
        return next.then((model) => !identical(current, model));
      }
      return !identical(current, next);
    }

    final action = _actions.resolve(key);
    if (action == null) return false;

    final state = _verified_application_state;

    if (state == null) {
      return true;
    }

    // A newer observation invalidates the user's interaction context.
    if (!identical(state, _displayed_application_state)) {
      _interaction_notice = 'State changed. Please review and try again.';
      return true;
    }

    if (_awaiting_observation) return true;

    return _execute(action, current, state);
  }

  /// Dispatches [action] with the admitted navigation and application state.
  Future<bool> _execute(
    ExplorerAction action,
    ExplorerModel model,
    RudraState state,
  ) async {
    _is_busy = true;
    _awaiting_observation = true;
    try {
      await action.execute(model, state);
      return true;
    } catch (_) {
      _awaiting_observation = false;
      rethrow;
    } finally {
      _is_busy = false;
    }
  }

  /// Establishes application observation and awaits its initial state.
  ///
  /// Returns after the SDK delivers a verified application snapshot.
  /// Initial synchronization failures propagate to the caller.
  Future<void> _start_observation() async {
    final initial = Completer<void>();

    void observation_failed(Object error, StackTrace stack_trace) {
      if (_disposal != null || _observation_ended) return;

      _observation_ended = true;
      _latest_application_state = null;

      if (!initial.isCompleted) {
        initial.completeError(error, stack_trace);
      }

      _invalidate_presentation();
    }

    _status_subscription = _sdk.observe_synchronization_status().listen(
      (_) => _invalidate_presentation(),
      onError: observation_failed,
    );

    _state_subscription = _sdk.observe_state().listen(
      (state) {
        if (_disposal != null || _observation_ended) return;

        // A newer verified snapshot may arrive before the action returns.
        if (!identical(state, _latest_application_state)) {
          _awaiting_observation = false;
        }
        _latest_application_state = state;

        if (!initial.isCompleted) {
          initial.complete();
        }

        _invalidate_presentation();
      },
      onError: observation_failed,
      onDone: () {
        observation_failed(
          StateError('Application state observation terminated.'),
          StackTrace.current,
        );
      },
    );

    await initial.future;
  }

  /// Reports that the retained presentation requires updating.
  ///
  /// Closed interactions and disposed controllers publish no notifications.
  void _invalidate_presentation() {
    if (_disposal != null || is_closed) return;

    _presentation_changes.add(null);
  }

  /// Prepares an immutable presentation of the current interaction.
  ///
  /// [visible_row_limit] supplies the available directory viewport height.
  ///
  /// Returns a presentation containing verified feature projections or
  /// synchronization-unavailable diagnostics.
  ///
  /// The prepared application snapshot becomes the displayed snapshot
  /// only when [acknowledge_render] confirms successful rendering.
  ///
  /// Throws [RangeError] for a negative limit and [StateError] when
  /// the interaction is inactive or busy.
  ExplorerViewModel view_model({required int visible_row_limit}) {
    final current = _require_active();
    final state = _verified_application_state;
    final notice = _interaction_notice;

    final contributions = <ExplorerFeaturePresentation>[
      if (notice != null)
        (
          status: TerminalLine(notice, role: TerminalRole.warning),
          instruction: null,
        ),
      if (state == null)
        (
          status: const TerminalLine(
            'Application state: UNAVAILABLE',
            role: TerminalRole.warning,
          ),
          instruction: null,
        )
      else ...[
        if (_awaiting_observation)
          (
            status: const TerminalLine(
              'Waiting for updated application state.',
              role: TerminalRole.warning,
            ),
            instruction: null,
          ),
        for (final presentation in _actions.features.map(
          (feature) => feature.present(state),
        ))
          (
            status: presentation.status,
            instruction: _awaiting_observation
                ? null
                : presentation.instruction,
          ),
      ],
    ];

    final view = ExplorerViewModel.from_navigation(
      explorer: current,
      contributions: contributions,
      visible_row_limit: visible_row_limit,
      first_visible_index: _first_visible_index,
    );

    _prepared_frame = (view: view, state: state);

    return view;
  }

  /// Confirms successful rendering of the prepared [view].
  ///
  /// Advances the displayed application snapshot to the exact state
  /// incorporated into the supplied presentation.
  ///
  /// Throws [StateError] when the supplied presentation does not match
  /// the currently prepared frame.
  void acknowledge_render(ExplorerViewModel view) {
    final prepared = _prepared_frame;

    if (prepared == null || !identical(prepared.view, view)) {
      throw StateError(
        'Cannot acknowledge an unprepared Explorer presentation.',
      );
    }

    _displayed_application_state = prepared.state;
    _first_visible_index = view.directory.first_visible_index;
    _prepared_frame = null;
    _interaction_notice = null;
  }

  /// Establishes application observation and inspects the navigation root.
  ///
  /// Returns the initial immutable navigation snapshot after verified
  /// application state and the directory listing become available.
  ///
  /// Throws [StateError] when already started, busy or disposed.
  /// Synchronization and inspection failures propagate after observation
  /// resources have been released.
  Future<ExplorerModel> start() async {
    if (_disposal != null || _is_busy || _model != null) {
      throw StateError('The explorer cannot be started.');
    }

    _is_busy = true;

    try {
      await _start_observation();

      if (_verified_application_state == null) {
        throw StateError('Initial application state is unavailable.');
      }

      // Directory loading owns its existing operation guard.
      _is_busy = false;

      final model = await _load(directory: _root_directory, history: const []);

      if (_verified_application_state == null) {
        throw StateError(
          'Application synchronization was lost during startup.',
        );
      }

      return model;
    } catch (_) {
      _is_busy = false;
      await dispose();
      rethrow;
    } finally {
      _is_busy = false;
    }
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
  /// When synchronization is unavailable, returns the retained listing.
  /// Unexpected SDK failures leave the previous state intact.
  ///
  /// The directory may change after inspection. This method
  /// makes no cleanup authorization or containment guarantee.
  FutureOr<ExplorerModel> open_selected() {
    final current = _require_active();
    final selected = current.selected_entry;

    if (selected == null ||
        selected.kind != FilesystemEntryKind.directory ||
        _verified_application_state == null) {
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
  /// When synchronization is unavailable, returns the retained listing.
  ///
  /// The previous directory is re-inspected through the SDK
  /// rather than restored from a potentially stale listing.
  ///
  /// If the SDK throws unexpectedly, the current navigation
  /// state and history remain unchanged.
  FutureOr<ExplorerModel> back() {
    final current = _require_active();

    if (!current.can_go_back || _verified_application_state == null) {
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
    final current = _model;
    _is_busy = true;

    try {
      final listing = await _sdk.filesystem.list(directory: directory);
      if (current != null && _verified_application_state == null)
        return current;

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
    } catch (_) {
      // A connection lost during navigation leaves the displayed listing intact.
      if (current != null && _verified_application_state == null)
        return current;
      rethrow;
    } finally {
      _is_busy = false;
    }
  }

  /// Requires a started, active Explorer with no operation in progress.
  ///
  /// Centralizes lifecycle validation for navigation operations.
  ExplorerModel _require_active() {
    if (_disposal != null) {
      throw StateError('The explorer has been disposed.');
    }

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

  /// Releases the controller's observation and presentation resources.
  ///
  /// Closes the retained navigation interaction, if one exists.
  /// Cancellation failures propagate after cancellation has been
  /// attempted for both owned SDK subscriptions.
  ///
  /// Repeated disposal has no additional effect.
  ///
  /// The caller must settle admitted interactions before disposal.
  /// The borrowed SDK remains owned by product composition.
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    final current = _model;

    if (current != null && !current.is_closed) {
      _model = current.close();
    }

    _latest_application_state = null;
    _displayed_application_state = null;
    _prepared_frame = null;

    try {
      await Future.wait<void>([
        if (_state_subscription case final subscription?)
          Future<void>.sync(subscription.cancel),
        if (_status_subscription case final subscription?)
          Future<void>.sync(subscription.cancel),
      ]);
    } finally {
      await _presentation_changes.close();
    }
  }
}
