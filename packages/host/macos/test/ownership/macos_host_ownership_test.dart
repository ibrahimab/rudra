import 'dart:convert';
import 'dart:io';

import 'package:rudra_host_macos/rudra_host_macos.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies Darwin ownership acquisition and process-level release.
///
/// Tests use private temporary directories and independent native
/// descriptors. Cross-process tests execute a separate Dart process.
void main() {
  const provider = MacOsHostOwnershipProvider();

  const process_timeout = Duration(seconds: 30);

  late Directory directory;

  group('MacOsHostOwnershipProvider', () {
    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'rudra-native-ownership-',
      );
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    /// Acquires ownership of the canonical test directory.
    ///
    /// Returns the native ownership lease.
    Future<HostOwnershipLease> acquire() async => provider.acquire(
      scope_directory: await directory.resolveSymbolicLinks(),
    );

    test('rejects competing ownership and permits reacquisition', () async {
      final first = await acquire();

      try {
        await expectLater(acquire(), throwsA(isA<HostAlreadyOwnedException>()));
      } finally {
        await first.release();
      }

      final second = await acquire();
      await second.release();
    });

    test('release retains the lock file', () async {
      final lease = await acquire();

      final lock_file = File(
        '${directory.path}/'
        '${MacOsHostOwnershipProvider.lock_filename}',
      );

      try {
        expect(await lock_file.exists(), isTrue);
      } finally {
        await lease.release();
      }

      expect(await lock_file.exists(), isTrue);
    });

    test('repeated release has no additional effect', () async {
      final first = await acquire();
      await first.release();

      final second = await acquire();

      try {
        // A previously released lease must not accidentally
        // close a descriptor reused by the subsequent owner.
        await first.release();

        await expectLater(acquire(), throwsA(isA<HostAlreadyOwnedException>()));
      } finally {
        await second.release();
      }
    });

    test('rejects a symbolic link at the lock location', () async {
      final target = File('${directory.path}/unrelated');

      await target.writeAsString('unchanged');

      final link = Link(
        '${directory.path}/'
        '${MacOsHostOwnershipProvider.lock_filename}',
      );

      await link.create(target.path);

      await expectLater(acquire(), throwsA(isA<FileSystemException>()));

      expect(await target.readAsString(), 'unchanged');
    });

    for (final forced in [false, true]) {
      test(
        forced
            ? 'process termination releases native ownership'
            : 'graceful process exit releases native ownership',
        () async {
          final fixture = File('test/ownership/fixtures/hold_ownership.dart')
              .absolute;

          final process = await Process.start(Platform.resolvedExecutable, [
            fixture.path,
            directory.path,
          ]);

          // Drain diagnostics concurrently to prevent a child
          // process from blocking on a full output pipe.
          final diagnostics = process.stderr.transform(utf8.decoder).join();

          final completion = process.exitCode;

          try {
            final readiness = await process.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .first
                .timeout(process_timeout);

            expect(readiness, 'ready');

            // The competing acquisition occurs in a different
            // OS process from the existing native lock holder.
            await expectLater(
              acquire(),
              throwsA(isA<HostAlreadyOwnedException>()),
            );

            if (forced) {
              expect(process.kill(ProcessSignal.sigkill), isTrue);
            } else {
              await process.stdin.close();
            }

            final status = await completion.timeout(process_timeout);

            if (forced) {
              expect(status, isNot(0));
            } else {
              expect(status, 0);
              expect(await diagnostics, isEmpty);
            }

            // The kernel must permit a fresh acquisition
            // without deleting or repairing the old lock file.
            final replacement = await acquire();

            await replacement.release();
          } finally {
            process.kill(ProcessSignal.sigkill);

            await completion.timeout(process_timeout);
            await diagnostics;
          }
        },
      );
    }
  }, skip: !Platform.isMacOS);
}
