import 'dart:async';
import 'dart:convert';

import 'package:rudra_cli/src/core/rendering/renderer.dart';
import 'package:rudra_cli/src/features/explorer/application/explorer_action_registry.dart';
import 'package:rudra_cli/src/features/explorer/application/explorer_controller.dart';
import 'package:rudra_cli/src/features/explorer/application/explorer_runner.dart';
import 'package:rudra_cli/src/features/explorer/presentation/explorer_view_model.dart';
import 'package:rudra_cli/src/features/explorer/terminal/dart_explorer_terminal_host.dart';
import 'package:rudra_cli/src/features/explorer/terminal/explorer_terminal_device.dart';
import 'package:rudra_cli/src/features/explorer/terminal/explorer_terminal_host.dart';
import 'package:rudra_cli/src/features/explorer/terminal/terminal_key.dart';
import 'package:rudra_cli/src/features/workflow/explorer/workflow_explorer_contribution.dart';
import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/filesystem/messaging/list/filesystem_list_messages.dart';
import 'package:test/test.dart';

import '../../../../../packages/host/test/support/host_test_transport_registry.dart';
import '../../../../../packages/host/test/support/loopback_host_transport.dart';

const _stop = TerminalCharacterKey('x');

void main() {
  test(
    'waits for verified initial state before listing and cancels observation',
    () async {
      final host = await _ControlledHost.connect();
      final explorer = host.controller();
      addTearDown(explorer.dispose);

      expect(host.sdk.synchronization_status, StateSynchronizationStatus.idle);
      final starting = explorer.start();
      await host.subscribed.future;
      expect(host.directories, isEmpty);

      await host.publish('original');
      await starting;

      final view = explorer.view_model(visible_row_limit: 2);
      expect(_statuses(view), contains(contains('ID: original')));
      expect(host.directories, ['/root']);
      await explorer.dispose();
      expect(host.cancelled, 1);
      expect(host.sdk.synchronization_status, StateSynchronizationStatus.idle);
    },
  );

  test(
    'requires a successful render and rejects new state before dispatch',
    () async {
      final host = await _ControlledHost.connect();
      final explorer = host.controller();
      addTearDown(explorer.dispose);
      final starting = explorer.start();
      await host.publish('original');
      await starting;

      final original = explorer.view_model(visible_row_limit: 2);
      expect(await explorer.handle_key(_stop), isTrue);
      expect(host.stops, isEmpty);
      explorer.acknowledge_render(original);

      await host.publish('replacement');
      final replacement = explorer.view_model(visible_row_limit: 2);
      expect(_statuses(replacement), contains(contains('ID: replacement')));
      expect(await explorer.handle_key(_stop), isTrue);
      expect(host.stops, isEmpty);

      final warning = explorer.view_model(visible_row_limit: 2);
      expect(
        _statuses(warning),
        contains('State changed. Please review and try again.'),
      );
      expect(() => explorer.acknowledge_render(replacement), throwsStateError);
      explorer.acknowledge_render(warning);
      expect(host.stops, isEmpty);

      await explorer.handle_key(_stop);
      expect(host.stops.map((request) => request.workflow_id), ['replacement']);
      expect(host.stops.single.idempotency_key, isNotEmpty);
    },
  );

  test(
    'a response waits for a newer observation before enabling shortcuts',
    () async {
      final host = await _ControlledHost.connect();
      final ui = _Terminal();
      final running = ui.run(host);
      await host.publish('original');
      expect(
        _statuses(await ui.next_frame()),
        contains(contains('ID: original')),
      );

      ui.press('x');
      final pending = await ui.next_frame();
      expect(
        _statuses(pending),
        contains('Waiting for updated application state.'),
      );
      expect(_statuses(pending), contains(contains('ID: original')));
      expect(pending.footer.actions.instructions, isEmpty);
      ui.press('x');
      expect(
        _statuses(await ui.next_frame()),
        contains('Waiting for updated application state.'),
      );
      expect(host.stops, hasLength(1));

      // A later publication can skip the intermediate workflow absence.
      await host.publish('replacement');
      final latest = await ui.next_frame();
      expect(_statuses(latest), contains(contains('ID: replacement')));
      expect(latest.footer.actions.instructions, ['X Stop Workflow']);
      expect(host.stops.map((request) => request.workflow_id), ['original']);

      ui.press('x');
      await ui.next_frame();
      expect(host.stops.map((request) => request.workflow_id), [
        'original',
        'replacement',
      ]);
      ui.press('q');
      expect(await running, 0);
      expect(host.cancelled, 1);
    },
  );

  test(
    'coalesces updates during navigation and preserves the committed viewport',
    () async {
      final host = await _ControlledHost.connect();
      final opened = Completer<void>();
      final release = Completer<void>();
      host.before_listing = (directory) async {
        if (directory == '/root/child') {
          opened.complete();
          await release.future;
        }
      };
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final ui = _Terminal();
      final running = ui.run(host);
      await host.publish('initial');
      await ui.next_frame();

      ui.press('\r');
      await opened.future;
      ui.press('\x1b[D\x1b[Bx');
      await host.publish(null);
      await host.publish('replacement');
      expect(ui.frames, hasLength(1));

      release.complete();
      final child = await ui.next_frame();
      expect(_statuses(child), contains(contains('ID: replacement')));
      expect(child.header.explorer.current_directory.value, '/root/child');
      expect(child.header.explorer.history.map((path) => path.value), [
        '/root',
      ]);
      expect(child.directory.selected_index, 0);
      expect(host.stops, isEmpty);

      ui.press('\x1b[B\x1b[B\x1b[B');
      await ui.next_frame();
      await ui.next_frame();
      final scrolled = await ui.next_frame();
      expect(scrolled.directory.selected_index, 3);
      expect(scrolled.directory.first_visible_index, 2);

      await host.publish(null);
      final stopped = await ui.next_frame();
      expect(_statuses(stopped), ['Workflow: NONE']);
      expect(stopped.header.explorer, same(scrolled.header.explorer));
      expect(stopped.directory.selected_index, 3);
      expect(stopped.directory.first_visible_index, 2);
      expect(host.directories, ['/root', '/root/child']);
      expect(ui.frames, hasLength(6));

      ui.press('q');
      expect(await running, 0);
      expect(ui.restored, isTrue);
    },
  );

  test(
    'renders the latest observation once when an admitted action settles',
    () async {
      final host = await _ControlledHost.connect();
      final entered = Completer<void>();
      final release = Completer<void>();
      host.before_stop = () async {
        entered.complete();
        await release.future;
      };
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final ui = _Terminal();
      final running = ui.run(host);
      await host.publish('original');
      final initial = await ui.next_frame();

      ui.press('x');
      await entered.future;
      await host.publish(null);
      await host.publish('replacement');
      ui.press('x\r');
      expect(ui.frames, hasLength(1));

      release.complete();
      final updated = await ui.next_frame();
      expect(_statuses(updated), [contains('ID: replacement')]);
      expect(updated.header.explorer, same(initial.header.explorer));
      expect(updated.footer.actions.instructions, ['X Stop Workflow']);
      expect(host.stops.map((request) => request.workflow_id), ['original']);
      expect(ui.frames, hasLength(2));

      ui.press('q');
      expect(await running, 0);
      expect(host.cancelled, 1);
    },
  );

  for (final exit in ['quit', 'ctrl-c', 'eof', 'signal']) {
    test(
      '$exit settles an admitted action and prevents later renders',
      () async {
        final host = await _ControlledHost.connect();
        final entered = Completer<void>();
        final release = Completer<void>();
        host.before_stop = () async {
          entered.complete();
          await release.future;
        };
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        final ui = _Terminal();
        final running = ui.run(host);
        final result = exit == 'signal'
            ? expectLater(running, throwsA(isA<ExplorerTerminalInterrupted>()))
            : expectLater(running, completion(0));
        await host.publish('original');
        await ui.next_frame();

        ui.press('x');
        await entered.future;
        await host.publish('replacement');
        ui.press('x\r\x1b[B');
        switch (exit) {
          case 'quit':
            ui.press('q');
          case 'ctrl-c':
            ui.press('\x1b[\x03');
          case 'eof':
            await ui.input.close();
          case 'signal':
            ui.input.addError(
              const ExplorerTerminalInterrupted(
                ExplorerTerminalSignal.terminate,
              ),
            );
        }

        expect(ui.restored, isFalse);
        expect(host.cancelled, 0);
        expect(host.sdk.is_connected, isTrue);
        expect(ui.frames, hasLength(1));

        release.complete();
        await result;
        expect(host.stops.map((request) => request.workflow_id), ['original']);
        expect(host.directories, ['/root']);
        expect(ui.frames, hasLength(1));
        expect(ui.restored, isTrue);
        expect(host.cancelled, 1);
      },
    );
  }

  test(
    'loss of observation retains the directory and disables host actions',
    () async {
      final host = await _ControlledHost.connect();
      final ui = _Terminal();
      final running = ui.run(host);
      await host.publish('original');
      final initial = await ui.next_frame();

      await host.disconnect();
      final unavailable = await ui.next_frame();
      expect(_statuses(unavailable), ['Application state: UNAVAILABLE']);
      expect(unavailable.header.explorer, same(initial.header.explorer));
      expect(unavailable.footer.actions.instructions, isEmpty);
      ui.press('\rx');
      expect(_statuses(await ui.next_frame()), [
        'Application state: UNAVAILABLE',
      ]);
      expect(host.directories, ['/root']);
      expect(host.stops, isEmpty);

      ui.press('q');
      expect(await running, 0);
      expect(ui.restored, isTrue);
    },
  );

  test('initial observation failure never enters interactive mode', () async {
    final host = await _ControlledHost.connect();
    final ui = _Terminal();
    final running = ui.run(host);
    final result = expectLater(running, throwsA(anything));
    await host.subscribed.future;
    await host.disconnect();
    await result;
    expect(host.directories, isEmpty);
    expect(ui.frames, isEmpty);
    expect(ui.restored, isFalse);
  });
}

