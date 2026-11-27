import 'dart:convert';
import 'dart:io';

import 'package:rudra_host/rudra_host.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies Darwin ownership acquisition and process-level release.
///
/// Tests use private temporary directories and independent native
/// descriptors. Cross-process tests execute a separate Dart process.
void main() {
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
    Future<HostOwnershipLease> acquire() async => MacOsHostOwnershipProvider(
      runtime_directory: await directory.resolveSymbolicLinks(),
    ).acquire();

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
        'rudra.lock',
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
        'rudra.lock',
      );

      await link.create(target.path);

      await expectLater(acquire(), throwsA(isA<FileSystemException>()));

      expect(await target.readAsString(), 'unchanged');
    });

    test('rejects missing directories and symbolic directory paths', () async {
      final canonical = await directory.resolveSymbolicLinks();
      final link = Link('$canonical/runtime-link')..createSync(canonical);

      for (final path in ['$canonical/missing', link.path]) {
        await expectLater(
          MacOsHostOwnershipProvider(runtime_directory: path).acquire(),
          throwsA(isA<FileSystemException>()),
        );
      }
      expect(await File('$canonical/rudra.lock').exists(), isFalse);
    });

    test('rejects exposed directory and lock modes', () async {
      final canonical = await directory.resolveSymbolicLinks();
      expect(
        (await Process.run('/bin/chmod', ['0755', canonical])).exitCode,
        0,
      );
      await expectLater(acquire(), throwsA(isA<FileSystemException>()));

      expect(
        (await Process.run('/bin/chmod', ['0700', canonical])).exitCode,
        0,
      );
      final lock = File('$canonical/rudra.lock')..createSync();
      expect(
        (await Process.run('/bin/chmod', ['0644', lock.path])).exitCode,
        0,
      );
      await expectLater(acquire(), throwsA(isA<FileSystemException>()));
    });

    for (final forced in [false, true]) {
      test(
        forced
            ? 'process termination releases native ownership'
            : 'graceful process exit releases native ownership',
        () async {
          final fixture = File(
            'test/ownership/macos/fixtures/hold_ownership.dart',
          ).absolute;

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
