import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import 'about_information_view_model.dart';

/// Displays Rudra's application identity and description.
///
/// The widget receives only its dedicated presentation model.
///
/// It produces one terminal line without directly writing
/// to stdout or managing terminal capabilities.
///
/// Sanitization, optional styling, and width handling belong
/// to the shared rendering backend.
///
/// The widget never invokes SDK services or filesystem operations.
///
/// Example:
/// ```dart
/// final widget = AboutInformation(
///   AboutInformationViewModel(
///     product_name: 'Rudra',
///     description: 'User-directed filesystem exploration.',
///   ),
/// );
///
/// print(widget.height);
/// // 1
/// ```
final class AboutInformation implements TerminalWidget {
  /// Creates a presentation widget from prepared application data.
  const AboutInformation(this.view_model);

  /// Information displayed by this widget.
  final AboutInformationViewModel view_model;

  /// Number of rows occupied by the information component.
  static const int fixed_rows = 1;

  @override
  int get height => fixed_rows;

  @override
  Iterable<TerminalLine> build(
    TerminalConstraints constraints,
  ) sync* {
    yield TerminalLine(
      '${view_model.product_name} - ${view_model.description}',
      role: TerminalRole.title,
    );
  }
}
