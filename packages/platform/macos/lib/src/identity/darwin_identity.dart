import 'dart:ffi';
import 'dart:io';

/// Resolves the effective UID of the current macOS process through Darwin.
///
/// Throws [UnsupportedError] outside macOS. Binding failures propagate.
///
/// Example:
/// ```dart
/// final uid = macos_effective_uid();
/// print(macos_user_id(uid));
/// ```
int macos_effective_uid() {
  if (!Platform.isMacOS) {
    throw UnsupportedError('Rudra native identities require macOS.');
  }
  return _geteuid();
}

/// Native effective user identity lookup.
final _geteuid = DynamicLibrary.process()
    .lookupFunction<Uint32 Function(), int Function()>('geteuid');

/// Formats a trusted [uid] in the shared host and peer identity namespace.
String macos_user_id(int uid) => 'macos-uid:$uid';
