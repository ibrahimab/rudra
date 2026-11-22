import 'package:args/command_runner.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../core/cli/rudra_cli_module.dart';
import '../../../core/cli/rudra_exit_code.dart';

/// Registers explicit workflow lifecycle commands.
///
/// Workflow creation is a user action, not a consequence
/// of opening an application view.
///
/// CLI application composition supplies SDK-backed actions.
/// No SQLite implementation or state machine is imported here.
final class WorkflowCliModule implements RudraCliModule {
  /// Creates a workflow module with injected application services.
  WorkflowCliModule({
    required this.working_directory,
    required this.start_workflow,
    required this.stop_workflow,
    required this.output,
    required this.error_output,
  });

  /// Default target-native workflow root.
  final TargetPath working_directory;

  /// SDK-backed explicit workflow-start operation.
  final Future<WorkflowSnapshot> Function(TargetPath) start_workflow;

  /// SDK-backed explicit workflow-stop operation.
  final Future<String> Function() stop_workflow;

  /// Output destination supplied by application composition.
  final StringSink output;

  /// Destination for expected workflow command diagnostics.
  final StringSink error_output;

  @override
  String get module_id => 'rudra.product.workflow';

  @override
  Iterable<Command<int>> create_commands() {
    return [
      _WorkflowCommand(
        working_directory: working_directory,
        start_workflow: start_workflow,
        stop_workflow: stop_workflow,
        output: output,
        error_output: error_output,
      ),
    ];
  }
}

/// Groups explicit workflow actions under `rudra workflow`.
final class _WorkflowCommand extends Command<int> {
  /// Registers explicit start and stop actions.
  _WorkflowCommand({
    required TargetPath working_directory,
    required Future<WorkflowSnapshot> Function(TargetPath) start_workflow,
    required Future<String> Function() stop_workflow,
    required StringSink output,
    required StringSink error_output,
  }) {
    addSubcommand(
      _WorkflowStartCommand(
        working_directory: working_directory,
        start_workflow: start_workflow,
        output: output,
        error_output: error_output,
      ),
    );

    addSubcommand(
      _WorkflowStopCommand(
        stop_workflow: stop_workflow,
        output: output,
        error_output: error_output,
      ),
    );
  }

  @override
  String get name => 'workflow';

  @override
  String get description => 'Manage explicit workflow actions.';
}

/// Explicitly requests terminal commitment of an active workflow.
///
/// The command delegates trusted identity resolution,
/// submission processing, and transactional persistence
/// to application composition.
///
/// No lifecycle outcome is inferred from merely accepting
/// a command submission.
final class _WorkflowStopCommand extends Command<int> {
  /// Creates the explicit workflow-stop action.
  _WorkflowStopCommand({
    required Future<String> Function() stop_workflow,
    required StringSink output,
    required StringSink error_output,
  }) : _stop_workflow = stop_workflow,
       _output = output,
       _error_output = error_output;

  final Future<String> Function() _stop_workflow;
  final StringSink _output;
  final StringSink _error_output;

  @override
  String get name => 'stop';

  @override
  String get description => 'Explicitly stop the active workflow.';

  @override
  String get invocation => 'rudra workflow stop';

  /// Processes the stop action after validating invocation.
  ///
  /// Returns success only after durable terminal commitment.
  /// Expected lifecycle conflicts use the workflow exit code.
  @override
  Future<int> run() async {
    final arguments = argResults?.rest ?? const <String>[];

    if (arguments.isNotEmpty) {
      throw UsageException('Workflow stop does not accept arguments.', usage);
    }

    final String workflow_id;

    try {
      workflow_id = await _stop_workflow();
    } on WorkflowStopRejectedException catch (error) {
      final message = switch (error.code) {
        WorkflowRejectionCode.workflow_not_active =>
          'No active workflow to stop.',
        WorkflowRejectionCode.workflow_id_mismatch =>
          'Active workflow changed before stop completed.',
        WorkflowRejectionCode.ownership_conflict =>
          'Workflow stop rejected due to an ownership conflict.',
      };

      _error_output.writeln(message);

      return RudraExitCode.workflow_conflict.value;
    }

    _output.writeln('Workflow: ENDED  |  ID: $workflow_id');

    return RudraExitCode.success.value;
  }
}

/// Explicitly requests establishment of a persistent workflow.
///
/// The command delegates all processing and restoration to the
/// injected application service. It never constructs lifecycle
/// states, event outcomes, or database adapters.
final class _WorkflowStartCommand extends Command<int> {
  /// Creates a start action bound to one SDK target.
  _WorkflowStartCommand({
    required TargetPath working_directory,
    required Future<WorkflowSnapshot> Function(TargetPath) start_workflow,
    required StringSink output,
    required StringSink error_output,
  }) : _working_directory = working_directory,
       _start_workflow = start_workflow,
       _output = output,
       _error_output = error_output;

  final TargetPath _working_directory;
  final Future<WorkflowSnapshot> Function(TargetPath) _start_workflow;
  final StringSink _output;
  final StringSink _error_output;

  @override
  String get name => 'start';

  @override
  String get description => 'Explicitly start a persistent workflow.';

  @override
  String get invocation => 'rudra workflow start [absolute-directory]';

  /// Validates the requested root before invoking SDK processing.
  ///
  /// A successful result represents a committed, restored
  /// active workflow, not merely an accepted submission.
  @override
  Future<int> run() async {
    final arguments = argResults?.rest ?? const <String>[];

    if (arguments.length > 1) {
      throw UsageException('Expected at most one directory.', usage);
    }

    TargetPath root = _working_directory;

    if (arguments.isNotEmpty) {
      try {
        root = TargetPath(arguments.single);
      } on ArgumentError {
        throw UsageException('Invalid workflow root.', usage);
      }
    }

    if (!root.value.startsWith('/')) {
      throw UsageException('Expected an absolute directory.', usage);
    }

    final WorkflowSnapshot active;

    try {
      active = await _start_workflow(root);
    } on WorkflowAlreadyActiveException catch (error) {
      final identifier = error.workflow_id;

      _error_output.writeln(
        identifier == null
            ? 'Workflow already active.'
            : 'Workflow already active: $identifier',
      );

      return RudraExitCode.workflow_conflict.value;
    }

    _output.writeln(
      'Workflow: ACTIVE'
      '  |  ID: ${active.identity.workflow_id}'
      '  |  Version: ${active.version}'
      '  |  Target: ${active.identity.target_id}',
    );

    return RudraExitCode.success.value;
  }
}
