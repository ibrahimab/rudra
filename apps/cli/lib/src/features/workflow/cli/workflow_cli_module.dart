import 'package:args/command_runner.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:uuid/uuid.dart';

import '../../../composition/product_sdk_composition.dart';
import '../../../core/cli/rudra_cli_module.dart';
import '../../../core/cli/rudra_exit_code.dart';

/// Registers explicit workflow lifecycle commands.
///
/// Application composition supplies workflow execution and
/// authoritative state-reading capabilities.
///
/// The commands select operation inputs, identify new user intentions,
/// and present durable application outcomes.
final class WorkflowCliModule implements RudraCliModule {
  /// Assembles workflow commands against the invocation's SDK.
  ///
  /// [sdk_composition] supplies the default Start root and opens the shared
  /// session after command arguments have been validated. [output] and
  /// [error_output] receive operation results and diagnostics.
  factory WorkflowCliModule.product({
    required ProductSdkComposition sdk_composition,
    required StringSink output,
    required StringSink error_output,
  }) => WorkflowCliModule(
    working_directory: sdk_composition.working_directory,
    current_workflow: () async {
      final sdk = await sdk_composition.connect();
      return (await sdk.read_state()).workflows.current_workflow;
    },
    start_workflow: (root, idempotency_key) async {
      final sdk = await sdk_composition.connect();
      return sdk.workflows.start(root: root, idempotency_key: idempotency_key);
    },
    // Submit Stop through the session used to select the workflow.
    stop_workflow: (workflow_id, idempotency_key) => sdk_composition
        .sdk
        .workflows
        .stop(workflow_id: workflow_id, idempotency_key: idempotency_key),
    output: output,
    error_output: error_output,
  );

  /// Creates a workflow module with injected application operations.
  ///
  /// [working_directory] supplies the default Start root.
  /// [current_workflow] reads the authoritative workflow selected for Stop.
  /// [start_workflow] starts a workflow with a durable idempotency key.
  /// [stop_workflow] stops a selected workflow with a durable idempotency key.
  ///
  /// [output] receives successful operation results.
  /// [error_output] receives unsuccessful operation diagnostics.
  WorkflowCliModule({
    required this.working_directory,
    required this.current_workflow,
    required this.start_workflow,
    required this.stop_workflow,
    required this.output,
    required this.error_output,
  });

  /// Default target-native workflow root.
  final TargetPath working_directory;

  /// Read-only authoritative workflow selection.
  final Future<WorkflowSnapshot?> Function() current_workflow;

  /// Explicit Start operation receiving a root and idempotency key.
  final Future<WorkflowOperationOutcome> Function(
    TargetPath root,
    String idempotency_key,
  )
  start_workflow;

  /// Explicit Stop operation receiving a workflow ID and idempotency key.
  final Future<WorkflowOperationOutcome> Function(
    String workflow_id,
    String idempotency_key,
  )
  stop_workflow;

  /// Destination for successful operation results.
  final StringSink output;

  /// Destination for unsuccessful operation diagnostics.
  final StringSink error_output;

  /// Stable identifier of the workflow command contribution.
  @override
  String get module_id => 'rudra.product.workflow';

