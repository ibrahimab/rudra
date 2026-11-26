import 'dart:async';
import 'dart:io';

import 'package:rudra_cli/src/composition/product_sdk_composition.dart';
import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../host/test/support/loopback_host_transport.dart';

/// Runs the real authoritative host with synthetic authenticated IPC.
///
/// Each consumer receives a fresh SDK and the host starts on first connection.
/// The inspector and SQLite connection reside on the host side of messaging.
final class CliHostFixture implements Transport {
  CliHostFixture({
    required this.inspector,
    this.target_id = 'fixture-target',
    this.database_file,
  }) {
    addTearDown(_dispose);
  }

  static const owner = 'test-os-user';
  final TargetInspector inspector;
  final String target_id;
  final File? database_file;

  final _transport = LoopbackHostTransport(os_user_id: owner);
  final _shutdown = Completer<void>();
  Future<void>? _ready;
  Future<void>? _running;
  RudraSqlitePersistence? _persistence;
  Directory? _temporary_directory;

  int connect_count = 0;

  /// Creates a new disconnected frontend for one invocation.
  ProductSdkComposition composition({TargetPath? directory}) =>
      ProductSdkComposition(
        sdk: RudraSdk(target_id: target_id),
        working_directory: directory ?? TargetPath('/fixture'),
        connection_params: ConnectionParams(transport: this),
      );

  /// Runs a verification operation through an independent authenticated SDK.
  Future<T> using_client<T>(Future<T> Function(RudraSdk) operation) async {
    final client = composition();
    try {
      return await operation(await client.connect());
    } finally {
      await client.sdk.close();
    }
  }

  Future<WorkflowSnapshot?> current() => using_client(
    (sdk) async => (await sdk.read_state()).workflows.current_workflow,
  );

  /// Holds the next client's first response after the host has computed it.
  LoopbackResponseBarrier hold_next_response() {
    return _transport.next_response_barrier = LoopbackResponseBarrier();
  }

  @override
  Future<TransportConnection> connect() async {
    connect_count++;
    await (_ready ??= _start());
    return _transport.connect();
  }

  @override
  Future<TransportListener> listen() => _transport.listen();

  Future<void> _start() async {
    final file = database_file ?? await _temporary_database();
    final runtime = WorkflowRuntime.standard();
    final persistence = _persistence = RudraSqlitePersistence(
      database_file: file,
      scope_id: owner,
      runtime: runtime,
    );
    final application = WorkflowApplication(
      runtime: runtime,
      persistence: persistence,
      identity_provider: const _FixtureIdentityProvider(),
      os_user_id: owner,
    );
    final host = RudraHost(
      application: application,
      filesystem_application: FilesystemApplication(
        target_id: target_id,
        inspector: inspector,
      ),
      validate_start: (target, root) {
        if (target != target_id || !root.value.startsWith('/')) {
          throw ArgumentError('Invalid fixture workflow target.');
        }
      },
      communication_factory: ({required codecs, required handlers}) =>
          Communication(
            listening_transports: [this],
            codecs: codecs,
            handlers: handlers,
          ),
    );
    final ready = Completer<void>();
    final running = _running = host.run(
      shutdown: _shutdown.future,
      on_ready: (_) => ready.complete(),
    );
    running.ignore();
    await Future.any([ready.future, running]);
  }

  Future<File> _temporary_database() async {
    final directory = _temporary_directory = await Directory.systemTemp
        .createTemp('rudra-cli-host-');
    return File('${directory.path}/rudra.sqlite');
  }

  Future<void> _dispose() async {
    _shutdown.complete();
    try {
      await _running;
    } finally {
      try {
        await _persistence?.close();
      } finally {
        await _temporary_directory?.delete(recursive: true);
      }
    }
  }
}

final class _FixtureIdentityProvider implements WorkflowIdentityProvider {
  const _FixtureIdentityProvider();

  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final command = submission.command as WorkflowStartEvent;
    return WorkflowIdentity(
      workflow_id: Uuid().v4(),
      os_user_id: CliHostFixture.owner,
      target_id: command.target_id,
      root: command.root,
    );
  }
}
