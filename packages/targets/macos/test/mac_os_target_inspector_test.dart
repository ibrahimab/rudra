@TestOn('mac-os')

import 'dart:io';
import 'dart:async';

import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:rudra_target_macos/rudra_target_macos.dart';
import 'package:test/test.dart';

/// Darwin allocation unit used by the independent stat comparison.
const int _darwin_allocation_block_bytes = 512;

/// POSIX mode 0640: owner read/write, group read, others none.
const int _fixture_posix_mode = 0x1A0;

void main() {
  group('MacOsTargetInspector.inspect', () {
    late Directory fixture;
    late MacOsTargetInspector inspector;

    setUp(() async {
      fixture = await Directory.systemTemp.createTemp(
        'rudra_inspector_test_',
      );

      inspector = MacOsTargetInspector();
    });

    tearDown(() async {
      await fixture.delete(recursive: true);
    });

    test('inspects a regular file', () async {
      final file = File('${fixture.path}/regular.txt');
      const content = 'Rudra inspection';

      await file.writeAsString(content);

      final path = TargetPath(file.path);
      final entry = await inspector.inspect(path);

      expect(entry.path, same(path));
      expect(entry.kind, FilesystemEntryKind.regularFile);
      expect(
        entry.metadata.logical_size_bytes,
        await file.length(),
      );
    });

    test('inspects an empty directory', () async {
      final directory = Directory(
        '${fixture.path}/empty',
      );

      await directory.create();

      final entry = await inspector.inspect(
        TargetPath(directory.path),
      );

      expect(entry.kind, FilesystemEntryKind.directory);
    });

    test('does not follow a file symbolic link', () async {
      final file = File('${fixture.path}/original.txt');
      await file.writeAsString('Original');

      final link = Link('${fixture.path}/shortcut');
      await link.create('original.txt');

      final entry = await inspector.inspect(
        TargetPath(link.path),
      );

      expect(entry.kind, FilesystemEntryKind.symbolicLink);
      expect(await link.target(), 'original.txt');
    });

    test('does not follow a directory symbolic link', () async {
      final directory = Directory(
        '${fixture.path}/directory',
      );

      await directory.create();

      final link = Link('${fixture.path}/directory-link');
      await link.create('directory');

      final entry = await inspector.inspect(
        TargetPath(link.path),
      );

      expect(entry.kind, FilesystemEntryKind.symbolicLink);
    });

    test('inspects dangling symbolic links', () async {
      final link = Link('${fixture.path}/dangling');
      await link.create('missing-target');

      final entry = await inspector.inspect(
        TargetPath(link.path),
      );

      expect(entry.kind, FilesystemEntryKind.symbolicLink);
    });

    test('identifies a named pipe as a special entry', () async {
      final pipe_path = '${fixture.path}/named-pipe';

      // Create the FIFO only inside the owned disposable fixture.
      final result = await Process.run(
        '/usr/bin/mkfifo',
        [pipe_path],
      );

      expect(
        result.exitCode,
        0,
        reason: '${result.stderr}',
      );

      final entry = await inspector.inspect(
        TargetPath(pipe_path),
      );

      expect(entry.kind, FilesystemEntryKind.other);
    });

    test('reports missing entries with typed errors', () async {
      final path = TargetPath(
        '${fixture.path}/missing',
      );

      await expectLater(
        inspector.inspect(path),
        throwsA(
          _inspection_error(
            TargetInspectionErrorCode.notFound,
            path,
          ),
        ),
      );
    });

    test('preserves the native failure as cause', () async {
      final path = TargetPath(
        '${fixture.path}/missing',
      );

      await expectLater(
        inspector.inspect(path),
        throwsA(
          isA<TargetInspectionException>().having(
            (error) => error.cause,
            'native cause',
            isA<FileSystemException>(),
          ),
        ),
      );
    });

    test('rejects relative paths', () async {
      final path = TargetPath('relative/file.txt');

      await expectLater(
        inspector.inspect(path),
        throwsA(
          _inspection_error(
            TargetInspectionErrorCode.invalidPath,
            path,
          ),
        ),
      );
    });

    test('rejects trailing path separators', () async {
      final path = TargetPath('${fixture.path}/');

      await expectLater(
        inspector.inspect(path),
        throwsA(
          _inspection_error(
            TargetInspectionErrorCode.invalidPath,
            path,
          ),
        ),
      );
    });

    test('reports non-directory path components', () async {
      final file = File('${fixture.path}/regular.txt');
      await file.writeAsString('Data');

      final path = TargetPath(
        '${file.path}/child',
      );

      await expectLater(
        inspector.inspect(path),
        throwsA(
          _inspection_error(
            TargetInspectionErrorCode.notDirectory,
            path,
          ),
        ),
      );
    });

    test('detects intermediate symbolic-link cycles', () async {
      final link = Link('${fixture.path}/cycle');
      await link.create('cycle');

      final path = TargetPath('${link.path}/child');

      await expectLater(
        inspector.inspect(path),
        throwsA(
          _inspection_error(
            TargetInspectionErrorCode.symbolicLinkLoop,
            path,
          ),
        ),
      );
    });

    test('preserves noncanonical path spelling', () async {
      final file = File('${fixture.path}/example.txt');
      await file.writeAsString('Data');

      final path = TargetPath(
        '${fixture.path}/./example.txt',
      );

      final entry = await inspector.inspect(path);

      expect(entry.path, same(path));
      expect(entry.path.value, path.value);
      expect(entry.kind, FilesystemEntryKind.regularFile);
    });

    test('does not infer effective permissions', () async {
      final file = File('${fixture.path}/example.txt');
      await file.writeAsString('Data');

      final entry = await inspector.inspect(
        TargetPath(file.path),
      );

      // No effective-access probe has been implemented.
      expect(
        entry.metadata.permissions?.effective_readable,
        isNull,
      );

      expect(
        entry.metadata.permissions?.effective_writable,
        isNull,
      );

      expect(
        entry.metadata.permissions?.effective_executable,
        isNull,
      );
    });

    test('reports filesystem-allocated bytes', () async {
      final file = File('${fixture.path}/allocated.txt');
      await file.writeAsString('Rudra allocation test');

      final command = await Process.run(
        '/usr/bin/stat',
        ['-f', '%b', file.path],
      );

      expect(
        command.exitCode,
        0,
        reason: '${command.stderr}',
      );

      final allocated_blocks = int.parse(
        (command.stdout as String).trim(),
      );

      final entry = await inspector.inspect(
        TargetPath(file.path),
      );

      // Compare against the operating system's independent
      // report, not against an assumed APFS allocation size.
      expect(
        entry.metadata.allocated_size_bytes,
        allocated_blocks * _darwin_allocation_block_bytes,
      );

      expect(
        entry.metadata.logical_size_bytes,
        await file.length(),
      );
    });

    test('identifies hard links as the same object', () async {
      final original = File('${fixture.path}/original.txt');
      await original.writeAsString('Shared inode');

      final hard_link_path = '${fixture.path}/hard-link.txt';

      final command = await Process.run(
        '/bin/ln',
        [original.path, hard_link_path],
      );

      expect(
        command.exitCode,
        0,
        reason: '${command.stderr}',
      );

      final original_entry = await inspector.inspect(
        TargetPath(original.path),
      );

      final hard_link_entry = await inspector.inspect(
        TargetPath(hard_link_path),
      );

      final original_identity = original_entry.metadata.identity;
      final hard_link_identity = hard_link_entry.metadata.identity;

      expect(original_identity, isNotNull);
      expect(hard_link_identity, original_identity);

      // Matching identities do not imply that removing one
      // directory entry would reclaim the allocated bytes.
    });

    test('identifies symbolic links independently', () async {
      final original = File('${fixture.path}/original.txt');
      await original.writeAsString('Original data');

      final link = Link('${fixture.path}/symbolic-link');
      await link.create('original.txt');

      final original_entry = await inspector.inspect(
        TargetPath(original.path),
      );

      final link_entry = await inspector.inspect(
        TargetPath(link.path),
      );

      final original_identity = original_entry.metadata.identity;
      final link_identity = link_entry.metadata.identity;

      expect(original_identity, isNotNull);
      expect(link_identity, isNotNull);

      expect(
        link_identity,
        isNot(original_identity),
      );

      expect(
        link_identity!.filesystem_id,
        original_identity!.filesystem_id,
      );

      expect(
        link_entry.kind,
        FilesystemEntryKind.symbolicLink,
      );
    });

    test('reports POSIX mode without inferring access', () async {
      final file = File('${fixture.path}/permissions.txt');
      await file.writeAsString('Permission test');

      // Restrict only this disposable test fixture.
      final command = await Process.run(
        '/bin/chmod',
        ['640', file.path],
      );

      expect(
        command.exitCode,
        0,
        reason: '${command.stderr}',
      );

      final entry = await inspector.inspect(
        TargetPath(file.path),
      );

      final permissions = entry.metadata.permissions;

      expect(permissions, isNotNull);

      expect(
        permissions!.posix_mode,
        _fixture_posix_mode,
      );

      // Mode bits alone do not establish effective access.
      expect(permissions.effective_readable, isNull);
      expect(permissions.effective_writable, isNull);
      expect(permissions.effective_executable, isNull);
    });

    test('reports UTC modification and access timestamps', () async {
      final file = File('${fixture.path}/timestamps.txt');
      await file.writeAsString('Timestamp inspection');

      final entry = await inspector.inspect(
        TargetPath(file.path),
      );

      final command = await Process.run(
        '/usr/bin/stat',
        ['-f', '%a:%m', file.path],
      );

      expect(command.exitCode, 0);

      final seconds =
          (command.stdout as String).trim().split(':').map(int.parse).toList();

      expect(seconds, hasLength(2));

      final accessed_at = entry.metadata.accessed_at;
      final modified_at = entry.metadata.modified_at;

      expect(accessed_at, isNotNull);
      expect(modified_at, isNotNull);

      expect(accessed_at!.isUtc, isTrue);
      expect(modified_at!.isUtc, isTrue);

      const microseconds_per_second = 1000000;

      expect(
        accessed_at.microsecondsSinceEpoch ~/ microseconds_per_second,
        seconds[0],
      );

      expect(
        modified_at.microsecondsSinceEpoch ~/ microseconds_per_second,
        seconds[1],
      );

      // Birthtime support has not been established reliably.
      expect(entry.metadata.created_at, isNull);
    });

    test('reports timestamps for a dangling link itself', () async {
      final link = Link('${fixture.path}/dangling-timestamp');
      await link.create('missing-destination');

      final entry = await inspector.inspect(
        TargetPath(link.path),
      );

      // macOS stat defaults to lstat without -L.
      final command = await Process.run(
        '/usr/bin/stat',
        ['-f', '%a:%m', link.path],
      );

      expect(command.exitCode, 0);

      final seconds =
          (command.stdout as String).trim().split(':').map(int.parse).toList();

      expect(seconds, hasLength(2));
      expect(entry.kind, FilesystemEntryKind.symbolicLink);

      const microseconds_per_second = 1000000;

      expect(
        entry.metadata.accessed_at!.microsecondsSinceEpoch ~/
            microseconds_per_second,
        seconds[0],
      );

      expect(
        entry.metadata.modified_at!.microsecondsSinceEpoch ~/
            microseconds_per_second,
        seconds[1],
      );

      expect(entry.metadata.created_at, isNull);
    });
  });

  group('MacOsTargetInspector.list_directory', () {
    late Directory fixture;
    late MacOsTargetInspector inspector;

    setUp(() async {
      fixture = await Directory.systemTemp.createTemp(
        'rudra_directory_inspector_test_',
      );

      inspector = MacOsTargetInspector();
    });

    tearDown(() async {
      await fixture.delete(recursive: true);
    });

    test('enumerates immediate children without recursion', () async {
      final file = File('${fixture.path}/file.txt');
      await file.writeAsString('Rudra');

      final directory = Directory('${fixture.path}/child');
      await directory.create();

      final nested = File('${directory.path}/nested.txt');
      await nested.writeAsString('Nested');

      final link = Link('${fixture.path}/shortcut');
      await link.create('child');

      final dangling = Link('${fixture.path}/dangling');
      await dangling.create('missing-target');

      final paths = await inspector
          .list_directory(TargetPath(fixture.path))
          .map((path) => path.value)
          .toList();

      expect(
        paths,
        unorderedEquals([
          file.path,
          directory.path,
          link.path,
          dangling.path,
        ]),
      );

      // The nested child must not be discovered.
      expect(paths, isNot(contains(nested.path)));
    });

    test('returns an empty stream for an empty directory', () async {
      final empty = Directory('${fixture.path}/empty');
      await empty.create();

      final paths =
          await inspector.list_directory(TargetPath(empty.path)).toList();

      expect(paths, isEmpty);
    });

    test('defers enumeration until subscription', () async {
      final path = TargetPath(fixture.path);

      // Construct the stream before creating the child.
      final stream = inspector.list_directory(path);

      final file = File('${fixture.path}/created-later.txt');
      await file.writeAsString('Created after stream construction');

      final paths = await stream.toList();

      expect(paths, hasLength(1));
      expect(paths.single.value, file.path);
    });

    test('reports a directory removed before subscription', () async {
      final directory = Directory('${fixture.path}/temporary');
      await directory.create();

      final path = TargetPath(directory.path);
      final stream = inspector.list_directory(path);

      // Remove only our disposable test directory.
      // The stream must discover the removal when subscribed.
      await directory.delete();

      await expectLater(
        stream,
        emitsInOrder([
          emitsError(
            _directory_error(
              TargetInspectionErrorCode.notFound,
              path,
            ),
          ),
          emitsDone,
        ]),
      );
    });

    test('rejects regular files as directories', () async {
      final file = File('${fixture.path}/regular.txt');
      await file.writeAsString('Not a directory');

      final path = TargetPath(file.path);

      await expectLater(
        inspector.list_directory(path),
        emitsInOrder([
          emitsError(
            _directory_error(
              TargetInspectionErrorCode.notDirectory,
              path,
            ),
          ),
          emitsDone,
        ]),
      );
    });

    test('does not follow directory symbolic links', () async {
      final directory = Directory('${fixture.path}/actual');
      await directory.create();

      final link = Link('${fixture.path}/shortcut');
      await link.create('actual');

      final path = TargetPath(link.path);

      await expectLater(
        inspector.list_directory(path),
        emitsInOrder([
          emitsError(
            _directory_error(
              TargetInspectionErrorCode.notDirectory,
              path,
            ),
          ),
          emitsDone,
        ]),
      );
    });

    test('rejects dangling symbolic links', () async {
      final link = Link('${fixture.path}/dangling');
      await link.create('missing-target');

      final path = TargetPath(link.path);

      await expectLater(
        inspector.list_directory(path),
        emitsInOrder([
          emitsError(
            _directory_error(
              TargetInspectionErrorCode.notDirectory,
              path,
            ),
          ),
          emitsDone,
        ]),
      );
    });

    test('reports missing directories with typed errors', () async {
      final path = TargetPath('${fixture.path}/missing');

      await expectLater(
        inspector.list_directory(path),
        emitsInOrder([
          emitsError(
            _directory_error(
              TargetInspectionErrorCode.notFound,
              path,
            ),
          ),
          emitsDone,
        ]),
      );
    });

    test('rejects relative paths and trailing separators', () async {
      final relative = TargetPath('relative/directory');
      final trailing = TargetPath('${fixture.path}/');

      for (final path in [relative, trailing]) {
        await expectLater(
          inspector.list_directory(path),
          emitsInOrder([
            emitsError(
              _directory_error(
                TargetInspectionErrorCode.invalidPath,
                path,
              ),
            ),
            emitsDone,
          ]),
        );
      }
    });

    test('creates a single-subscription stream', () async {
      final stream = inspector.list_directory(
        TargetPath(fixture.path),
      );

      await stream.toList();

      // Reusing the same stream must not silently reopen
      // the directory and create another subscription.
      expect(
        () => stream.listen((_) {}),
        throwsStateError,
      );
    });

    test('preserves the original parent path spelling', () async {
      final directory = Directory('${fixture.path}/child');
      await directory.create();

      final file = File('${directory.path}/example.txt');
      await file.writeAsString('Data');

      // The inspector must not silently canonicalize this path.
      final path = TargetPath('${fixture.path}/./child');

      final paths = await inspector.list_directory(path).toList();

      expect(paths, hasLength(1));
      expect(
        paths.single.value,
        '${path.value}/example.txt',
      );
    });

    test('supports cancellation after the first child', () async {
      // Provide several entries so there is more work to cancel.
      for (var index = 0; index < 16; index++) {
        final file = File('${fixture.path}/entry_$index.txt');
        await file.writeAsString('$index');
      }

      final canceled = Completer<void>();
      var received = 0;

      late final StreamSubscription<TargetPath> subscription;

      subscription = inspector.list_directory(TargetPath(fixture.path)).listen(
        (path) async {
          received++;

          try {
            // Cancel immediately after the first observation.
            // The native cursor must be released by finally.
            await subscription.cancel();

            if (!canceled.isCompleted) {
              canceled.complete();
            }
          } catch (error, stack) {
            if (!canceled.isCompleted) {
              canceled.completeError(error, stack);
            }
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!canceled.isCompleted) {
            canceled.completeError(error, stack);
          }
        },
      );

      await canceled.future.timeout(
        const Duration(seconds: 5),
      );

      expect(received, 1);

      // A new enumeration remains possible after cancellation.
      // This is a functional check, not a direct descriptor-leak
      // measurement.
      final remaining =
          await inspector.list_directory(TargetPath(fixture.path)).toList();

      expect(remaining, hasLength(16));
    });
  });

  group('MacOsTargetInspector.read_symbolic_link', () {
    late Directory fixture;
    late MacOsTargetInspector inspector;

    setUp(() async {
      fixture = await Directory.systemTemp.createTemp(
        'rudra_symbolic_link_inspector_test_',
      );

      inspector = MacOsTargetInspector();
    });

    tearDown(() async {
      await fixture.delete(recursive: true);
    });

    test('preserves relative destinations exactly', () async {
      const target = '../cache/../original.txt';

      final link = Link('${fixture.path}/shortcut');
      await link.create(target);

      final destination = await inspector.read_symbolic_link(
        TargetPath(link.path),
      );

      expect(destination.value, target);
    });

    test('preserves absolute destinations exactly', () async {
      final target = '${fixture.path}/missing-target';

      final link = Link('${fixture.path}/absolute-link');
      await link.create(target);

      final destination = await inspector.read_symbolic_link(
        TargetPath(link.path),
      );

      expect(destination.value, target);
    });

    test('reads dangling symbolic links', () async {
      const target = 'nonexistent-entry';

      final link = Link('${fixture.path}/dangling');
      await link.create(target);

      final destination = await inspector.read_symbolic_link(
        TargetPath(link.path),
      );

      expect(destination.value, target);

      // The destination does not have to exist.
      expect(
        await File('${fixture.path}/$target').exists(),
        isFalse,
      );
    });

    test('does not follow self-referencing links', () async {
      final link = Link('${fixture.path}/self-reference');
      await link.create('self-reference');

      final destination = await inspector.read_symbolic_link(
        TargetPath(link.path),
      );

      // Resolving this link would encounter a cycle.
      // Reading its stored target must succeed.
      expect(destination.value, 'self-reference');
    });

    test('preserves Unicode destinations', () async {
      const target = '../café/日本語/über.txt';

      final link = Link('${fixture.path}/unicode-link');
      await link.create(target);

      final destination = await inspector.read_symbolic_link(
        TargetPath(link.path),
      );

      expect(destination.value, target);
    });

    test('rejects regular files as non-symbolic links', () async {
      final file = File('${fixture.path}/regular.txt');
      await file.writeAsString('Regular file');

      final path = TargetPath(file.path);

      await expectLater(
        inspector.read_symbolic_link(path),
        throwsA(
          _symbolic_link_error(
            TargetInspectionErrorCode.notSymbolicLink,
            path,
          ),
        ),
      );
    });

    test('rejects directories as non-symbolic links', () async {
      final path = TargetPath(fixture.path);

      await expectLater(
        inspector.read_symbolic_link(path),
        throwsA(
          _symbolic_link_error(
            TargetInspectionErrorCode.notSymbolicLink,
            path,
          ),
        ),
      );
    });

    test('reports missing links and preserves the native cause', () async {
      final path = TargetPath('${fixture.path}/missing');

      await expectLater(
        inspector.read_symbolic_link(path),
        throwsA(
          _symbolic_link_error(
            TargetInspectionErrorCode.notFound,
            path,
          ).having(
            (error) => error.cause,
            'native cause',
            isA<FileSystemException>(),
          ),
        ),
      );
    });

    test('rejects invalid macOS input paths', () async {
      final relative = TargetPath('relative/link');
      final trailing = TargetPath('${fixture.path}/');

      for (final path in [relative, trailing]) {
        await expectLater(
          inspector.read_symbolic_link(path),
          throwsA(
            _symbolic_link_error(
              TargetInspectionErrorCode.invalidPath,
              path,
            ),
          ),
        );
      }
    });

    test('reports intermediate symbolic-link cycles', () async {
      final link = Link('${fixture.path}/cycle');
      await link.create('cycle');

      // The final component is "child", so macOS must
      // resolve the cyclic intermediate symbolic link.
      final path = TargetPath('${link.path}/child');

      await expectLater(
        inspector.read_symbolic_link(path),
        throwsA(
          _symbolic_link_error(
            TargetInspectionErrorCode.symbolicLinkLoop,
            path,
          ),
        ),
      );
    });

    test('preserves noncanonical source path spelling', () async {
      const target = '../original.txt';

      final link = Link('${fixture.path}/shortcut');
      await link.create(target);

      final path = TargetPath(
        '${fixture.path}/./shortcut',
      );

      final destination = await inspector.read_symbolic_link(path);

      // Reading a link must not normalize or resolve the
      // stored destination based on the source path.
      expect(destination.value, target);
    });
  });
}

