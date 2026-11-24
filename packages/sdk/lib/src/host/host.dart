/// Portable host lifecycle and platform capability contracts.
///
/// Exposes the SDK-owned host runtime and the contracts implemented
/// by native host adapters.
library;

/// Trusted operating-system identity resolution.
export 'platform/contracts/host_identity_provider.dart';

/// Portable host execution lifecycle.
export 'runtime/rudra_host.dart';
