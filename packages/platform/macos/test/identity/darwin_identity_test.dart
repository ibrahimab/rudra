@TestOn('mac-os')
import 'dart:io';

import 'package:rudra_platform_macos/rudra_platform_macos.dart';
import 'package:test/test.dart';

void main() {
  test('native effective UID matches the system identity', () async {
    final id = await Process.run('/usr/bin/id', ['-u']);
    expect(id.exitCode, 0);
    final expected_uid = int.parse((id.stdout as String).trim());
    expect(macos_effective_uid(), expected_uid);
    expect(macos_user_id(expected_uid), 'macos-uid:$expected_uid');
  });
}
