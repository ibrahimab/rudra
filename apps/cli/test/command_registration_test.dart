import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:rudra_cli/rudra_cli.dart';
import 'package:test/test.dart';

import '../tool/src/dev_tasks.dart';
import '../tool/src/dev_tools_cli_module.dart';

/// Verifies product/development registration and CLI lifecycle rules.
void main() {
  group('RudraCli production composition', () {
    test('registers product commands', () {
      final cli = RudraCli.product();

      expect(cli.command_names, contains('about'));
      expect(cli.module_ids, contains('rudra.product.about'));
    });

    test('excludes development commands', () {
      final cli = RudraCli.product();

      for (final name in [
        'test',
        'check',
        'analyze',
        'format',
        'build',
      ]) {
        expect(
          cli.command_names.contains(name),
          isFalse,
          reason: '$name must not be registered in production.',
        );
      }
    });

    test('executes product commands successfully', () async {
      final cli = RudraCli.product();

      final status = await cli.run(['about']);

      expect(status, RudraExitCode.success.value);
    });

    test('maps invalid arguments to a typed exit code', () async {
      final diagnostics = StringBuffer();

      final cli = RudraCli.product(
        error_output: diagnostics,
      );

      final status = await cli.run(['--invalid-option']);

      expect(status, RudraExitCode.invalid_usage.value);
      expect(diagnostics.isNotEmpty, isTrue);
    });
  });

  group('RudraCli module lifecycle', () {
    test('supports registering independent modules', () {
      final cli = RudraCli();

      cli.register_module(
        const _StubModule('module.one', 'example'),
      );

      expect(cli.command_names, contains('example'));
      expect(cli.module_ids, contains('module.one'));
    });

    test('rejects duplicate module identifiers', () {
      final cli = RudraCli();

      cli.register_module(
        const _StubModule('duplicate', 'first'),
      );

      expect(
        () => cli.register_module(
          const _StubModule('duplicate', 'second'),
        ),
        throwsStateError,
      );
    });

    test('rejects conflicting command names', () {
      final cli = RudraCli();

      cli.register_module(
        const _StubModule('module.one', 'example'),
      );

      expect(
        () => cli.register_module(
          const _StubModule('module.two', 'example'),
        ),
        throwsStateError,
      );

      // A rejected contribution must not register its module.
      expect(cli.module_ids, isNot(contains('module.two')));
    });

    test('rejects reserved help command names', () {
      final cli = RudraCli();

      expect(
        () => cli.register_module(
          const _StubModule('reserved', 'help'),
        ),
        throwsStateError,
      );
    });

    test('rejects modules without commands', () {
      final cli = RudraCli();

      expect(
        () => cli.register_module(const _EmptyModule()),
        throwsStateError,
      );
    });

    test('prevents registration after execution', () async {
      final cli = RudraCli.product();

      await cli.run(['about']);

      expect(
        () => cli.register_module(
          const _StubModule('late', 'late-command'),
        ),
        throwsStateError,
      );
    });

    test('prevents executing an instance twice', () async {
      final cli = RudraCli.product();

      await cli.run(['about']);

      await expectLater(
        cli.run(['about']),
        throwsStateError,
      );
    });
  });

  group('RudraCli development composition', () {
    test('extends the product registry', () {
      final cli = RudraCli.product();

      cli.register_module(
        DevToolsCliModule(
          DevTasks(Directory.current),
        ),
      );

      expect(
        cli.command_names,
        containsAll([
          'about',
          'test',
          'check',
          'analyze',
          'format',
          'build',
        ]),
      );

      expect(
        cli.module_ids,
        contains('rudra.development.tools'),
      );
    });
  });
}

/// Provides a minimal test module with a configurable command name.
final class _StubModule implements RudraCliModule {
  /// Creates a module used exclusively by registration tests.
  const _StubModule(this.module_id, this.command_name);

  /// Identifier supplied by the test.
  @override
  final String module_id;

  /// Name of the command supplied by the test.
  final String command_name;

  /// Creates a harmless command with the requested name.
  @override
  Iterable<Command<int>> create_commands() {
    return [_StubCommand(command_name)];
  }
}

/// Provides a module that deliberately contributes no commands.
final class _EmptyModule implements RudraCliModule {
  /// Creates an empty test module.
  const _EmptyModule();

  /// Identifier of the empty module.
  @override
  String get module_id => 'empty';

  /// Returns no commands to verify registration validation.
  @override
  Iterable<Command<int>> create_commands() {
    return <Command<int>>[];
  }
}

/// Harmless command used to test registration and dispatch.
final class _StubCommand extends Command<int> {
  /// Creates a command with the supplied name.
  _StubCommand(this.name);

  /// Configurable command identifier.
  @override
  final String name;

  /// Description displayed by generated help.
  @override
  String get description => 'A test command.';

  /// Returns success without performing filesystem operations.
  @override
  int run() => RudraExitCode.success.value;
}
