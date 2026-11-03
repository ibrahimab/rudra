@TestOn('mac-os')

import 'dart:io';

import 'package:test/test.dart';

import '../lib/src/darwin_directory_reader.dart';

const int _errno_not_found = 2;

void main() {
  group('DarwinDirectoryReader', () {
    late Directory fixture;
    late DarwinDirectoryReader reader;

    setUp(() async {
      fixture = await Directory.systemTemp.createTemp(
        'rudra_directory_reader_test_',
      );

      reader = DarwinDirectoryReader();
    });

    tearDown(() async {
      await fixture.delete(recursive: true);
    });

    test('enumerates immediate children without recursion', () async {
      final file = File('${fixture.path}/example.txt');
      await file.writeAsString('Rudra');

      final child = Directory('${fixture.path}/child');
      await child.create();

      final nested = File('${child.path}/nested.txt');
      await nested.writeAsString('Nested');

      final link = Link('${fixture.path}/shortcut');
      await link.create('child');

      final cursor = reader.open(fixture.path);
      final names = <String>[];

      try {
        while (true) {
          final name = cursor.next_name();

          if (name == null) {
            break;
          }

          names.add(name);
        }
      } finally {
        cursor.close();
      }

      expect(
        names,
        unorderedEquals([
          'example.txt',
          'child',
          'shortcut',
        ]),
      );

      expect(names, isNot(contains('nested.txt')));
      expect(cursor.is_closed, isTrue);
    });

    test('returns null for an empty directory', () async {
      final empty = Directory('${fixture.path}/empty');
      await empty.create();

      final cursor = reader.open(empty.path);

      try {
        expect(cursor.next_name(), isNull);
      } finally {
        cursor.close();
      }
    });

    test('does not follow a final directory symlink', () async {
      final target = Directory('${fixture.path}/target');
      await target.create();

      final link = Link('${fixture.path}/link');
      await link.create('target');

      expect(
        () => reader.open(link.path),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('rejects a regular file as a directory', () async {
      final file = File('${fixture.path}/regular.txt');
      await file.writeAsString('Not a directory');

      expect(
        () => reader.open(file.path),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('preserves native errors for missing directories', () {
      final missing = '${fixture.path}/missing';

      expect(
        () => reader.open(missing),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.osError?.errorCode,
            'native errno',
            _errno_not_found,
          ),
        ),
      );
    });

    test('rejects relative paths', () {
      expect(
        () => reader.open('relative/directory'),
        throwsArgumentError,
      );
    });

    test('rejects trailing directory separators', () {
      expect(
        () => reader.open('${fixture.path}/'),
        throwsArgumentError,
      );
    });

    test('closes safely and rejects further reads', () {
      final cursor = reader.open(fixture.path);

      cursor.close();
      cursor.close();

      expect(cursor.is_closed, isTrue);

      expect(
        () => cursor.next_name(),
        throwsStateError,
      );
    });

    test('keeps reading an opened directory after rename', () async {
      final directory = Directory('${fixture.path}/original');
      await directory.create();

      final file = File('${directory.path}/example.txt');
      await file.writeAsString('Data');

      final cursor = reader.open(directory.path);

      try {
        // Rename only our owned fixture after the descriptor
        // is opened. Enumeration must use the open descriptor.
        await directory.rename('${fixture.path}/renamed');

        expect(cursor.next_name(), 'example.txt');
        expect(cursor.next_name(), isNull);
      } finally {
        cursor.close();
      }
    });

    test('preserves valid Unicode entry names', () async {
      const filename = 'café-日本語.txt';

      final file = File('${fixture.path}/$filename');
      await file.writeAsString('Unicode');

      final cursor = reader.open(fixture.path);

      try {
        expect(cursor.next_name(), filename);
        expect(cursor.next_name(), isNull);
      } finally {
        cursor.close();
      }
    });
  });
}
