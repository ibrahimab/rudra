import 'package:test/test.dart';

import '../../tool/src/verify_command.dart';

/// Verifies development verification target resolution.
void main() {
  test('resolves all to the complete workspace', () {
    expect(resolve_verify_target('all'), isNull);
  });

  test('resolves all supported package aliases', () {
    expect(resolve_verify_target('sqlite'), 'rudra_persistence_sqlite');
    expect(resolve_verify_target('sdk'), 'rudra_sdk');
    expect(resolve_verify_target('cli'), 'rudra_cli');
    expect(resolve_verify_target('macos'), 'rudra_target_inspection');
    expect(resolve_verify_target('contracts'), 'rudra_target_contracts');
  });

  test('preserves full workspace package names', () {
    expect(
      resolve_verify_target('rudra_persistence_sqlite'),
      'rudra_persistence_sqlite',
    );
  });

  test('passes unknown names to workspace validation', () {
    expect(resolve_verify_target('unknown'), 'unknown');
  });
}
