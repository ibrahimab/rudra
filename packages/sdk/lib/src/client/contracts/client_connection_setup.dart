import 'dart:async';

import 'package:rudra_communication/rudra_communication.dart';

/// Resolves a configured authenticated transport for an SDK connection.
///
/// Each connection attempt invokes this capability independently,
/// allowing trusted composition to resolve updated endpoint and
/// authentication configuration.
///
/// Returns a transport ready for communication establishment.
///
/// Transport construction must retain configuration without
/// establishing connections or acquiring native resources.
///
/// Configuration and platform-resolution failures propagate.
///
/// Example:
/// ```dart
/// final ClientConnectionSetup setup = () async {
///   return MacOsUnixTransport(
///     scope_directory: await resolve_host_scope(),
///     os_user_id: await resolve_trusted_owner(),
///   );
/// };
/// ```
typedef ClientConnectionSetup = FutureOr<Transport> Function();
