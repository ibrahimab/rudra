import 'dart:io';

import 'package:rudra_host_macos/rudra_host_macos.dart';

/// Acquires native ownership for cross-process integration tests.
///
/// [arguments] contains the private runtime directory.
/// Reports readiness after acquisition and retains ownership
/// until its standard input is closed or the process terminates.
///
/// Example:
/// ```sh
/// dart test/ownership/fixtures/hold_ownership.dart /fixture
/// ```
Future<void> main(List<String> arguments) async {
  final scope = await Directory(arguments.single).resolveSymbolicLinks();

  final provider = MacOsHostOwnershipProvider(runtime_directory: scope);

  final lease = await provider.acquire();

  try {
    // Report readiness only after kernel ownership has been
    // acquired. The parent test can now attempt contention.
    stdout.writeln('ready');
    await stdout.flush();

    // Retain the resource without introducing polling or
    // arbitrary sleep durations into the test protocol.
    await stdin.drain<void>();
  } finally {
    await lease.release();
  }
}
