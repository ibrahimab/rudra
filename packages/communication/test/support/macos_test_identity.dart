import 'dart:io';

/// Resolves the expected effective macOS user identity.
///
/// Uses an independent operating-system command to establish
/// the identity expected from native peer authentication.
///
/// Returns the effective UID in the macOS identity namespace.
///
/// Throws [UnsupportedError] outside macOS or [StateError]
/// when identity resolution fails.
///
/// Example:
/// ```dart
/// final expected_owner = await resolve_macos_test_identity();
/// expect(peer.os_user_id, expected_owner);
/// ```
Future<String> resolve_macos_test_identity() async {
  if (!Platform.isMacOS) {
    throw UnsupportedError('Test identity requires macOS.');
  }

  final result = await Process.run('/usr/bin/id', ['-u']);

  if (result.exitCode != 0) {
    throw StateError('Unable to resolve macOS test identity.');
  }

  final uid = int.tryParse((result.stdout as String).trim());

  if (uid == null || uid < 0) {
    throw StateError('Invalid macOS test identity.');
  }

  return 'macos-uid:$uid';
}