  /// Creates the workflow command group and its lifecycle actions.
  @override
  Iterable<Command<int>> create_commands() {
    return [
      _WorkflowCommand(
        working_directory: working_directory,
        current_workflow: current_workflow,
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
  /// Registers Start and Stop using the supplied application capabilities.
  ///
  /// [working_directory] supplies the default Start root.
  /// [current_workflow] selects an authoritative workflow for Stop.
  /// [start_workflow] executes an identified Start.
  /// [stop_workflow] executes an identified Stop.
  /// [output] receives successful operation results.
  /// [error_output] receives unsuccessful operation diagnostics.
  _WorkflowCommand({
    required TargetPath working_directory,
    required Future<WorkflowSnapshot?> Function() current_workflow,
    required Future<WorkflowOperationOutcome> Function(
      TargetPath root,
      String idempotency_key,
    )
    start_workflow,
    required Future<WorkflowOperationOutcome> Function(
      String workflow_id,
      String idempotency_key,
    )
    stop_workflow,
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
        current_workflow: current_workflow,
        stop_workflow: stop_workflow,
        output: output,
        error_output: error_output,
      ),
    );
  }

  /// Workflow command group identifier.
  @override
  String get name => 'workflow';

  /// Description displayed by the CLI help system.
  @override
  String get description => 'Manage explicit workflow actions.';
}

/// Requests termination of an explicitly selected workflow.
final class _WorkflowStopCommand extends Command<int> {
  /// Creates the Stop action.
  ///
  /// [current_workflow] supplies the authoritative workflow selection.
  /// [stop_workflow] executes Stop for that workflow's captured identity.
  /// [output] receives successful operation results.
  /// [error_output] receives unsuccessful operation diagnostics.
  _WorkflowStopCommand({
    required Future<WorkflowSnapshot?> Function() current_workflow,
    required Future<WorkflowOperationOutcome> Function(
      String workflow_id,
      String idempotency_key,
    )
    stop_workflow,
    required StringSink output,
    required StringSink error_output,
  }) : _current_workflow = current_workflow,
       _stop_workflow = stop_workflow,
       _output = output,
       _error_output = error_output;

  /// Authoritative read-only workflow selection.
  final Future<WorkflowSnapshot?> Function() _current_workflow;

  /// Explicit application operation for the selected workflow.
  final Future<WorkflowOperationOutcome> Function(
    String workflow_id,
    String idempotency_key,
  )
  _stop_workflow;

  /// Destination for successful operation results.
  final StringSink _output;

  /// Destination for unsuccessful operation diagnostics.
  final StringSink _error_output;

  /// Stop command identifier.
  @override
  String get name => 'stop';

  /// Description displayed by the CLI help system.
  @override
  String get description => 'Explicitly stop the active workflow.';

  /// Supported Stop invocation.
  @override
  String get invocation => 'rudra workflow stop';

  /// Selects and requests termination of the current workflow.
  ///
  /// Returns a workflow conflict without submission when no workflow
  /// can be selected.
  ///
  /// Returns success only after the requested workflow's terminal
  /// outcome has been durably confirmed. Invalid usage and unexpected
  /// application failures propagate.
  @override
  Future<int> run() async {
    final arguments = argResults?.rest ?? const <String>[];

    if (arguments.isNotEmpty) {
      throw UsageException('Workflow stop does not accept arguments.', usage);
    }

    final current = await _current_workflow();

    if (current == null) {
      _error_output.writeln('No active workflow to stop.');
      return RudraExitCode.workflow_conflict.value;
    }

    // Capture the intended workflow before dispatching the operation.
    final workflow_id = current.identity.workflow_id;
    final idempotency_key = Uuid().v4();

    final outcome = await _stop_workflow(workflow_id, idempotency_key);

    if (outcome is! WorkflowOperationResolved ||
        outcome.resolution.state != WorkflowSubmissionState.completed) {
      return _report_unsuccessful_outcome(outcome, _error_output);
    }

    final committed = outcome.resolution.committed_outcome!;

    if (committed.workflow_id != workflow_id ||
        committed.event_type != WorkflowEndedEvent.type_id) {
      throw StateError('Stop result contradicts the requested workflow.');
    }

    _output.writeln('Workflow: ENDED  |  ID: ${committed.workflow_id}');

    return RudraExitCode.success.value;
  }
}

/// Requests establishment of a persistent workflow.
final class _WorkflowStartCommand extends Command<int> {
  /// Creates the Start action for the supplied application capability.
  ///
  /// [working_directory] supplies the default root.
  /// [start_workflow] executes an identified Start operation.
  /// [output] receives successful operation results.
  /// [error_output] receives unsuccessful operation diagnostics.
  _WorkflowStartCommand({
    required TargetPath working_directory,
    required Future<WorkflowOperationOutcome> Function(
      TargetPath root,
      String idempotency_key,
    )
    start_workflow,
    required StringSink output,
    required StringSink error_output,
  }) : _working_directory = working_directory,
       _start_workflow = start_workflow,
       _output = output,
       _error_output = error_output;

  /// Default target-native workflow root.
  final TargetPath _working_directory;

  /// Application operation responsible for durable establishment.
  final Future<WorkflowOperationOutcome> Function(
    TargetPath root,
    String idempotency_key,
  )
  _start_workflow;

  /// Destination for successful operation results.
  final StringSink _output;

  /// Destination for unsuccessful operation diagnostics.
  final StringSink _error_output;

  /// Start command identifier.
  @override
  String get name => 'start';

  /// Description displayed by the CLI help system.
  @override
  String get description => 'Explicitly start a persistent workflow.';

  /// Supported Start invocation.
  @override
  String get invocation => 'rudra workflow start [absolute-directory]';

  /// Validates the requested root and executes a new Start operation.
  ///
  /// Returns success only for a durably committed establishment outcome.
  /// Expected conflicts return the workflow-conflict status.
  /// Invalid usage and unexpected application failures propagate.
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

    final idempotency_key = Uuid().v4();
    final outcome = await _start_workflow(root, idempotency_key);

    if (outcome is! WorkflowOperationResolved ||
        outcome.resolution.state != WorkflowSubmissionState.completed) {
      return _report_unsuccessful_outcome(outcome, _error_output);
    }

    final committed = outcome.resolution.committed_outcome!;

    if (committed.event_type != WorkflowStartedEvent.type_id ||
        committed.version != 1) {
      throw StateError('Start result lacks its establishment outcome.');
    }

    _output.writeln(
      'Workflow: STARTED'
      '  |  ID: ${committed.workflow_id}'
      '  |  Version: ${committed.version}',
    );

    return RudraExitCode.success.value;
  }
}

/// Presents an unsuccessful application [outcome] through [error_output].
///
/// Returns the CLI exit status associated with the durable classification.
/// Business rejection and idempotency conflicts use the workflow-conflict
/// status. Pending and quarantined submissions are reported without
/// claiming successful execution.
///
/// Throws [StateError] if a completed operation reaches this boundary.
int _report_unsuccessful_outcome(
  WorkflowOperationOutcome outcome,
  StringSink error_output,
) {
  switch (outcome) {
    case WorkflowOperationIdempotencyConflict():
      error_output.writeln(
        'Workflow operation key conflicts with another request.',
      );
      return RudraExitCode.workflow_conflict.value;

    case WorkflowOperationResolved(:final resolution):
      switch (resolution.state) {
        case WorkflowSubmissionState.completed:
          throw StateError('Unexpected completed workflow operation.');

        case WorkflowSubmissionState.rejected:
          final message = switch (resolution.rejection_code!) {
            WorkflowRejectionCode.ownership_conflict =>
              'Workflow already active.',
            WorkflowRejectionCode.workflow_not_active =>
              'No active workflow to stop.',
            WorkflowRejectionCode.workflow_id_mismatch =>
              'Active workflow changed before stop completed.',
          };

          error_output.writeln(message);
          return RudraExitCode.workflow_conflict.value;

        case WorkflowSubmissionState.pending:
          error_output.writeln(
            'Workflow operation remains pending: '
            '${resolution.receipt.event_id}',
          );
          return RudraExitCode.software_error.value;

        case WorkflowSubmissionState.quarantined:
          error_output.writeln(
            'Workflow operation quarantined: '
            '${resolution.quarantine_code!.name}',
          );
          return RudraExitCode.software_error.value;
      }
  }
}
