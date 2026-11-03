@TestOn('mac-os')

import 'dart:io';

import 'package:rudra_target_contracts/rudra_target_contracts.dart';
import 'package:rudra_target_macos/rudra_target_macos.dart';
import 'package:test/test.dart';

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
