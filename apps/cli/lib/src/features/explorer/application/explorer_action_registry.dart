import 'explorer_model.dart';

/// A feature-owned status contribution for Explorer.
///
/// Status values are presentation data only. They must not
/// be interpreted as authorization to perform an operation.
///
/// The feature producing a status is responsible for
/// projecting its authoritative application snapshot.
///
/// Explorer is responsible only for displaying the result.
final class ExplorerStatus {
  /// Creates immutable status presentation data.
  ///
  /// [text] is the complete human-readable contribution.
  ///
  /// [emphasized] requests the existing heading style.
  /// It does not indicate that an action is authorized.
  const ExplorerStatus(this.text, {this.emphasized = false});

  /// Human-readable text supplied by the owning feature.
  final String text;

  /// Whether presentation should emphasize this status.
  final bool emphasized;
}

/// Describes one explicitly invoked Explorer action.
///
/// An action owns its identity, keyboard binding,
/// availability rule, and application operation.
///
/// The registry does not inspect action-specific state or
/// know which application capability the action represents.
///
/// [is_available] must be synchronous and side-effect-free.
/// It may inspect a feature-owned in-memory snapshot.
///
/// [execute] may perform application operations. It is
/// invoked only when a registered shortcut is explicitly
/// received and the action is available.
///
/// Availability is a UI and dispatch decision, not a
/// substitute for backend authorization or revalidation.
///
/// Implementations must independently enforce their
/// application invariants before performing side effects.
///
/// Example:
/// ```dart
/// final action = ExplorerAction(
///   id: 'example.inspect',
///   shortcut: 'i',
///   hint: 'Inspect',
///   is_available: (_) => true,
///   execute: (model) async {
///     print(model.current_directory.value);
///   },
/// );
/// ```
final class ExplorerAction {
  /// Creates an action contribution.
  ///
  /// Construction does not execute the action or evaluate
  /// its availability rule.
  ///
  /// The registry validates IDs, shortcuts, and collisions
  /// when contributions are assembled.
  const ExplorerAction({
    required this.id,
    required this.shortcut,
    required this.hint,
    required this.is_available,
    required this.execute,
  });

  /// Globally unique action identifier within Explorer.
  ///
  /// Prefer feature-qualified IDs such as `workflow.start`.
  /// IDs must remain stable across refactoring.
  final String id;

  /// Printable ASCII shortcut for the action.
  ///
  /// Registration is case-insensitive. The original value
  /// is retained for presentation.
  final String shortcut;

  /// Short label displayed alongside the shortcut.
  ///
  /// Example: `Start Workflow`.
  final String hint;

  /// Determines whether the action can currently be offered.
  ///
  /// This callback must not submit commands, mutate state,
  /// or perform filesystem or persistence operations.
  final bool Function(ExplorerModel) is_available;

  /// Performs the action against the current Explorer snapshot.
  ///
  /// The callback is awaited by the generic runner.
  /// Failures propagate through terminal restoration.
  ///
  /// The feature owns any required application state updates.
  final Future<void> Function(ExplorerModel) execute;
}

/// Groups the Explorer contributions owned by one feature.
///
/// Features may contribute actions, a status projection,
/// or both.
///
/// This contract separates feature implementation from
/// frontend registration. A new feature can contribute
/// behavior without modifying existing Explorer actions.
///
/// The supplied action collection is copied and made
/// unmodifiable to prevent registration changes after
/// the application has been composed.
///
/// Example:
/// ```dart
/// final contribution = ExplorerFeatureContribution(
///   id: 'example',
///   actions: [example_action],
///   status: () => const ExplorerStatus('Example ready'),
/// );
/// ```
final class ExplorerFeatureContribution {
  /// Creates a feature contribution.
  ///
  /// [id] identifies the contributing feature.
  ///
  /// [actions] contains the feature's registered actions,
  /// in their desired presentation order.
  ///
  /// [status] is an optional synchronous projection of
  /// feature-owned presentation state.
  ///
  /// Construction never invokes supplied callbacks.
  ExplorerFeatureContribution({
    required this.id,
    Iterable<ExplorerAction> actions = const [],
    this.status,
  }) : actions = List<ExplorerAction>.unmodifiable(actions);

  /// Unique feature identifier within the Explorer.
  final String id;

  /// Immutable, ordered actions owned by this feature.
  final List<ExplorerAction> actions;

  /// Optional read-only feature status projection.
  ///
  /// The callback must not perform application operations.
  final ExplorerStatus Function()? status;
}

