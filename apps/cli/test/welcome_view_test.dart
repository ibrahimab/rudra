import 'package:rudra_cli/src/presentation/welcome/welcome_model.dart';
import 'package:rudra_cli/src/presentation/welcome/welcome_view.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies the CLI welcome presentation independently.
///
/// No native target adapter, terminal session, or filesystem
/// operation is required by these tests.
void main() {
  group('WelcomeModel', () {
    test('represents a configured inspection target', () {
      final directory = TargetPath('/Users/example');

      final model = WelcomeModel(
        product_name: 'Rudra',
        target_id: 'local-macos',
        starting_directory: directory,
      );

      expect(model.product_name, 'Rudra');
      expect(model.target_id, 'local-macos');
      expect(model.starting_directory, same(directory));
      expect(model.can_inspect, isTrue);
    });

    test('represents an unavailable inspection target', () {
      final model = WelcomeModel(
        product_name: 'Rudra',
      );

      expect(model.can_inspect, isFalse);
      expect(model.target_id, isNull);
      expect(model.starting_directory, isNull);
    });

    test('rejects blank product names', () {
      for (final name in ['', ' ', '\t', '\n']) {
        expect(
          () => WelcomeModel(product_name: name),
          throwsArgumentError,
        );
      }
    });

    test('requires target ID and directory together', () {
      expect(
        () => WelcomeModel(
          product_name: 'Rudra',
          target_id: 'local-macos',
        ),
        throwsArgumentError,
      );

      expect(
        () => WelcomeModel(
          product_name: 'Rudra',
          starting_directory: TargetPath('/tmp'),
        ),
        throwsArgumentError,
      );
    });

    test('rejects blank target identifiers', () {
      expect(
        () => WelcomeModel(
          product_name: 'Rudra',
          target_id: ' ',
          starting_directory: TargetPath('/tmp'),
        ),
        throwsArgumentError,
      );
    });

    test('preserves target-native Windows paths', () {
      final model = WelcomeModel(
        product_name: 'Rudra',
        target_id: 'local-windows',
        starting_directory: TargetPath(
          r'C:\Users\example',
        ),
      );

      expect(
        model.starting_directory!.value,
        r'C:\Users\example',
      );

      expect(model.can_inspect, isTrue);
    });
  });

  group('WelcomeView', () {
    const view = WelcomeView();

    test('renders configured target information', () {
      final output = StringBuffer();

      final model = WelcomeModel(
        product_name: 'Rudra',
        target_id: 'local-macos',
        starting_directory: TargetPath('/Users/example'),
      );

      view.render(model, output: output);

      final text = output.toString();

      expect(text, contains('RUDRA  |  READ ONLY'));
      expect(text, contains('Read-only filesystem exploration.'));
      expect(text, contains('Target: local-macos'));
      expect(
        text,
        contains('Starting directory: /Users/example'),
      );

      expect(text, contains('rudra ls'));
      expect(text, contains('rudra about'));
      expect(text, contains('rudra --help'));
    });

    test('does not advertise unsupported inspection', () {
      final output = StringBuffer();

      view.render(
        WelcomeModel(product_name: 'Rudra'),
        output: output,
      );

      final text = output.toString();

      expect(
        text,
        contains('Filesystem inspection is not available'),
      );

      expect(text, isNot(contains('rudra ls')));
      expect(text, contains('rudra about'));
      expect(text, contains('rudra --help'));
    });

    test('renders target-native paths unchanged', () {
      final output = StringBuffer();

      view.render(
        WelcomeModel(
          product_name: 'Rudra',
          target_id: 'local-windows',
          starting_directory: TargetPath(
            r'C:\Users\example',
          ),
        ),
        output: output,
      );

      expect(
        output.toString(),
        contains(r'C:\Users\example'),
      );
    });

    test('includes the inspection safety statement', () {
      final output = StringBuffer();

      view.render(
        WelcomeModel(product_name: 'Rudra'),
        output: output,
      );

      expect(
        output.toString(),
        contains(
          'Inspection never authorizes file modification or deletion.',
        ),
      );
    });

    test('renders deterministically without shared state', () {
      final model = WelcomeModel(
        product_name: 'Rudra',
        target_id: 'local-macos',
        starting_directory: TargetPath('/tmp'),
      );

      final first_output = StringBuffer();
      final second_output = StringBuffer();

      view.render(model, output: first_output);
      view.render(model, output: second_output);

      expect(
        first_output.toString(),
        second_output.toString(),
      );
    });
  });
}
