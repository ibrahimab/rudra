import 'widgets/information/about_information_view_model.dart';

/// Immutable composition of About's presentation components.
///
/// The root view model supplies one presentation snapshot
/// to AboutScreen.
///
/// About currently has a single information component.
/// Additional components can be introduced without changing
/// the command or rendering contract.
///
/// This model does not duplicate child presentation fields.
///
/// No SDK access, filesystem I/O, or terminal I/O occurs here.
///
/// Example:
/// ```dart
/// final model = AboutViewModel(
///   information: AboutInformationViewModel(
///     product_name: 'Rudra',
///     description: 'User-directed filesystem exploration.',
///   ),
/// );
///
/// print(model.information.product_name);
/// // Rudra
/// ```
final class AboutViewModel {
  /// Composes the independently prepared application information.
  const AboutViewModel({
    required this.information,
  });

  /// Application identity and descriptive information.
  final AboutInformationViewModel information;
}
