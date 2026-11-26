import 'dart:async';

/// Trusted endpoint configuration for an authenticated connection.
///
/// [scope_directory] identifies the configured communication endpoint.
/// [os_user_id] identifies the expected authenticated remote peer.
///
/// Both values originate from trusted application composition rather
/// than application operation payloads.
///
/// Example:
/// ```dart
/// final ClientConnectionConfiguration configuration = (
///   scope_directory: trusted_scope,
///   os_user_id: trusted_owner,
/// );
/// ```
typedef ClientConnectionConfiguration = ({
  String scope_directory,
  String os_user_id,
});

/// Resolves trusted configuration for one outbound SDK connection.
///
/// Returns configuration for the selected host without establishing
/// communication or acquiring ownership of the host.
///
/// Each connection attempt invokes this capability independently,
/// allowing trusted composition to resolve updated endpoint information.
///
/// Configuration and platform-resolution failures propagate.
///
/// Example:
/// ```dart
/// final ClientConnectionSetup setup = () async {
///   return (
///     scope_directory: await resolve_host_scope(),
///     os_user_id: await resolve_trusted_owner(),
///   );
/// };
/// ```
typedef ClientConnectionSetup =
    FutureOr<ClientConnectionConfiguration> Function();
