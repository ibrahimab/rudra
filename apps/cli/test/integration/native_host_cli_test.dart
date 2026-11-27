import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rudra_cli/rudra_cli.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native host, CLI commands and two Explorers share authoritative state',
    () async {
      final directory = await Directory('/private/tmp')
          .createTemp('rudra-app-');
      addTearDown(() => directory.delete(recursive: true));
      final path = directory.path;
      final database = '$path/rudra.sqlite';
      final endpoint = '$path/rudra.sock';
      final lock = File('$path/rudra.lock');
      await File('$path/fixture.txt').writeAsString('Rudra');

      List<String> arguments(
        List<String> command, {
        String? database_override,
        String? socket_override,
      }) => [
        'run',
        'test/integration/fixtures/isolated_rudra.dart',
        path,
        database_override ?? database,
        socket_override ?? endpoint,
        ...command,
      ];

      Future<ProcessResult> cli(List<String> command) =>
          Process.run(Platform.resolvedExecutable, arguments(command));

      const host_command = ['host', 'start', '--foreground'];
      Future<({Process process, List<String> readiness, Future<String> errors})>
      start_host() async {
        final process = await Process.start(
          Platform.resolvedExecutable,
          arguments(host_command),
        );
        final errors = process.stderr.transform(utf8.decoder).join();
        final readiness = <String>[];
        final ready = Completer<void>();
        final subscription = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              if (ready.isCompleted) return;
              readiness.add(line);
              if (line.startsWith('Host ready (pid: ')) ready.complete();
            });
        addTearDown(() async {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
          await subscription.cancel();
        });

        await Future.any([ready.future, process.exitCode]);
        expect(
          ready.isCompleted,
          isTrue,
          reason: ready.isCompleted ? null : await errors,
        );
        return (process: process, readiness: readiness, errors: errors);
      }

      final first_host = await start_host();
      expect(first_host.readiness, contains('Workflow: NONE'));
      expect(await lock.exists(), isTrue);
      expect(await File(database).exists(), isFalse);

      final first_frontend_database = '$path/explorer-a.sqlite';
      final second_frontend_database = '$path/explorer-b.sqlite';
      final first_explorer = await _ProcessExplorer.start(
        arguments(['explore'], database_override: first_frontend_database),
      );
      final second_explorer = await _ProcessExplorer.start(
        arguments(['explore'], database_override: second_frontend_database),
      );
      await Future.wait([
        first_explorer.wait_for_status('Workflow: NONE'),
        second_explorer.wait_for_status('Workflow: NONE'),
      ]);
      expect(await File(database).exists(), isFalse);

      final competitor = await Process.run(
        Platform.resolvedExecutable,
        arguments(
          host_command,
          database_override: '$path/other.sqlite',
          socket_override: '$path/other.sock',
        ),
      );
      expect(
        competitor.exitCode,
        RudraExitCode.host_conflict.value,
        reason: '${competitor.stderr}',
      );
      expect(
        competitor.stderr,
        contains('Rudra Host already running for user'),
      );
      expect(await File('$path/other.sqlite').exists(), isFalse);
      expect(
        await FileSystemEntity.type('$path/other.sock'),
        FileSystemEntityType.notFound,
      );

      final starts = await Future.wait([
        cli(['workflow', 'start']),
        cli(['workflow', 'start']),
      ]);
      expect(
        starts.map((result) => result.exitCode),
        unorderedEquals([
          RudraExitCode.success.value,
          RudraExitCode.workflow_conflict.value,
        ]),
        reason: starts.map((result) => result.stderr).join('\n'),
      );

      final winner = starts.singleWhere((result) => result.exitCode == 0);
      final first_id = RegExp(r'ID: (\S+)')
          .firstMatch(winner.stdout as String)!
          .group(1)!;
      await Future.wait([
        first_explorer.wait_for_status('ID: $first_id'),
        second_explorer.wait_for_status('ID: $first_id'),
      ]);
      final listing = await cli(['ls', path]);
      expect(listing.exitCode, 0, reason: '${listing.stderr}');
      expect(listing.stdout, contains('$path/fixture.txt'));

      final stopped = await cli(['workflow', 'stop']);
      expect(stopped.exitCode, 0, reason: '${stopped.stderr}');
      expect(stopped.stdout, contains('ID: $first_id'));
      await Future.wait([
        first_explorer.wait_for_status('Workflow: NONE'),
        second_explorer.wait_for_status('Workflow: NONE'),
      ]);

      first_explorer.press('s');
      final next = await second_explorer.wait_for_status('Workflow: ACTIVE');
      final next_id = RegExp(r'ID: (\S+)').firstMatch(next)!.group(1)!;
      expect(next_id, isNot(first_id));
      await first_explorer.wait_for_status('ID: $next_id');

      second_explorer.press('x');
      await Future.wait([
        first_explorer.wait_for_status('Workflow: NONE'),
        second_explorer.wait_for_status('Workflow: NONE'),
      ]);
      first_explorer.press('s');
      final retained = await first_explorer.wait_for_status('Workflow: ACTIVE');
      final retained_id = RegExp(r'ID: (\S+)').firstMatch(retained)!.group(1)!;
      expect(retained_id, isNot(next_id));
      await second_explorer.wait_for_status('ID: $retained_id');
      await first_explorer.quit();
      expect(await File(first_frontend_database).exists(), isFalse);
      expect(await File(second_frontend_database).exists(), isFalse);

      // Keep the committed WAL and a stale socket by terminating abruptly.
      expect(first_host.process.kill(ProcessSignal.sigkill), isTrue);
      expect(await first_host.process.exitCode, isNot(0));
      await second_explorer.wait_for_status('Application state: UNAVAILABLE');
      await second_explorer.quit();
      expect(await lock.exists(), isTrue);
      expect(await File('$database-wal').exists(), isTrue);

      final restored_host = await start_host();
      expect(restored_host.readiness, contains('Workflow restored'));
      expect(restored_host.readiness, contains('Workflow ID: $retained_id'));
      expect(restored_host.readiness, contains('Workflow version: 1'));

      final restored_stop = await cli(['workflow', 'stop']);
      expect(restored_stop.exitCode, 0, reason: '${restored_stop.stderr}');
      expect(restored_stop.stdout, contains('ID: $retained_id'));

      expect(restored_host.process.kill(ProcessSignal.sigterm), isTrue);
      expect(
        await restored_host.process.exitCode,
        0,
        reason: await restored_host.errors,
      );
      expect(
        await FileSystemEntity.type(endpoint),
        FileSystemEntityType.notFound,
      );
      expect(await lock.exists(), isTrue);
    },
    skip: !Platform.isMacOS,
    timeout: Timeout(Duration(minutes: 3)),
  );
}

