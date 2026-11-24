/// Portable host lifecycle and platform capability contracts.
///
/// Exposes the SDK-owned host runtime and the contracts implemented
/// by native host adapters.
library;

/// Trusted operating-system identity resolution.
export 'platform/contracts/host_identity_provider.dart';

/// Exclusive host persistence ownership contracts.
export 'platform/contracts/host_ownership_provider.dart';
export 'platform/contracts/host_ownership_lease.dart';

/// Portable host execution lifecycle.
export 'runtime/rudra_host.dart';
