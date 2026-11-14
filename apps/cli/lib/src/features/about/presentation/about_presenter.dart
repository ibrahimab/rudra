import 'about_view_model.dart';
import 'widgets/information/about_information_view_model.dart';

/// Prepares application information for the About screen.
///
/// The presenter transforms the supplied product identity
/// into an immutable [AboutViewModel].
///
/// The description is presentation-specific copy rather than
/// filesystem or application workflow state.
///
/// The presenter does not:
/// - Read application or filesystem state.
/// - Invoke Rudra SDK services.
/// - Write to stdout or stderr.
/// - Create terminal widgets.
/// - Manage sessions or authorization.
///
/// Example:
/// ```dart
/// final view_model = const AboutPresenter().present(
///   product_name: 'Rudra',
/// );
///
/// print(view_model.information.description);
/// // User-directed filesystem exploration.
/// ```
final class AboutPresenter {
  /// Creates a stateless application-information presenter.
  const AboutPresenter();

  /// Prepares an immutable About presentation.
  ///
  /// [product_name] comes from application composition.
  ///
  /// The product name is validated by the component view model.
  /// This method does not perform filesystem or terminal I/O.
  AboutViewModel present({
    required String product_name,
  }) {
    return AboutViewModel(
      information: AboutInformationViewModel(
        product_name: product_name,
        description: 'User-directed filesystem exploration.',
      ),
    );
  }
}
