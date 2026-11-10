import 'package:test/test.dart';

import '../../tool/src/dev_tasks.dart';

/// Verifies workspace package discovery and malformed-input handling.
void main() {
  group('Workspace listing parser', () {
    test('extracts all workspace package paths', () {
      const output = 'Package          Path\n'
          'rudra_workspace  ./\n'
          'rudra_cli        apps/cli/\n'
          'rudra_sdk        packages/sdk/\n';

      final paths = parse_workspace_paths(output);

      expect(
        paths,
        equals([
          './',
          'apps/cli/',
          'packages/sdk/',
        ]),
      );
    });

    test('ignores empty lines', () {
      const output = 'Package          Path\n'
          '\n'
          'rudra_cli        apps/cli/\n'
          '\n';

      expect(
        parse_workspace_paths(output),
        equals(['apps/cli/']),
      );
    });

    test('rejects unexpected output formats', () {
      expect(
        () => parse_workspace_paths('Unexpected output'),
        throwsFormatException,
      );
    });

    test('rejects workspace listings without packages', () {
      expect(
        () => parse_workspace_paths('Package          Path\n'),
        throwsFormatException,
      );
    });

    test('rejects malformed package entries', () {
      const output = 'Package          Path\n'
          'invalid-entry-without-path\n';

      expect(
        () => parse_workspace_paths(output),
        throwsFormatException,
      );
    });
  });

  group('Workspace package metadata', () {
    test('preserves package names and paths', () {
      const output = 'Package          Path\n'
          'rudra_workspace  ./\n'
          'rudra_cli        apps/cli/\n'
          'rudra_sdk        packages/sdk/\n';

      final packages = parse_workspace_packages(output);

      expect(packages.length, 3);

      expect(packages[1].name, 'rudra_cli');
      expect(packages[1].path, 'apps/cli/');

      expect(packages[2].name, 'rudra_sdk');
      expect(packages[2].path, 'packages/sdk/');
    });
  });

  group('Test argument construction', () {
    test('defaults to all tests', () {
      expect(
        build_test_arguments(),
        equals(['test']),
      );
    });

    test('forwards test name and tag filters', () {
      final arguments = build_test_arguments(
        test_name: 'TargetDescriptor',
        tags: 'unit',
        exclude_tags: 'slow',
      );

      expect(
        arguments,
        equals([
          'test',
          '--name',
          'TargetDescriptor',
          '--tags',
          'unit',
          '--exclude-tags',
          'slow',
        ]),
      );
    });

    test('preserves compound tag selectors', () {
      final arguments = build_test_arguments(
        tags: 'unit && !slow',
      );

      expect(
        arguments,
        equals([
          'test',
          '--tags',
          'unit && !slow',
        ]),
      );
    });
  });
}
