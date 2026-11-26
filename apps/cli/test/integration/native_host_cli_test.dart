import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rudra_cli/rudra_cli.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native host and independent CLI processes share authoritative state',
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
      final listing = await cli(['ls', path]);
      expect(listing.exitCode, 0, reason: '${listing.stderr}');
      expect(listing.stdout, contains('$path/fixture.txt'));

      final stopped = await cli(['workflow', 'stop']);
      expect(stopped.exitCode, 0, reason: '${stopped.stderr}');
      expect(stopped.stdout, contains('ID: $first_id'));

      final next = await cli(['workflow', 'start']);
      expect(next.exitCode, 0, reason: '${next.stderr}');
      final next_id = RegExp(r'ID: (\S+)')
          .firstMatch(next.stdout as String)!
          .group(1)!;
      expect(next_id, isNot(first_id));

      // Keep the committed WAL and a stale socket by terminating abruptly.
      expect(first_host.process.kill(ProcessSignal.sigkill), isTrue);
      expect(await first_host.process.exitCode, isNot(0));
      expect(await lock.exists(), isTrue);
      expect(await File('$database-wal').exists(), isTrue);

      final restored_host = await start_host();
      expect(restored_host.readiness, contains('Workflow restored'));
      expect(restored_host.readiness, contains('Workflow ID: $next_id'));
      expect(restored_host.readiness, contains('Workflow version: 1'));

      final restored_stop = await cli(['workflow', 'stop']);
      expect(restored_stop.exitCode, 0, reason: '${restored_stop.stderr}');
      expect(restored_stop.stdout, contains('ID: $next_id'));

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
