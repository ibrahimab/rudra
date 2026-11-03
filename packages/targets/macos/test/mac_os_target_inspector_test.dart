@TestOn('mac-os')

import 'dart:io';

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
