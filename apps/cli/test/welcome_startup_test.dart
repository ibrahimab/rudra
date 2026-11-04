import 'package:rudra_cli/rudra_cli.dart';
import 'package:rudra_cli/src/composition/product_sdk_composition.dart';
import 'package:rudra_cli/src/presentation/welcome/welcome_controller.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies welcome-controller behavior and application startup.
///
/// Tests use an injected TargetInspector with no native
/// filesystem dependencies.
///
/// Startup must not enumerate directories, inspect entries,
/// manage sessions, or execute cleanup operations.
void main() {
  group('WelcomeController', () {
    test('renders a configured SDK target', () {
      final inspector = _StartupInspector();

      final composition = ProductSdkComposition(
        sdk: RudraSdk(
          target_id: 'fixture-target',
          inspector: inspector,
        ),
        working_directory: TargetPath('/fixture'),
      );

      final output = StringBuffer();

      final controller = WelcomeController(
        composition: composition,
        output: output,
      );

      controller.show();

      expect(output.toString(), contains('Rudra'));
      expect(
        output.toString(),
        contains('Target: fixture-target'),
      );
      expect(
        output.toString(),
        contains('Starting directory: /fixture'),
      );
      expect(output.toString(), contains('rudra ls'));

      expect(inspector.enumeration_count, 0);
      expect(inspector.inspection_count, 0);
    });

    test('renders unavailable target information', () {
      final output = StringBuffer();

      final controller = WelcomeController(
        composition: null,
        output: output,
      );

      controller.show();

      expect(
        output.toString(),
        contains('Filesystem inspection is not available'),
      );
      expect(output.toString(), isNot(contains('rudra ls')));
      expect(output.toString(), contains('rudra about'));
    });
  });

  group('Production CLI welcome startup', () {
    test('displays welcome screen without arguments', () async {
      final inspector = _StartupInspector();

      final composition = ProductSdkComposition(
        sdk: RudraSdk(
          target_id: 'fixture-target',
          inspector: inspector,
        ),
        working_directory: TargetPath('/fixture'),
      );

      final output = StringBuffer();
      final errors = StringBuffer();

      final cli = RudraCli.product(
        target_composition: composition,
        output: output,
        error_output: errors,
      );

      final status = await cli.run([]);

      expect(status, RudraExitCode.success.value);
      expect(output.toString(), contains('Rudra'));
      expect(
        output.toString(),
        contains('Target: fixture-target'),
      );
      expect(
        output.toString(),
        contains('Starting directory: /fixture'),
      );
      expect(output.toString(), contains('rudra ls'));

      expect(errors.toString(), isEmpty);

      // The welcome screen must not initiate inspection.
      expect(inspector.enumeration_count, 0);
      expect(inspector.inspection_count, 0);
    });

    test('preserves explicit command registration', () {
      final composition = ProductSdkComposition(
        sdk: RudraSdk(
          target_id: 'fixture-target',
          inspector: _StartupInspector(),
        ),
        working_directory: TargetPath('/fixture'),
      );

      final cli = RudraCli.product(
        target_composition: composition,
        output: StringBuffer(),
      );

      expect(
        cli.command_names,
        containsAll(['about', 'ls']),
      );

      expect(
        cli.module_ids,
        containsAll([
          'rudra.product.about',
          'rudra.product.filesystem',
        ]),
      );
    });

    test('retains single-invocation lifecycle', () async {
      final inspector = _StartupInspector();

      final composition = ProductSdkComposition(
        sdk: RudraSdk(
          target_id: 'fixture-target',
          inspector: inspector,
        ),
        working_directory: TargetPath('/fixture'),
      );

      final cli = RudraCli.product(
        target_composition: composition,
        output: StringBuffer(),
      );

      final first_status = await cli.run([]);

      expect(first_status, RudraExitCode.success.value);

      await expectLater(
        cli.run([]),
        throwsStateError,
      );

      expect(inspector.enumeration_count, 0);
      expect(inspector.inspection_count, 0);
    });
  });
}

/// A read-only inspection test double for CLI startup.
///
/// The inspector records filesystem operations.
///
/// Welcome-screen rendering must never invoke these methods.
/// Any unexpected entry inspection fails explicitly.
final class _StartupInspector implements TargetInspector {
  /// Creates an inspector with no configured filesystem entries.
  ///
  /// Construction performs no native filesystem operations.
  _StartupInspector();

  /// Number of directory enumeration requests.
  int enumeration_count = 0;

  /// Number of individual entry inspections.
  int inspection_count = 0;

  /// Records enumeration without accessing the filesystem.
  ///
  /// No children are configured for this test double.
  @override
  Stream<TargetPath> list_directory(TargetPath path) {
    enumeration_count++;

    return const Stream<TargetPath>.empty();
  }

  /// Rejects unexpected entry inspection.
  @override
  Future<FilesystemEntry> inspect(TargetPath path) async {
    inspection_count++;

    throw StateError(
      'Unexpected inspection during startup: ${path.value}',
    );
  }

  /// Rejects unexpected capability discovery.
  @override
  Future<TargetCapabilities> capabilities_for(
    TargetPath path,
  ) async {
    throw StateError(
      'Unexpected capability discovery: ${path.value}',
    );
  }

  /// Rejects unexpected symbolic-link resolution.
  @override
  Future<TargetPath> read_symbolic_link(
    TargetPath path,
  ) async {
    throw StateError(
      'Unexpected symbolic-link access: ${path.value}',
    );
  }
}
