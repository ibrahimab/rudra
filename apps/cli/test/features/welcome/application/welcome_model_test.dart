import 'package:rudra_cli/src/features/welcome/application/welcome_model.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies Rudra's validated welcome application state.
///
/// WelcomeModel represents the target configuration and SDK
/// observation consumed by WelcomePresenter.
///
/// These tests exercise application-state invariants rather
/// than terminal presentation or renderer implementations.
///
/// No real filesystem, target adapter, or terminal is used.
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
      expect(model.listing, isNull);
    });

    test('represents an unavailable inspection target', () {
      final model = WelcomeModel(
        product_name: 'Rudra',
      );

      expect(model.can_inspect, isFalse);
      expect(model.target_id, isNull);
      expect(model.starting_directory, isNull);
      expect(model.listing, isNull);
    });

    test('rejects blank product names', () {
      for (final name in ['', ' ', '\t', '\n']) {
        expect(
          () => WelcomeModel(product_name: name),
          throwsArgumentError,
        );
      }
    });

    test('requires target and starting directory together', () {
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
      final directory = TargetPath(
        r'C:\Users\example',
      );

      final model = WelcomeModel(
        product_name: 'Rudra',
        target_id: 'local-windows',
        starting_directory: directory,
      );

      expect(model.starting_directory, same(directory));

      expect(
        model.starting_directory!.value,
        r'C:\Users\example',
      );

      expect(model.can_inspect, isTrue);
    });

    test('accepts a matching SDK directory observation', () {
      final directory = TargetPath('/fixture');

      final listing = DirectoryListing(
        target_id: 'fixture-target',
        directory: directory,
        entries: [],
        is_complete: true,
      );

      final model = WelcomeModel(
        product_name: 'Rudra',
        target_id: 'fixture-target',
        starting_directory: directory,
        listing: listing,
      );

      expect(model.listing, same(listing));
      expect(model.can_inspect, isTrue);
      expect(model.listing!.is_complete, isTrue);
    });

    test('rejects an observation for another target', () {
      final listing = _listing(
        target_id: 'different-target',
      );

      expect(
        () => WelcomeModel(
          product_name: 'Rudra',
          target_id: 'fixture-target',
          starting_directory: TargetPath('/fixture'),
          listing: listing,
        ),
        throwsArgumentError,
      );
    });

    test('rejects an observation for another directory', () {
      final listing = _listing(
        directory: '/different-directory',
      );

      expect(
        () => WelcomeModel(
          product_name: 'Rudra',
          target_id: 'fixture-target',
          starting_directory: TargetPath('/fixture'),
          listing: listing,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a listing without a configured target', () {
      expect(
        () => WelcomeModel(
          product_name: 'Rudra',
          listing: _listing(),
        ),
        throwsArgumentError,
      );
    });

    test('preserves incomplete observations', () {
      final listing = _listing(
        is_complete: false,
      );

      final model = WelcomeModel(
        product_name: 'Rudra',
        target_id: 'fixture-target',
        starting_directory: TargetPath('/fixture'),
        listing: listing,
      );

      expect(model.listing, same(listing));
      expect(model.listing!.is_complete, isFalse);

      // Validation must not reinterpret an incomplete
      // inspection as a successful observation.
      expect(model.can_inspect, isTrue);
    });
  });
}

/// Creates a deterministic SDK directory observation.
///
/// The observation is constructed entirely in memory.
///
/// No target inspection or filesystem mutation occurs.
DirectoryListing _listing({
  String target_id = 'fixture-target',
  String directory = '/fixture',
  bool is_complete = true,
}) {
  return DirectoryListing(
    target_id: target_id,
    directory: TargetPath(directory),
    entries: [],
    is_complete: is_complete,
  );
}
