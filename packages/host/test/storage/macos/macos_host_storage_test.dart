@TestOn('mac-os')
import 'dart:io';

import 'package:rudra_platform_macos/rudra_platform_macos.dart';
import 'package:test/test.dart';

import '../../../lib/src/storage/macos/macos_host_storage.dart';

void main() {
  late String data;
  late String database;
  late int group;
  late int uid;

  setUp(() async {
    final fixture = await Directory.systemTemp.createTemp('rudra-storage-');
    addTearDown(() => fixture.delete(recursive: true));

    data = await fixture.resolveSymbolicLinks();
    database = '$data/rudra.sqlite';
    await Directory('$data/runtime').create();
    await File(database).writeAsString('isolated data');
    await _chmod('1770', data);
    await _chmod('0750', '$data/runtime');
    await _chmod('0660', database);
    final ownership = DarwinLStat().inspect(data);
    uid = ownership.uid;
    group = ownership.gid;
  });

  Future<File> validate({int? administrator, Set<int>? groups}) =>
      validate_macos_storage(
        data_directory: data,
        administrator_uid: administrator ?? uid,
        resolve_groups: () async => groups ?? {group},
      );

  test(
    'accepts provisioned storage and leaves missing auxiliary files absent',
    () async {
      expect((await validate()).path, database);
      expect(await File('$database-wal').exists(), isFalse);
      expect(await File('$database-shm').exists(), isFalse);

      final wal = File('$database-wal')..createSync();
      await _chmod('0660', wal.path);
      expect((await validate()).path, database);
    },
  );

  test('requires the administrator owner and an authorized group', () async {
    await expectLater(
      validate(administrator: uid + 1),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      validate(groups: {}),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('rejects an extended ACL on the database', () async {
    await _chmod('+a', database, rule: 'everyone allow read');
    await expectLater(validate(), throwsA(isA<FileSystemException>()));
  });

  test('rejects hard links and symbolic auxiliary files', () async {
    final hard_link = '$data/linked';
    final result = await Process.run('/bin/ln', [database, hard_link]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    await expectLater(validate(), throwsA(isA<FileSystemException>()));

    await File(hard_link).delete();
    await Link('$database-wal').create(database);
    await expectLater(validate(), throwsA(isA<FileSystemException>()));
    expect(await File(database).readAsString(), 'isolated data');
  });

  test('rejects an exposed runtime parent or database', () async {
    final runtime = '$data/runtime';
    await _chmod('0770', runtime);
    await expectLater(validate(), throwsA(isA<FileSystemException>()));
    await _chmod('0750', runtime);

    await _chmod('0664', database);
    await expectLater(validate(), throwsA(isA<FileSystemException>()));
  });
}

/// Sets the fixture [path]'s [mode] or installs one ACL [rule].
Future<void> _chmod(String mode, String path, {String? rule}) async {
  final result = await Process.run('/bin/chmod', [
    mode,
    if (rule != null) rule,
    path,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
}
