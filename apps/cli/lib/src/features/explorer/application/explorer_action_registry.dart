import 'explorer_model.dart';

/// Represents an action invoked through an Explorer keyboard shortcut.
///
/// Each action defines a stable identifier, a keyboard shortcut, and
/// an operation executed against the current Explorer navigation model.
///
/// Implementations are registered through [ExplorerActionRegistry].
///
/// Example:
/// ```dart
/// final class InspectAction implements ExplorerAction {
///   const InspectAction();
///
///   @override
///   String get id => 'filesystem.inspect';
///
///   @override
///   String get shortcut => 'i';
///
///   @override
///   Future<void> execute(ExplorerModel model) async {
///     print(model.current_directory.value);
///   }
/// }
/// ```
abstract interface class ExplorerAction {
  /// Unique identifier for this action.
  ///
  /// Identifiers should be feature-qualified, such as
  /// `workflow.start` or `filesystem.inspect`.
  ///
  /// The registry rejects duplicate identifiers.
  String get id;

  /// Keyboard shortcut assigned to this action.
  ///
  /// Must contain exactly one printable ASCII character.
  /// Matching is case-insensitive.
  ///
  /// Duplicate and reserved shortcuts are rejected during
  /// registration.
  String get shortcut;

  /// Executes the action using the current Explorer snapshot.
  ///
  /// [model] contains the navigation state at the moment the
  /// keyboard shortcut was dispatched.
  ///
  /// Returns a future that completes when the action finishes.
  ///
  /// Exceptions from the underlying application operation
  /// propagate to the caller.
  Future<void> execute(ExplorerModel model);
}

/// Groups the Explorer actions contributed by a feature.
///
/// Each contribution has a unique identifier and an immutable,
/// ordered collection of actions.
///
/// The registry uses these contributions to validate action
/// identities and construct its keyboard shortcut index.
///
/// Example:
/// ```dart
/// final contribution = ExplorerFeatureContribution(
///   id: 'workflow',
///   actions: [start_action, stop_action],
/// );
/// ```
final class ExplorerFeatureContribution {
  /// Creates a feature contribution.
  ///
  /// [id] uniquely identifies the contributing feature within
  /// the Explorer registry.
  ///
  /// [actions] contains the feature's action implementations.
  /// The supplied collection is copied into an unmodifiable
  /// list, preserving its original order.
  ///
  /// An empty action collection is permitted.
  ExplorerFeatureContribution({
    required this.id,
    Iterable<ExplorerAction> actions = const [],
  }) : actions = List<ExplorerAction>.unmodifiable(actions);

  /// Unique identifier for the contributing feature.
  ///
  /// Examples include `workflow`, `filesystem`, and `explorer`.
  final String id;

  /// Immutable collection of actions registered by this feature.
  ///
  /// Actions retain the order supplied to the constructor.
  final List<ExplorerAction> actions;
}

/// Registry of keyboard actions contributed by Explorer features.
///
/// Construction validates all contributions and builds an immutable
/// shortcut-to-action lookup.
///
/// Feature identifiers and action identifiers must be unique across
/// the registration. Shortcuts are matched case-insensitively.
///
/// Invalid registrations fail during construction.
///
/// Example:
/// ```dart
/// final registry = ExplorerActionRegistry([
///   ExplorerFeatureContribution(
///     id: 'workflow',
///     actions: [start_action, stop_action],
///   ),
/// ]);
///
/// final action = registry.resolve('s');
///
/// if (action != null) {
///   await action.execute(explorer_model);
/// }
/// ```
final class ExplorerActionRegistry {
  /// Creates a registry from the supplied feature contributions.
  ///
  /// [features] contains the feature registrations to validate
  /// and index. Contributions are processed in iteration order.
  ///
  /// Throws [ArgumentError] when:
  /// - A feature identifier is empty or duplicated.
  /// - An action identifier is empty or duplicated.
  /// - A shortcut is not one printable ASCII character.
  /// - A shortcut conflicts with another action.
  /// - A shortcut is reserved by Explorer.
  ///
  /// The registry becomes available only after all contributions
  /// have been validated successfully.
  ExplorerActionRegistry(Iterable<ExplorerFeatureContribution> features)
    : _by_shortcut = _register(features);

  /// Immutable lookup of registered actions by keyboard shortcut.
  ///
  /// Shortcut keys are normalized to lowercase during registration.
  final Map<String, ExplorerAction> _by_shortcut;

  /// Validates contributions and builds the shortcut index.
  ///
  /// [features] contains the contributions to register.
  ///
  /// Returns an unmodifiable map indexed by normalized shortcuts.
  ///
  /// Throws [ArgumentError] for invalid or conflicting
  /// contributions.
  static Map<String, ExplorerAction> _register(
    Iterable<ExplorerFeatureContribution> features,
  ) {
    final feature_ids = <String>{};
    final action_ids = <String>{};
    final actions = <String, ExplorerAction>{};

    // Quit is handled by Explorer's interaction lifecycle.
    const reserved_shortcuts = {'q'};

    for (final feature in features) {
      if (feature.id.trim().isEmpty || !feature_ids.add(feature.id)) {
        throw ArgumentError('Invalid or duplicate Explorer feature ID.');
      }

      for (final action in feature.actions) {
        if (action.id.trim().isEmpty || !action_ids.add(action.id)) {
          throw ArgumentError('Invalid or duplicate Explorer action ID.');
        }

        final shortcut = action.shortcut;

        // Restrict shortcuts to printable ASCII characters.
        // ANSI control sequences and whitespace are handled
        // separately by the terminal input decoder.
        if (shortcut.length != 1 ||
            shortcut.codeUnitAt(0) < 0x21 ||
            shortcut.codeUnitAt(0) > 0x7E) {
          throw ArgumentError(
            'Explorer shortcuts must be one printable '
            'ASCII character.',
          );
        }

        // Normalize before collision detection so uppercase
        // and lowercase forms cannot identify different actions.
        final normalized = shortcut.toLowerCase();

        if (reserved_shortcuts.contains(normalized) ||
            actions.containsKey(normalized)) {
          throw ArgumentError(
            'Duplicate or reserved Explorer shortcut: $shortcut',
          );
        }

        actions[normalized] = action;
      }
    }

    // Expose only the fully validated action index.
    return Map<String, ExplorerAction>.unmodifiable(actions);
  }

  /// Resolves the action registered for a keyboard shortcut.
  ///
  /// [character] is the decoded character received from terminal
  /// input. Lookup is case-insensitive.
  ///
  /// Returns the registered [ExplorerAction], or null when no
  /// action is associated with the supplied character.
  ///
  /// Resolution does not execute the returned action.
  ///
  /// Example:
  /// ```dart
  /// final start_action = registry.resolve('S');
  /// final unknown_action = registry.resolve('?');
  /// ```
  ExplorerAction? resolve(String character) {
    return _by_shortcut[character.toLowerCase()];
  }
}
