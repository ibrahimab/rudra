import 'package:rudra_cli/rudra_cli.dart';
import 'package:rudra_cli/src/features/host/cli/host_cli_module.dart';
import 'package:rudra_host/rudra_host.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies host command registration, execution and presentation.
///
/// Injected host operations isolate CLI behavior from native
/// process management and SQLite persistence.
void main() {
  late StringBuffer output;
  late StringBuffer errors;

  setUp(() {
    output = StringBuffer();
    errors = StringBuffer();
  });

  /// Creates a CLI containing only the host feature contribution.
  ///
  /// [run_host] supplies the controlled application operation.
  /// Returns a fresh CLI with isolated presentation destinations.
  RudraCli create_cli(HostRunOperation run_host) {
    final cli = RudraCli(error_output: errors);

    cli.register_module(
      HostCliModule(run_host: run_host, output: output, error_output: errors),
    );

    return cli;
  }

  /// Rejects unexpected execution of the injected host operation.
  ///
  /// Used by registration and argument-validation tests where
  /// application execution must never be reached.
  final HostRunOperation unexpected_execution =
      ({
        required data_directory,
        required start_workflow,
        required on_ready,
      }) async {
        fail('Host execution must not be invoked.');
      };

  test('production composition registers the host feature', () {
    final cli = RudraCli.product(output: output, error_output: errors);

    expect(cli.command_names, contains('host'));

    expect(cli.module_ids, contains('rudra.product.host'));

    expect(output.toString(), isEmpty);
    expect(errors.toString(), isEmpty);
  });

  test('registration does not execute the host', () {
    final cli = create_cli(unexpected_execution);

    expect(cli.command_names, contains('host'));
    expect(output.toString(), isEmpty);
    expect(errors.toString(), isEmpty);
  });

  test('rejects missing development directory', () async {
    final cli = create_cli(unexpected_execution);

    final status = await cli.run(['host', 'start', '--foreground']);

    expect(status, RudraExitCode.invalid_usage.value);

    expect(
      errors.toString(),
      contains('A development data directory is required.'),
    );
  });

  test('rejects unsupported managed background startup', () async {
    final cli = create_cli(unexpected_execution);

    final status = await cli.run(['host', 'start', '--data-dir', '/fixture']);

    expect(status, RudraExitCode.invalid_usage.value);

    expect(errors.toString(), contains('Only foreground host execution'));
  });

  test('rejects positional arguments before execution', () async {
    final cli = create_cli(unexpected_execution);

    final status = await cli.run([
      'host',
      'start',
      '--foreground',
      '--data-dir',
      '/fixture',
      'unexpected',
    ]);

    expect(status, RudraExitCode.invalid_usage.value);
    expect(errors.toString(), contains('positional arguments'));
  });

  test('ordinary startup requests no workflow establishment', () async {
    final cli = create_cli(({
      required data_directory,
      required start_workflow,
      required on_ready,
    }) async {
      expect(data_directory.path, '/fixture');
      expect(start_workflow, isFalse);

      on_ready('trusted-owner', null);
    });

    final status = await cli.run([
      'host',
      'start',
      '--foreground',
      '--data-dir',
      '/fixture',
    ]);

    expect(status, RudraExitCode.success.value);

    expect(output.toString(), contains('Host identity: trusted-owner'));
    expect(output.toString(), contains('Workflow: NONE'));
    expect(output.toString(), contains('Host ready'));
    expect(output.toString(), contains('Rudra Host stopped'));
    expect(errors.toString(), isEmpty);
  });

  test('explicit startup forwards workflow establishment', () async {
    var invoked = false;

    final snapshot = WorkflowSnapshot(
      identity: WorkflowIdentity(
        workflow_id: 'workflow-1',
        os_user_id: 'trusted-owner',
        target_id: 'test-target',
        root: TargetPath('/workspace'),
      ),
      version: 1,
      lifecycle: WorkflowLifecycle(id: 'test.active', is_terminal: false),
    );

    final cli = create_cli(({
      required data_directory,
      required start_workflow,
      required on_ready,
    }) async {
      invoked = true;

      expect(data_directory.path, '/fixture');
      expect(start_workflow, isTrue);

      // Supply a committed snapshot through the application
      // boundary rather than performing actual workflow processing.
      on_ready('trusted-owner', snapshot);
    });

    final status = await cli.run([
      'host',
      'start',
      '--foreground',
      '--data-dir',
      '/fixture',
      '--start-workflow',
    ]);

    expect(invoked, isTrue);
    expect(status, RudraExitCode.success.value);
    expect(output.toString(), contains('Workflow started'));
    expect(output.toString(), contains('Workflow ID: workflow-1'));
    expect(output.toString(), contains('Workflow version: 1'));
  });

  test('maps workflow conflicts to the existing exit status', () async {
    final cli = create_cli(({
      required data_directory,
      required start_workflow,
      required on_ready,
    }) async {
      throw const WorkflowAlreadyActiveException(
        workflow_id: 'existing-workflow',
      );
    });

    final status = await cli.run([
      'host',
      'start',
      '--foreground',
      '--data-dir',
      '/fixture',
      '--start-workflow',
    ]);

    expect(status, RudraExitCode.workflow_conflict.value);
    expect(errors.toString(), contains('existing-workflow'));
    expect(output.toString(), isNot(contains('Host ready')));
  });

  test('maps unsupported platforms to configuration errors', () async {
    final cli = create_cli(({
      required data_directory,
      required start_workflow,
      required on_ready,
    }) async {
      throw UnsupportedError('Unsupported host platform.');
    });

    final status = await cli.run([
      'host',
      'start',
      '--foreground',
      '--data-dir',
      '/fixture',
    ]);

    expect(status, RudraExitCode.configuration_error.value);
    expect(errors.toString(), contains('Host unavailable'));
  });

  test('maps execution failures to the software error status', () async {
    final cli = create_cli(({
      required data_directory,
      required start_workflow,
      required on_ready,
    }) async {
      throw StateError('Host initialization failed.');
    });

    final status = await cli.run([
      'host',
      'start',
      '--foreground',
      '--data-dir',
      '/fixture',
    ]);

    expect(status, RudraExitCode.software_error.value);

    expect(errors.toString(), contains('Host initialization failed.'));

    expect(output.toString(), isNot(contains('Host ready')));
    expect(output.toString(), isNot(contains('Host stopped')));
  });
}
