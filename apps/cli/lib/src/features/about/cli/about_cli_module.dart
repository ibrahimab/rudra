import 'package:args/command_runner.dart';

import '../../../core/cli/rudra_cli_module.dart';
import '../../../core/rendering/renderer.dart';

import '../presentation/about_presenter.dart';
import '../presentation/about_view_model.dart';

import 'about_command.dart';

/// Registers Rudra's application-information commands.
///
/// The module receives application identity and a renderer
/// through explicit dependency injection.
///
/// It does not select rendering backends or output sinks.
/// That responsibility belongs to application composition.
///
/// The About command remains available regardless of
/// configured filesystem target support.
///
/// Command registration performs no terminal or filesystem I/O.
///
/// Example:
/// ```dart
/// cli.register_module(
///   AboutCliModule(
///     product_name: 'Rudra',
///     renderer: renderer,
///   ),
/// );
/// ```
final class AboutCliModule implements RudraCliModule {
  /// Creates an application-information command module.
  ///
  /// [product_name] is the application identity.
  ///
  /// [renderer] is the backend-independent presentation contract.
  ///
  /// [presenter] prepares the About presentation.
  ///
  /// Dependencies are reused by commands created by this module.
  AboutCliModule({
    required String product_name,
    required Renderer<AboutViewModel> renderer,
    AboutPresenter presenter = const AboutPresenter(),
  }) : _product_name = product_name,
       _renderer = renderer,
       _presenter = presenter;

  /// Application identity shared by registered commands.
  final String _product_name;

  /// Injected About rendering contract.
  final Renderer<AboutViewModel> _renderer;

  /// Stateless About presentation dependency.
  final AboutPresenter _presenter;

  /// Stable identifier of Rudra's About command module.
  @override
  String get module_id => 'rudra.product.about';

  /// Creates the commands provided by this module.
  ///
  /// Construction does not render or inspect anything.
  @override
  Iterable<Command<int>> create_commands() {
    return [
      AboutCommand(
        product_name: _product_name,
        renderer: _renderer,
        presenter: _presenter,
      ),
    ];
  }
}
