import '../rudra_state.dart';

/// One verified application-state publication within a generation.
///
/// Publication metadata establishes delivery ordering independently
/// of domain workflow identities, versions and journal sequences.
///
/// Example:
/// ```dart
/// final publication = StatePublicationSnapshot(
///   generation: 'host-generation',
///   revision: 1,
///   state: verified_state,
/// );
///
/// print(publication.state.workflows.current_workflow);
/// ```
final class StatePublicationSnapshot {
  /// Associates verified [state] with its publication position.
  ///
  /// [generation] identifies the originating publication lifecycle.
  /// [revision] is its positive, monotonically increasing ordinal.
  ///
  /// Throws [ArgumentError] for a blank generation or non-positive
  /// revision.
  StatePublicationSnapshot({
    required this.generation,
    required this.revision,
    required this.state,
  }) {
    if (generation.trim().isEmpty) {
      throw ArgumentError.value(generation, 'generation');
    }

    if (revision <= 0) {
      throw ArgumentError.value(revision, 'revision');
    }
  }

  /// Opaque identity of the originating publication lifecycle.
  final String generation;

  /// Ordered publication position within [generation].
  ///
  /// Revisions are transient and cannot be compared across generations.
  final int revision;

  /// Immutable application state obtained through authoritative observation.
  final RudraState state;
}