List<String> _statuses(ExplorerViewModel view) =>
    view.header.statuses.map((line) => line.text).toList();

/// Exercises real subscription messaging with independently controlled
/// publication, navigation and Stop response boundaries.
final class _ControlledHost {
  static const _owner = 'fixture-user';
  static const _target = 'fixture-target';
  static const _generation = 'fixture-generation';

  final subscribed = Completer<(MessageSession, String)>();
  final directories = <String>[];
  final stops = <WorkflowStopRequest>[];
  var cancelled = 0;
  var _revision = 0;
  Future<void> Function(String)? before_listing;
  Future<void> Function()? before_stop;
  late final RudraSdk sdk;

  static Future<_ControlledHost> connect() async {
    final host = _ControlledHost();
    final transport = LoopbackHostTransport(os_user_id: _owner);
    final shutdown = Completer<void>();
    final ready = Completer<void>();
    final handlers = RequestHandlerRegistry()
      ..register<StateSubscribeResponse, StateSubscribeRequest>((
        request,
        session,
      ) {
        host.subscribed.complete((session, request.subscription_id));
        return StateSubscribeResponse(
          subscription_id: request.subscription_id,
          generation: _generation,
        );
      })
      ..register<StateUnsubscribeResponse, StateUnsubscribeRequest>((
        request,
        _,
      ) {
        host.cancelled++;
        return StateUnsubscribeResponse(
          subscription_id: request.subscription_id,
        );
      })
      ..register<FilesystemListOpenResponse, FilesystemListOpenRequest>((
        request,
        _,
      ) async {
        final directory = request.directory.value;
        host.directories.add(directory);
        await host.before_listing?.call(directory);
        return FilesystemListOpenResponse(
          inspection_id: request.inspection_id,
          target_id: _target,
        );
      })
      ..register<FilesystemListBatchResponse, FilesystemListNextRequest>((
        request,
        _,
      ) {
        final entries = host.directories.last == '/root'
            ? [
                FilesystemEntry(
                  path: TargetPath('/root/child'),
                  kind: FilesystemEntryKind.directory,
                  metadata: FilesystemMetadata(),
                ),
              ]
            : List.generate(
                5,
                (index) => FilesystemEntry(
                  path: TargetPath('/root/child/file-$index'),
                  kind: FilesystemEntryKind.regularFile,
                  metadata: FilesystemMetadata(),
                ),
              );
        return FilesystemListBatchResponse(
          inspection_id: request.inspection_id,
          sequence: request.sequence,
          status: FilesystemListBatchStatus.complete,
          entries: entries,
          issues: const [],
        );
      })
      ..register<WorkflowStopResponse, WorkflowStopRequest>((request, _) async {
        host.stops.add(request);
        await host.before_stop?.call();
        return WorkflowStopResponse(
          outcome: WorkflowOperationResolved(
            resolution: WorkflowSubmissionResolution(
              receipt: EventSubmissionReceipt(
                event_id: 'stop-event',
                correlation_id: request.idempotency_key,
              ),
              state: WorkflowSubmissionState.completed,
              committed_outcome: WorkflowCommittedOutcome(
                workflow_id: request.workflow_id,
                event_type: WorkflowEndedEvent.type_id,
                version: 2,
                sequence: 2,
              ),
            ),
          ),
        );
      });
    final communication = Communication(
      codecs: create_application_message_codecs(),
      handlers: handlers,
      transport_registry: host_test_transport_registry(transport),
    );
    final serving = communication.run(
      shutdown: shutdown.future,
      on_startup: () async => ready.complete(),
    );
    serving.ignore();
    addTearDown(() async {
      shutdown.complete();
      await serving;
    });
    await Future.any([ready.future, serving]);
    host.sdk = RudraSdk();
    addTearDown(host.sdk.close);
    await host.sdk.connect(ConnectionParams(transport: transport));
    return host;
  }

