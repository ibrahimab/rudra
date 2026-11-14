import 'package:args/command_runner.dart';

import '../../../core/cli/rudra_exit_code.dart';
import '../../../core/rendering/renderer.dart';

import '../presentation/about_presenter.dart';
import '../presentation/about_view_model.dart';

/// Coordinates the read-only About command.
///
/// This command receives its dependencies through application
/// composition rather than creating output backends itself.
///
/// Responsibilities:
/// - Obtain a prepared About view model from [AboutPresenter].
/// - Delegate display to an injected [Renderer].
/// - Return the typed success exit code.
///
/// It does not:
/// - Write directly to stdout or stderr.
/// - Access SDK or platform target services.
/// - Implement terminal formatting.
/// - Read or modify the filesystem.
/// - Create or execute cleanup sessions.
///
/// Example:
/// ```dart
/// final command = AboutCommand(
///   product_name: 'Rudra',
///   renderer: renderer,
/// );
/// ```
///
/// CLI usage:
/// ```text
/// rudra about
/// ```
final class AboutCommand extends Command<int> {
  /// Creates an About command with explicit presentation dependencies.
  ///
  /// [product_name] identifies the application.
  ///
  /// [renderer] receives the prepared [AboutViewModel].
  ///
  /// [presenter] transforms the product identity into
  /// immutable presentation data.
  ///
  /// Construction performs no terminal or filesystem I/O.
  AboutCommand({
    required String product_name,
    required Renderer<AboutViewModel> renderer,
    AboutPresenter presenter = const AboutPresenter(),
  }) : _product_name = product_name,
       _renderer = renderer,
       _presenter = presenter;

  /// Product identity supplied by application composition.
  final String _product_name;

  /// Backend-independent presentation renderer.
  final Renderer<AboutViewModel> _renderer;

  /// Stateless application-information presenter.
  final AboutPresenter _presenter;

  /// Command identifier used by the argument parser.
  @override
  String get name => 'about';

  /// Human-readable description displayed in CLI help.
  @override
  String get description => 'Display information about Rudra.';

  /// Prepares and renders the About screen.
  ///
  /// Returns [RudraExitCode.success] after successful rendering.
  ///
  /// Presenter and renderer exceptions propagate to the caller.
  /// No SDK request or filesystem modification occurs.
  @override
  int run() {
    final view_model = _presenter.present(product_name: _product_name);

    _renderer.render(view_model);

    return RudraExitCode.success.value;
  }
}
