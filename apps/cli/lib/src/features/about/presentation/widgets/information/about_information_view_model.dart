/// Immutable application information prepared for display.
///
/// This model contains only About's textual presentation data.
/// It has no dependency on SDK services, terminal output,
/// command registration, or rendering technologies.
///
/// Example:
/// ```dart
/// final model = AboutInformationViewModel(
///   product_name: 'Rudra',
///   description: 'User-directed filesystem exploration.',
/// );
///
/// print(model.product_name);
/// // Rudra
/// ```
final class AboutInformationViewModel {
  /// Creates a validated application-information presentation.
  ///
  /// Both [product_name] and [description] must be nonblank.
  ///
  /// Throws [ArgumentError] for invalid input.
  ///
  /// Construction performs no filesystem or terminal operations.
  AboutInformationViewModel({
    required this.product_name,
    required this.description,
  }) {
    if (product_name.trim().isEmpty) {
      throw ArgumentError.value(
        product_name,
        'product_name',
        'The product name must not be blank.',
      );
    }

    if (description.trim().isEmpty) {
      throw ArgumentError.value(
        description,
        'description',
        'The product description must not be blank.',
      );
    }
  }

  /// Display-ready product name.
  final String product_name;

  /// Human-readable application description.
  final String description;
}
