/// Immutable presentation data for the Welcome safety footer.
///
/// The message is informational and does not provide cleanup
/// authorization. All actual safety policies belong to the SDK.
///
/// Example:
/// ```dart
/// final model = WelcomeFooterViewModel(
///   safety_statement: 'Exploration is read-only.',
/// );
/// ```
final class WelcomeFooterViewModel {
  /// Creates a footer with a nonblank safety statement.
  ///
  /// Throws [ArgumentError] when the statement is blank.
  WelcomeFooterViewModel({required this.safety_statement}) {
    if (safety_statement.trim().isEmpty) {
      throw ArgumentError.value(
        safety_statement,
        'safety_statement',
        'The safety statement must not be blank.',
      );
    }
  }

  /// Display-only safety information.
  final String safety_statement;
}
