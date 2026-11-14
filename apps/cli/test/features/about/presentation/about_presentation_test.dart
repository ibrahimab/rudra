import 'package:rudra_cli/src/core/rendering/bare/ansi_text.dart';
import 'package:rudra_cli/src/core/rendering/theme.dart';
import 'package:rudra_cli/src/core/rendering/widgets/terminal_widget.dart';

import 'package:rudra_cli/src/features/about/presentation/about_presenter.dart';
import 'package:rudra_cli/src/features/about/presentation/about_view_model.dart';
import 'package:rudra_cli/src/features/about/presentation/bare_about_renderer.dart';
import 'package:rudra_cli/src/features/about/presentation/widgets/about_screen.dart';
import 'package:rudra_cli/src/features/about/presentation/widgets/information/about_information.dart';
import 'package:rudra_cli/src/features/about/presentation/widgets/information/about_information_view_model.dart';

import 'package:test/test.dart';

/// Verifies the independent About presentation components.
///
/// The tests do not construct a real CLI, SDK service,
/// filesystem target adapter, or terminal host.
void main() {
  group('AboutPresenter', () {
    test('prepares immutable application information', () {
      final model = const AboutPresenter().present(
        product_name: 'Rudra',
      );

      expect(model.information.product_name, 'Rudra');
      expect(
        model.information.description,
        'User-directed filesystem exploration.',
      );
    });

    test('rejects blank product names', () {
      for (final name in ['', ' ', '\t', '\n']) {
        expect(
          () => const AboutPresenter().present(
            product_name: name,
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects blank descriptions', () {
      expect(
        () => AboutInformationViewModel(
          product_name: 'Rudra',
          description: ' ',
        ),
        throwsArgumentError,
      );
    });
  });

  group('AboutInformation', () {
    test('renders exactly one semantic terminal row', () {
      final model = _model();
      final widget = AboutInformation(model.information);

      final lines = widget
          .build(
            TerminalConstraints(),
          )
          .toList();

      expect(widget.height, 1);
      expect(lines, hasLength(widget.height));

      expect(
        lines.single.text,
        'Rudra - User-directed filesystem exploration.',
      );

      expect(lines.single.role, TerminalRole.title);
    });
  });

  group('AboutScreen', () {
    test('derives its height from the child widget', () {
      final screen = AboutScreen(_model());

      final lines = screen
          .build(
            TerminalConstraints(),
          )
          .toList();

      expect(screen.height, AboutInformation.fixed_rows);
      expect(lines, hasLength(screen.height));
      expect(lines.single.text, contains('Rudra'));
    });
  });

  group('BareAboutRenderer', () {
    test('renders application information to the injected sink', () {
      final output = StringBuffer();

      BareAboutRenderer(
        output: output,
      ).render(_model());

      expect(
        output.toString(),
        'Rudra - User-directed filesystem exploration.\n',
      );
    });

    test('sanitizes untrusted product information', () {
      final output = StringBuffer();

      final model = AboutViewModel(
        information: AboutInformationViewModel(
          product_name: 'Rudra\x1B[2J',
          description: 'User-directed filesystem exploration.',
        ),
      );

      BareAboutRenderer(
        output: output,
      ).render(model);

      expect(output.toString(), contains('Rudra?[2J'));
      expect(output.toString(), isNot(contains('\x1B')));
    });

    test('supports semantic ANSI styling', () {
      final output = StringBuffer();

      BareAboutRenderer(
        output: output,
        theme: TerminalTheme.ansi,
        ansi_text: const AnsiText(enabled: true),
      ).render(_model());

      expect(output.toString(), contains('\x1B[1;36m'));
      expect(output.toString(), contains('\x1B[0m'));
    });

    test('keeps plain output free of ANSI sequences', () {
      final output = StringBuffer();

      BareAboutRenderer(
        output: output,
      ).render(_model());

      expect(output.toString(), isNot(contains('\x1B')));
    });
  });
}

/// Creates a deterministic About presentation.
///
/// No application state or filesystem services are required.
AboutViewModel _model() {
  return const AboutPresenter().present(
    product_name: 'Rudra',
  );
}
