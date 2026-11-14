@TestOn('mac-os')
import 'dart:io';

import 'package:test/test.dart';

import '../lib/src/darwin_lstat.dart';

const int _file_type_mask = 0xF000;
const int _regular_file_type = 0x8000;
const int _directory_type = 0x4000;
const int _symbolic_link_type = 0xA000;
const int _no_such_file_errno = 2;

void main() {
  group('DarwinTimestamp', () {
    test('converts the Unix epoch to UTC', () {
      const timestamp = DarwinTimestamp(seconds: 0, nanoseconds: 0);

      expect(timestamp.to_utc_datetime(), DateTime.utc(1970));
    });

    test('preserves microseconds before the epoch', () {
      const timestamp = DarwinTimestamp(seconds: -1, nanoseconds: 123456789);

      final converted = timestamp.to_utc_datetime();

      expect(converted, isNotNull);
      expect(converted!.isUtc, isTrue);

      // -1 second + 123456789 nanoseconds.
      // Remaining sub-microsecond precision is discarded.
      expect(converted.microsecondsSinceEpoch, -876544);
    });

    test('rejects invalid nanosecond components', () {
      const negative = DarwinTimestamp(seconds: 0, nanoseconds: -1);

      const overflow = DarwinTimestamp(seconds: 0, nanoseconds: 1000000000);

      expect(negative.to_utc_datetime(), isNull);
      expect(overflow.to_utc_datetime(), isNull);
    });

    test('rejects out-of-range timestamps', () {
      const future = DarwinTimestamp(seconds: 8640000000001, nanoseconds: 0);

      const past = DarwinTimestamp(seconds: -8640000000001, nanoseconds: 0);

      expect(future.to_utc_datetime(), isNull);
      expect(past.to_utc_datetime(), isNull);
    });
  });

  group('DarwinLStat', () {
    late Directory fixture;
    late DarwinLStat native;

    setUp(() async {
      fixture = await Directory.systemTemp.createTemp('rudra_lstat_test_');

      native = DarwinLStat();
    });

    tearDown(() async {
      await fixture.delete(recursive: true);
    });

    test('inspects a regular file', () async {
      final file = File('${fixture.path}/example.txt');
      await file.writeAsString('Rudra test data');

      final result = native.inspect(file.path);

      expect(result.mode & _file_type_mask, _regular_file_type);

      expect(result.logical_size_bytes, await file.length());

      expect(result.inode, greaterThan(0));
      expect(result.allocated_blocks, greaterThanOrEqualTo(0));
    });

    test('identifies directories', () {
      final result = native.inspect(fixture.path);

      expect(result.mode & _file_type_mask, _directory_type);
    });

    test('does not follow a symbolic link', () async {
      final file = File('${fixture.path}/original.txt');
      await file.writeAsString('Original');

      final link = Link('${fixture.path}/shortcut');
      await link.create('original.txt');

      final file_stat = native.inspect(file.path);
      final link_stat = native.inspect(link.path);

      expect(link_stat.mode & _file_type_mask, _symbolic_link_type);

      expect(link_stat.inode, isNot(file_stat.inode));
      expect(link_stat.device_id, file_stat.device_id);
    });

    test('inspects a dangling symbolic link', () async {
      final link = Link('${fixture.path}/dangling');
      await link.create('missing-target');

      final result = native.inspect(link.path);

      expect(result.mode & _file_type_mask, _symbolic_link_type);

      expect(result.inode, greaterThan(0));
    });

    test('preserves native missing-file errno', () {
      final path = '${fixture.path}/does-not-exist';

      expect(
        () => native.inspect(path),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.osError?.errorCode,
            'native errno',
            _no_such_file_errno,
          ),
        ),
      );
    });

    test('rejects relative paths', () {
      expect(() => native.inspect('relative/path'), throwsArgumentError);
    });

    test('rejects trailing path separators', () {
      expect(() => native.inspect('${fixture.path}/'), throwsArgumentError);
    });

    test('rejects embedded NUL characters', () {
      expect(
        () => native.inspect('${fixture.path}\u0000other'),
        throwsArgumentError,
      );
    });

    test('matches the macOS stat utility', () async {
      final file = File('${fixture.path}/comparison.txt');
      await file.writeAsString('Independent comparison');

      final observed = native.inspect(file.path);

      final command = await Process.run('/usr/bin/stat', [
        '-f',
        '%d:%i:%z:%b',
        file.path,
      ]);

      expect(command.exitCode, 0);

      final fields = (command.stdout as String)
          .trim()
          .split(':')
          .map(int.parse)
          .toList();

      expect(fields, hasLength(4));

      expect(observed.device_id, fields[0]);
      expect(observed.inode, fields[1]);
      expect(observed.logical_size_bytes, fields[2]);
      expect(observed.allocated_blocks, fields[3]);
    });

    test('reads native access and modification times', () async {
      final file = File('${fixture.path}/timestamps.txt');
      await file.writeAsString('Timestamp test');

      final observed = native.inspect(file.path);

      final command = await Process.run('/usr/bin/stat', [
        '-f',
        '%a:%m',
        file.path,
      ]);

      expect(command.exitCode, 0, reason: '${command.stderr}');

      final fields = (command.stdout as String)
          .trim()
          .split(':')
          .map(int.parse)
          .toList();

      expect(fields, hasLength(2));

      expect(observed.access_time.seconds, fields[0]);
      expect(observed.modification_time.seconds, fields[1]);

      for (final timestamp in [
        observed.access_time,
        observed.modification_time,
      ]) {
        expect(timestamp.nanoseconds, inInclusiveRange(0, 999999999));
      }
    });
  });
}
