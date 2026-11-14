/// Immutable presentation data for the Welcome header.
///
/// This component contains only the application title.
/// Header layout and semantic styling belong to WelcomeHeader.
///
/// Example:
/// ```dart
/// final model = WelcomeHeaderViewModel(
///   product_title: 'RUDRA',
/// );
///
/// print(model.product_title);
/// // RUDRA
/// ```
final class WelcomeHeaderViewModel {
  /// Creates a header with a nonblank application title.
  ///
  /// Throws [ArgumentError] when the title is blank.
  WelcomeHeaderViewModel({
    required this.product_title,
  }) {
    if (product_title.trim().isEmpty) {
      throw ArgumentError.value(
        product_title,
        'product_title',
        'The application title must not be blank.',
      );
    }
  }

  /// Prepared application title.
  final String product_title;
}