/// Matches an inspection failure using its typed contract fields.
///
/// The diagnostic message and platform-specific cause are
/// deliberately excluded from classification assertions.
Matcher _inspection_error(
  TargetInspectionErrorCode code,
  TargetPath path,
) {
  return isA<TargetInspectionException>()
      .having(
        (error) => error.code,
        'error code',
        code,
      )
      .having(
        (error) => error.operation,
        'operation',
        TargetInspectionOperation.inspect,
      )
      .having(
        (error) => error.path,
        'original path',
        same(path),
      );
}

/// Matches a directory enumeration failure by its public contract.
///
/// The matcher checks the platform-independent error category,
/// the required operation, and the exact original TargetPath.
///
/// Diagnostic text and native errno are deliberately excluded:
/// callers must not depend on operating-system error messages.
///
/// Example:
/// ```dart
/// final matcher = _directory_error(
///   TargetInspectionErrorCode.notFound,
///   TargetPath('/tmp/missing'),
/// );
/// ```
Matcher _directory_error(
  TargetInspectionErrorCode code,
  TargetPath path,
) {
  return isA<TargetInspectionException>()
      .having(
        (error) => error.code,
        'error code',
        code,
      )
      .having(
        (error) => error.operation,
        'operation',
        TargetInspectionOperation.listDirectory,
      )
      .having(
        (error) => error.path,
        'original path',
        same(path),
      );
}

/// Matches a symbolic-link reading failure by its public contract.
///
/// Checks the platform-independent error code, the required
/// operation, and the exact original TargetPath object.
///
/// Native diagnostics and messages are excluded from this matcher
/// because applications must not classify failures by parsing
/// operating-system messages.
///
/// Example:
/// ```dart
/// final matcher = _symbolic_link_error(
///   TargetInspectionErrorCode.notSymbolicLink,
///   TargetPath('/tmp/regular.txt'),
/// );
/// ```
TypeMatcher<TargetInspectionException> _symbolic_link_error(
  TargetInspectionErrorCode code,
  TargetPath path,
) {
  return isA<TargetInspectionException>()
      .having(
        (error) => error.code,
        'error code',
        code,
      )
      .having(
        (error) => error.operation,
        'operation',
        TargetInspectionOperation.readSymbolicLink,
      )
      .having(
        (error) => error.path,
        'original path',
        same(path),
      );
}
