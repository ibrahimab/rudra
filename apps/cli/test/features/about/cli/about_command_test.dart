import 'package:rudra_cli/rudra_cli.dart';

import 'package:rudra_cli/src/core/rendering/renderer.dart';
import 'package:rudra_cli/src/features/about/cli/about_cli_module.dart';
import 'package:rudra_cli/src/features/about/cli/about_command.dart';
import 'package:rudra_cli/src/features/about/presentation/about_view_model.dart';
import 'package:rudra_cli/src/features/about/presentation/bare_about_renderer.dart';

import 'package:test/test.dart';

/// Verifies About command registration, dependency injection,
/// and error propagation without filesystem inspection.
void main() {
  group('AboutCliModule', () {
    test('registers About without producing output', () {
      final output = StringBuffer();
      final cli = RudraCli();

      cli.register_module(
        AboutCliModule(
          product_name: 'Rudra',
          renderer: BareAboutRenderer(output: output),
        ),
      );

      expect(cli.command_names, contains('about'));
      expect(cli.module_ids, contains('rudra.product.about'));
      expect(output.toString(), isEmpty);
    });

    test('renders through the injected output destination', () async {
      final output = StringBuffer();
      final errors = StringBuffer();

      final cli = RudraCli(error_output: errors);

      cli.register_module(
        AboutCliModule(
          product_name: 'Rudra',
          renderer: BareAboutRenderer(output: output),
        ),
      );

      final status = await cli.run(['about']);

      expect(status, RudraExitCode.success.value);
      expect(
        output.toString(),
        'Rudra - User-directed filesystem exploration.\n',
      );
      expect(errors.toString(), isEmpty);
    });
  });

  group('AboutCommand', () {
    test('passes one prepared view model to its renderer', () {
      final renderer = _RecordingAboutRenderer();

      final command = AboutCommand(product_name: 'Rudra', renderer: renderer);

      expect(renderer.models, isEmpty);

      final status = command.run();

      expect(status, RudraExitCode.success.value);
      expect(renderer.models, hasLength(1));

      final model = renderer.models.single;

      expect(model.information.product_name, 'Rudra');
      expect(
        model.information.description,
        'User-directed filesystem exploration.',
      );
    });

    test('propagates rendering failures', () {
      final command = AboutCommand(
        product_name: 'Rudra',
        renderer: _FailingAboutRenderer(),
      );

      expect(() => command.run(), throwsStateError);
    });
  });
}

/// Records presentation requests without performing terminal I/O.
final class _RecordingAboutRenderer implements Renderer<AboutViewModel> {
  /// Captured About presentations.
  final List<AboutViewModel> models = [];

  /// Records the supplied model for inspection by tests.
  @override
  void render(AboutViewModel view_model) {
    models.add(view_model);
  }
}

/// Simulates a renderer failure without touching the terminal.
final class _FailingAboutRenderer implements Renderer<AboutViewModel> {
  /// Throws to verify the command does not fabricate success.
  @override
  void render(AboutViewModel view_model) {
    throw StateError('Renderer failed.');
  }
}
