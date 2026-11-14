import 'package:rudra_cli/src/core/rendering/theme.dart';
import 'package:rudra_cli/src/core/rendering/widgets/terminal_widget.dart';

import 'package:rudra_cli/src/features/welcome/application/welcome_model.dart';
import 'package:rudra_cli/src/features/welcome/presentation/welcome_presenter.dart';
import 'package:rudra_cli/src/features/welcome/presentation/widgets/welcome_screen.dart';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies that Welcome composes independent terminal widgets.
///
/// SDK observations are constructed directly in memory.
/// No target inspector, terminal device, or filesystem mutation
/// is involved in these tests.
void main() {
  const presenter = WelcomePresenter();

  group('WelcomeScreen', () {
    test('composes unsupported target presentation', () {
      final presentation = presenter.present(
        WelcomeModel(product_name: 'Rudra'),
      );

      final screen = WelcomeScreen(presentation);

      final lines = screen
          .build(
            TerminalConstraints(),
          )
          .toList();

      expect(screen.height, 11);
      expect(lines, hasLength(screen.height));

      expect(
        lines.any((line) => line.text.contains('RUDRA')),
        isTrue,
      );

      expect(
        lines.any(
          (line) => line.text.contains(
            'Filesystem inspection is not available',
          ),
        ),
        isTrue,
      );

      expect(
        lines.any((line) => line.text.contains('rudra ls')),
        isFalse,
      );

      expect(
        lines.any((line) => line.text.contains('rudra about')),
        isTrue,
      );

      expect(
        lines.any((line) => line.role == TerminalRole.warning),
        isTrue,
      );
    });

    test('composes configured target without a listing', () {
      final presentation = presenter.present(
        WelcomeModel(
          product_name: 'Rudra',
          target_id: 'fixture-target',
          starting_directory: TargetPath('/fixture'),
        ),
      );

      final screen = WelcomeScreen(presentation);

      final lines = screen
          .build(
            TerminalConstraints(),
          )
          .toList();

      expect(screen.height, 14);
      expect(lines, hasLength(screen.height));

      expect(
        lines.any((line) => line.text == 'Target: fixture-target'),
        isTrue,
      );

      expect(
        lines.any(
          (line) => line.text == 'Starting directory: /fixture',
        ),
        isTrue,
      );

      expect(
        lines.any((line) => line.text.contains('rudra ls')),
        isTrue,
      );

      expect(
        lines.any((line) => line.text.contains('NAME')),
        isFalse,
      );
    });

    test('composes a detailed SDK listing once', () {
      final directory = TargetPath('/fixture');

      final observation = DirectoryListing(
        target_id: 'fixture-target',
        directory: directory,
        entries: [],
        is_complete: true,
      );

      final presentation = presenter.present(
        WelcomeModel(
          product_name: 'Rudra',
          target_id: 'fixture-target',
          starting_directory: directory,
          listing: observation,
        ),
      );

      final screen = WelcomeScreen(presentation);

      final lines = screen
          .build(
            TerminalConstraints(),
          )
          .toList();

      expect(screen.height, 19);
      expect(lines, hasLength(screen.height));

      expect(
        lines.where(
          (line) => line.text.contains(
            '0 observed entries',
          ),
        ),
        hasLength(1),
      );

      expect(
        lines.any((line) => line.text.contains('MODIFIED (UTC)')),
        isTrue,
      );

      expect(
        lines.any(
          (line) => line.text.contains('Available commands:'),
        ),
        isTrue,
      );

      expect(lines.last.role, TerminalRole.muted);
    });
  });
}