/// Runs the production Explorer terminal path in a dedicated macOS PTY.
final class _ProcessExplorer {
  _ProcessExplorer(this._process)
    : _errors = _process.stderr.transform(utf8.decoder).join();

  final Process _process;
  final Future<String> _errors;
  late final _output = StreamIterator(
    _process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  bool _exited = false;

  static Future<_ProcessExplorer> start(List<String> arguments) async {
    final process = await Process.start(
      '/usr/bin/script',
      [
        '-e',
        '-q',
        '/dev/null',
        '/bin/sh',
        '-c',
        r'stty rows 24 cols 180 && exec "$@"',
        'rudra-explorer-pty',
        Platform.resolvedExecutable,
        ...arguments,
      ],
      environment: {'TERM': 'xterm-256color'},
    );
    final explorer = _ProcessExplorer(process);
    addTearDown(explorer._dispose);
    return explorer;
  }

  void press(String key) => _process.stdin.write(key);

  Future<String> wait_for_status(String text) async {
    while (await _output.moveNext()) {
      final line = _output.current;
      // Frames use color and cursor controls. Assertions concern visible text.
      final plain = line.replaceAll(RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]'), '');
      if (plain.contains(text)) return plain;
    }
    throw StateError(
      'Explorer exited before displaying $text. ${await _errors}',
    );
  }

  Future<void> quit() async {
    press('q');
    // Drain remaining PTY output before waiting for the process to finish.
    var restored = false;
    while (await _output.moveNext()) {
      restored = restored || _output.current.contains('\x1b[?1049l');
    }
    final code = await _process.exitCode;
    _exited = true;
    expect(code, 0, reason: await _errors);
    expect(restored, isTrue);
  }

  Future<void> _dispose() async {
    if (!_exited) _process.kill(ProcessSignal.sigkill);
    await _process.exitCode;
    await _output.cancel();
    await _process.stdin.close();
  }
}