  ExplorerController controller() => ExplorerController(
    sdk: sdk,
    starting_directory: TargetPath('/root'),
    action_registry: ExplorerActionRegistry([
      WorkflowExplorerContribution(sdk.workflows),
    ]),
  );

  /// Publishes the supplied workflow identity or verified absence. Returns
  /// after the SDK accepts the publication on the authenticated connection.
  Future<void> publish(String? workflow_id) async {
    final (session, subscription_id) = await subscribed.future;
    final response = await session.request(
      StateDeliveryRequest(
        subscription_id: subscription_id,
        publication: StatePublicationSnapshot(
          generation: _generation,
          revision: ++_revision,
          state: RudraState(
            workflows: WorkflowsState(
              current_workflow: workflow_id == null
                  ? null
                  : WorkflowSnapshot(
                      identity: WorkflowIdentity(
                        workflow_id: workflow_id,
                        os_user_id: _owner,
                        target_id: _target,
                        root: TargetPath('/root'),
                      ),
                      version: 1,
                      lifecycle: WorkflowLifecycle(
                        id: 'rudra.workflow.active',
                        is_terminal: false,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
    expect(response.revision, _revision);
  }

  Future<void> disconnect() async {
    final (session, _) = await subscribed.future;
    await session.close();
  }
}

/// Delivers input synchronously and records frames at renderer boundaries.
final class _Terminal
    implements ExplorerTerminalHost, ViewportRenderer<ExplorerViewModel> {
  final input = StreamController<List<int>>(sync: true);
  final _rendered = StreamController<ExplorerViewModel>();
  late final _reader = StreamIterator(_rendered.stream);
  final frames = <ExplorerViewModel>[];
  var restored = false;

  Future<int> run(_ControlledHost host) {
    addTearDown(() async {
      input.close().ignore();
      await _reader.cancel();
      _rendered.close().ignore();
    });
    final runner = ExplorerRunner(
      controller: host.controller(),
      terminal: this,
      renderer: this,
      error_output: StringBuffer(),
    );
    return runner.run()..ignore();
  }

  void press(String keys) => input.add(ascii.encode(keys));

  Future<ExplorerViewModel> next_frame() async {
    expect(await _reader.moveNext(), isTrue);
    return _reader.current;
  }

  @override
  void render(ExplorerViewModel view_model) {
    expect(restored, isFalse);
    frames.add(view_model);
    _rendered.add(view_model);
  }

  @override
  Future<T> run_interactive<T>(Future<T> Function() interaction) async {
    try {
      return await interaction();
    } finally {
      restored = true;
    }
  }

  @override
  bool get is_interactive => true;
  @override
  int get terminal_columns => 100;
  @override
  int get fixed_rows => 7;
  @override
  int get terminal_rows => fixed_rows + 3;
  @override
  Stream<List<int>> get input_bytes => input.stream;
  @override
  StringSink get output => StringBuffer();
}