/// Validates and exposes registered Explorer feature actions.
///
/// The registry has three responsibilities:
/// - Reject invalid or conflicting contributions.
/// - Resolve currently available printable-key actions.
/// - Expose ordered presentation contributions.
///
/// It deliberately does not:
/// - Construct SDK services or persistence adapters.
/// - Know about workflow events or states.
/// - Execute actions during registration.
/// - Own terminal input or lifecycle.
/// - Perform backend authorization.
/// - Modify navigation or filesystem state.
///
/// All contributions are supplied explicitly by composition.
/// Registration finishes before the interaction begins.
///
/// Adding a new action requires a new contribution and
/// composition registration, not registry modifications.
///
/// Example:
/// ```dart
/// final registry = ExplorerActionRegistry([
///   ExplorerFeatureContribution(
///     id: 'example',
///     actions: [example_action],
///   ),
/// ]);
///
/// final action = registry.resolve('i', explorer_model);
///
/// if (action != null) {
///   await action.execute(explorer_model);
/// }
/// ```
final class ExplorerActionRegistry {
  /// Constructs an immutable Explorer action registration.
  ///
  /// Rejects:
  /// - Empty or duplicate feature identifiers.
  /// - Empty or duplicate action identifiers.
  /// - Empty action labels.
  /// - Non-ASCII or multi-character shortcuts.
  /// - Duplicate shortcuts, ignoring character case.
  /// - Shortcuts reserved for built-in Explorer behavior.
  ///
  /// Validation occurs before any interaction starts.
  /// No application action is executed by construction.
  ExplorerActionRegistry(Iterable<ExplorerFeatureContribution> features)
    : _features = List<ExplorerFeatureContribution>.unmodifiable(features) {
    final feature_ids = <String>{};
    final action_ids = <String>{};

    // Quit is a built-in lifecycle operation.
    // Navigation uses non-printable keys and therefore
    // cannot collide with printable action bindings.
    final shortcuts = <String>{'q'};

    for (final feature in _features) {
      if (feature.id.trim().isEmpty || !feature_ids.add(feature.id)) {
        throw ArgumentError('Invalid or duplicate Explorer feature ID.');
      }

      for (final action in feature.actions) {
        if (action.id.trim().isEmpty || !action_ids.add(action.id)) {
          throw ArgumentError('Invalid or duplicate Explorer action ID.');
        }

        if (action.hint.trim().isEmpty) {
          throw ArgumentError('Explorer action hints cannot be empty.');
        }

        final shortcut = action.shortcut;

        // Only visible printable ASCII characters are
        // supported as action shortcuts in this version.
        if (shortcut.length != 1 ||
            shortcut.codeUnitAt(0) < 0x21 ||
            shortcut.codeUnitAt(0) > 0x7E) {
          throw ArgumentError(
            'Explorer shortcuts must be one printable '
            'ASCII character.',
          );
        }

        final normalized = shortcut.toLowerCase();

        if (!shortcuts.add(normalized)) {
          throw ArgumentError(
            'Duplicate or reserved Explorer shortcut: $shortcut',
          );
        }

        _by_shortcut[normalized] = action;
      }
    }
  }

  /// Ordered feature registrations.
  final List<ExplorerFeatureContribution> _features;

  /// Indexed actions using normalized printable characters.
  ///
  /// Populated only during registry construction.
  final Map<String, ExplorerAction> _by_shortcut = {};

  /// Resolves an action for a user-entered character.
  ///
  /// Matching is case-insensitive.
  ///
  /// Returns null when:
  /// - No action owns the supplied shortcut.
  /// - The registered action is currently unavailable.
  ///
  /// Availability is checked against [model] at dispatch
  /// time, not cached during registration.
  ///
  /// This method never executes the resolved action.
  ExplorerAction? resolve(String character, ExplorerModel model) {
    final action = _by_shortcut[character.toLowerCase()];

    if (action == null || !action.is_available(model)) {
      return null;
    }

    return action;
  }

  /// Returns hints for currently available actions.
  ///
  /// Hints retain feature and action registration order.
  /// Unavailable actions are omitted.
  ///
  /// The result is unmodifiable and describes the
  /// availability snapshot observed at this invocation.
  ///
  /// The generic presenter decides how hints are displayed.
  List<String> available_hints(ExplorerModel model) {
    return List<String>.unmodifiable([
      for (final feature in _features)
        for (final action in feature.actions)
          if (action.is_available(model))
            '${action.shortcut.toUpperCase()} ${action.hint}',
    ]);
  }

  /// Builds ordered feature status contributions.
  ///
  /// Each callback reads the owning feature's current
  /// interaction-local presentation state.
  ///
  /// Status is never treated as authorization, and this
  /// method must not initiate application operations.
  ///
  /// A callback error propagates to the caller rather
  /// than being silently converted into a valid status.
  List<ExplorerStatus> statuses() {
    return List<ExplorerStatus>.unmodifiable([
      for (final feature in _features)
        if (feature.status != null) feature.status!(),
    ]);
  }
}
