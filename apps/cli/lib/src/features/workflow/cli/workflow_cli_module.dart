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
    required this.output,
  });

  /// Default target-native workflow root.
  final TargetPath working_directory;

  /// SDK-backed explicit workflow-start operation.
  final Future<WorkflowActiveState> Function(TargetPath) start_workflow;

  /// Output destination supplied by application composition.
  final StringSink output;

  @override
  String get module_id => 'rudra.product.workflow';

  @override
  Iterable<Command<int>> create_commands() {
    return [
      _WorkflowCommand(
        working_directory: working_directory,
        start_workflow: start_workflow,
        output: output,
      ),
    ];
  }
}

/// Groups explicit workflow actions under `rudra workflow`.
final class _WorkflowCommand extends Command<int> {
  /// Registers the supported workflow-start action.
  _WorkflowCommand({
    required TargetPath working_directory,
    required Future<WorkflowActiveState> Function(TargetPath) start_workflow,
    required StringSink output,
  }) {
    addSubcommand(
      _WorkflowStartCommand(
        working_directory: working_directory,
        start_workflow: start_workflow,
        output: output,
      ),
    );
  }

  @override
  String get name => 'workflow';

  @override
  String get description => 'Manage explicit workflow actions.';
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
    required Future<WorkflowActiveState> Function(TargetPath) start_workflow,
    required StringSink output,
  }) : _working_directory = working_directory,
       _start_workflow = start_workflow,
       _output = output;

  final TargetPath _working_directory;
  final Future<WorkflowActiveState> Function(TargetPath) _start_workflow;
  final StringSink _output;

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

    final active = await _start_workflow(root);

    _output.writeln(
      'Workflow: ACTIVE'
      '  |  ID: ${active.identity.workflow_id}'
      '  |  Version: ${active.version}'
      '  |  Target: ${active.identity.target_id}',
    );

    return RudraExitCode.success.value;
  }
}
