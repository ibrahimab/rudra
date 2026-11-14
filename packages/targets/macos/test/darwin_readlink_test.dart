@TestOn('mac-os')
import 'dart:io';

import 'package:test/test.dart';

import '../lib/src/darwin_readlink.dart';

// Independent Darwin errno expectations.
// Tests deliberately do not import implementation constants.
const int _errno_not_found = 2;
const int _errno_invalid_argument = 22;

// Exercise the boundary of the reader's initial allocation.
// These values are test fixtures, not production configuration.
const int _initial_buffer_boundary_bytes = 256;
const int _expanded_target_length_bytes = 600;

void main() {
  group('DarwinReadLink', () {
    late Directory fixture;
    late DarwinReadLink reader;

    setUp(() async {
      fixture = await Directory.systemTemp.createTemp('rudra_readlink_test_');

      reader = DarwinReadLink();
    });

    tearDown(() async {
      await fixture.delete(recursive: true);
    });

    test('preserves relative symbolic-link targets', () async {
      const target = '../cache/../missing-file.txt';

      final link = Link('${fixture.path}/relative-link');
      await link.create(target);

      final observed = reader.read_target(link.path);

      expect(observed, target);
    });

    test('preserves absolute symbolic-link targets', () async {
      final target = '${fixture.path}/nonexistent-target';

      final link = Link('${fixture.path}/absolute-link');
      await link.create(target);

      expect(reader.read_target(link.path), target);
    });

    test('reads dangling symbolic links', () async {
      const target = 'target-that-does-not-exist';

      final link = Link('${fixture.path}/dangling-link');
      await link.create(target);

      // readlink must return the stored destination without
      // requiring the destination to exist.
      expect(reader.read_target(link.path), target);

      expect(await File('${fixture.path}/$target').exists(), isFalse);
    });

    test('reads self-referencing links without following them', () async {
      final link = Link('${fixture.path}/self-reference');
      await link.create('self-reference');

      // A path-resolution API would encounter a loop here.
      // Native readlink must simply return the stored bytes.
      expect(reader.read_target(link.path), 'self-reference');
    });

    test('preserves Unicode link targets', () async {
      const target = '../café/日本語/über.txt';

      final link = Link('${fixture.path}/unicode-link');
      await link.create(target);

      expect(reader.read_target(link.path), target);
    });

    test('handles a target exactly filling the initial buffer', () async {
      // The reader must not assume that a full buffer means
      // a complete result. It must retry with more capacity.
      final target = List<String>.filled(
        _initial_buffer_boundary_bytes,
        'x',
      ).join();

      final link = Link('${fixture.path}/boundary-link');
      await link.create(target);

      final observed = reader.read_target(link.path);

      expect(observed, target);
      expect(observed.length, _initial_buffer_boundary_bytes);
    });

    test('grows the buffer for longer link targets', () async {
      final target = List<String>.filled(
        _expanded_target_length_bytes,
        'y',
      ).join();

      final link = Link('${fixture.path}/long-link');
      await link.create(target);

      final observed = reader.read_target(link.path);

      expect(observed, target);
      expect(observed.length, _expanded_target_length_bytes);
    });

    test('rejects regular files with native EINVAL', () async {
      final file = File('${fixture.path}/regular.txt');
      await file.writeAsString('Not a link');

      expect(
        () => reader.read_target(file.path),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.osError?.errorCode,
            'native errno',
            _errno_invalid_argument,
          ),
        ),
      );
    });

    test('rejects directories with native EINVAL', () {
      expect(
        () => reader.read_target(fixture.path),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.osError?.errorCode,
            'native errno',
            _errno_invalid_argument,
          ),
        ),
      );
    });

    test('preserves native ENOENT for missing links', () {
      final missing = '${fixture.path}/missing-link';

      expect(
        () => reader.read_target(missing),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.osError?.errorCode,
            'native errno',
            _errno_not_found,
          ),
        ),
      );
    });

    test('rejects relative input paths', () {
      expect(() => reader.read_target('relative/link'), throwsArgumentError);
    });

    test('rejects trailing path separators', () {
      expect(() => reader.read_target('${fixture.path}/'), throwsArgumentError);
    });

    test('rejects embedded NUL characters', () {
      final invalid = '${fixture.path}/link\u0000other';

      expect(() => reader.read_target(invalid), throwsArgumentError);
    });
  });
}
