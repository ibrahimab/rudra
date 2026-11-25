import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:rudra_communication/rudra_communication.dart';
import 'package:test/test.dart';

import '../support/macos_test_identity.dart';
import 'fixtures/echo_messages.dart';

/// Verifies the complete public communication API across
/// independently executing operating-system processes.
void main() {
  const operation_timeout = Duration(seconds: 30);

  late Directory directory;
  late String scope;
  late String owner;
  late File fixture;

  group(
    'Native cross-process communication',
    () {
      setUp(() async {
        directory = await Directory('/tmp').createTemp('rudra-native-');

        addTearDown(() async {
          await directory.delete(recursive: true);
        });

        scope = await directory.resolveSymbolicLinks();
        owner = await resolve_macos_test_identity();

        final package_uri = await Isolate.resolvePackageUri(
          Uri.parse('package:rudra_communication/rudra_communication.dart'),
        );

        if (package_uri == null) {
          throw StateError('Unable to resolve communication package.');
        }

        fixture = File.fromUri(
          package_uri.resolve(
            '../test/integration/fixtures/message_client.dart',
          ),
        );

        expect(
          await fixture.exists(),
          isTrue,
          reason: 'Missing client fixture: ${fixture.path}',
        );
      });

      /// Starts a native listening communication instance.
      ///
      /// [handler] supplies the test's application-specific behavior.
      ///
      /// Returns the communication owner, shutdown notification
      /// and retained server execution result.
      Future<
        ({
          Communication communication,
          Completer<void> shutdown,
          Future<void> running,
        })
      >
      start_server(RequestHandler<EchoResponse, EchoRequest> handler) async {
        final shutdown = Completer<void>();
        final ready = Completer<void>();

        final handlers = RequestHandlerRegistry()
          ..register<EchoResponse, EchoRequest>(handler);

        final communication = Communication(
          codecs: create_echo_codecs(),
          handlers: handlers,
        );

        final running = communication.run(
          scope_directory: scope,
          os_user_id: owner,
          shutdown: shutdown.future,
          on_startup: () async {
            ready.complete();
          },
        );

        running.ignore();

        addTearDown(() async {
          if (!shutdown.isCompleted) {
            shutdown.complete();
          }

          await running.timeout(operation_timeout);
        });

        // Report unsuccessful startup immediately rather than
        // waiting for a readiness notification that cannot arrive.
        await Future.any<void>([
          ready.future,
          running.then<void>((_) {
            throw StateError('Server ended before readiness.');
          }),
        ]).timeout(operation_timeout);

        return (
          communication: communication,
          shutdown: shutdown,
          running: running,
        );
      }

      /// Launches an independent Dart process for [scenario].
      ///
      /// [label] distinguishes the client's application requests.
      ///
      /// Returns the process and its retained execution result.
      Future<_ClientProcess> start_client(String scenario, String label) async {
        final process = await Process.start(Platform.resolvedExecutable, [
          fixture.path,
          scope,
          owner,
          scenario,
          label,
        ]);

        final client = _ClientProcess(process);

        addTearDown(() async {
          if (!client.has_exited) {
            process.kill(ProcessSignal.sigkill);
          }

          await client.result.timeout(operation_timeout);
        });

        return client;
      }

      /// Processes an authenticated [request] over [session].
      ///
      /// Returns a nested response obtained from the requesting
      /// process or throws a controlled application failure.
      Future<EchoResponse> exchange(
        EchoRequest request,
        MessageSession session,
      ) async {
        expect(session.os_user_id, owner);

        if (request.value == 'fail') {
          throw StateError('Private application diagnostics.');
        }

        final response = await session.request(EchoRequest(request.value));

        return EchoResponse('host:${response.value}');
      }

      /// Waits for the application handler represented by [entered].
      ///
      /// [client] identifies the process expected to invoke it.
      ///
      /// Returns the executing session or reports premature
      /// child process termination with its captured diagnostics.
      Future<MessageSession> await_admission(
        Completer<MessageSession> entered,
        _ClientProcess client,
      ) {
        return Future.any<MessageSession>([
          entered.future,
          client.result.then<MessageSession>((result) {
            throw StateError(
              'Client exited before handler admission: '
              '${result.status}\n${result.diagnostics}',
            );
          }),
        ]).timeout(operation_timeout);
      }

      test('exchanges nested messages across concurrent processes', () async {
        final arrived = <String>{};
        final sessions = <MessageSession>{};
        final both_entered = Completer<void>();

        final server = await start_server((request, session) async {
          if (request.value == 'first' || request.value == 'second') {
            arrived.add(request.value);
            sessions.add(session);

            if (arrived.length == 2 && !both_entered.isCompleted) {
              both_entered.complete();
            }

            // Neither client's first request may finish until
            // both independent processes have entered their handlers.
            await both_entered.future;
          }

          return exchange(request, session);
        });

        try {
          final first = await start_client('exchange', 'first');
          final second = await start_client('exchange', 'second');

          expect(first.process.pid, isNot(pid));
          expect(second.process.pid, isNot(pid));
          expect(first.process.pid, isNot(second.process.pid));

          final results = await Future.wait([first.result, second.result])
              .timeout(operation_timeout);

          expect(arrived, {'first', 'second'});
          expect(sessions.length, 2);

          expect(results[0].status, 0, reason: results[0].diagnostics);

          expect(results[1].status, 0, reason: results[1].diagnostics);

          expect(results[0].output, 'EXCHANGED:first\nRELEASED\n');

          expect(results[1].output, 'EXCHANGED:second\nRELEASED\n');

          expect(server.communication.resources_released, isFalse);
        } finally {
          if (!both_entered.isCompleted) {
            both_entered.complete();
          }
        }
      });

      test('isolates abrupt client process termination', () async {
        final entered = Completer<MessageSession>();
        final release = Completer<void>();
        final finished = Completer<void>();

        final server = await start_server((request, session) async {
          if (request.value != 'hold') {
            return exchange(request, session);
          }

          entered.complete(session);

          try {
            await release.future;

            return const EchoResponse('completed');
          } finally {
            finished.complete();
          }
        });

        try {
          final abandoned = await start_client('hold', 'abandoned');

          final session = await await_admission(entered, abandoned);

          expect(abandoned.process.kill(ProcessSignal.sigkill), isTrue);

          final terminated = await abandoned.result.timeout(operation_timeout);

          expect(terminated.status, isNot(0));

          await session.done.timeout(operation_timeout);

          // Process termination closes communication but does
          // not cancel application work already admitted.
          expect(finished.isCompleted, isFalse);

          final healthy = await start_client('exchange', 'healthy');

          final result = await healthy.result.timeout(operation_timeout);

          expect(result.status, 0, reason: result.diagnostics);

          expect(result.output, 'EXCHANGED:healthy\nRELEASED\n');

          expect(server.communication.resources_released, isFalse);

          release.complete();

          await finished.future.timeout(operation_timeout);
        } finally {
          if (!release.isCompleted) {
            release.complete();
          }
        }
      });

      test('host shutdown waits for admitted application handlers', () async {
        final entered = Completer<MessageSession>();
        final release = Completer<void>();

        final server = await start_server((request, session) async {
          entered.complete(session);

          await release.future;

          return const EchoResponse('completed');
        });

        try {
          final client = await start_client('hold', 'shutdown');

          final session = await await_admission(entered, client);

          server.shutdown.complete();

          await session.done.timeout(operation_timeout);

          final result = await client.result.timeout(operation_timeout);

          expect(result.status, 0, reason: result.diagnostics);

          expect(result.output, 'DISCONNECTED\nRELEASED\n');

          // The client has completely released its communication
          // resources, but the server still owns application work.
          expect(server.communication.resources_released, isFalse);

          release.complete();

          await server.running.timeout(operation_timeout);

          await server.communication.done.timeout(operation_timeout);

          expect(server.communication.resources_released, isTrue);

          final socket_path = '$scope/${MacOsUnixTransport.socket_filename}';

          expect(
            await FileSystemEntity.type(socket_path, followLinks: false),
            FileSystemEntityType.notFound,
          );
        } finally {
          if (!release.isCompleted) {
            release.complete();
          }
        }
      });
    },
    skip: !Platform.isMacOS,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// Retains the execution result of an independent client process.
///
/// Collects both output streams immediately to avoid blocking
/// the child on unread process output.
final class _ClientProcess {
  /// Observes the supplied independent [process].
  _ClientProcess(this.process) {
    result = _collect_result();

    result.ignore();
  }

  /// Independent operating-system process owned by the test.
  final Process process;

  /// Whether the process has reported termination.
  bool has_exited = false;

  /// Retained execution status, standard output and diagnostics.
  late final Future<({int status, String output, String diagnostics})> result;

  /// Collects process termination and both output streams.
  ///
  /// Returns the complete result after process exit.
  Future<({int status, String output, String diagnostics})>
  _collect_result() async {
    final output = process.stdout.transform(utf8.decoder).join();
    final diagnostics = process.stderr.transform(utf8.decoder).join();

    output.ignore();
    diagnostics.ignore();

    final status = await process.exitCode;

    has_exited = true;

    return (
      status: status,
      output: await output,
      diagnostics: await diagnostics,
    );
  }
}
