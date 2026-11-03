/// Platform-independent target contracts for the Rudra SDK.
///
/// This package describes filesystem targets and their capabilities
/// without depending on operating-system implementations, UI frameworks,
/// or native filesystem APIs.
///
/// Target adapters implement the contracts defined by this package.
/// Frontends and the shared SDK consume these contracts rather than
/// directly invoking platform-specific filesystem operations.
///
/// See also:
/// - `TargetDescriptor` for target identification.
/// - `TargetCapability` for supported inspection functionality.
library;

export 'src/target_capability.dart';
export 'src/target_descriptor.dart';
export 'src/target_path.dart';

export 'src/target_inspection_error_code.dart';
export 'src/target_inspection_operation.dart';
export 'src/target_inspection_exception.dart';

export 'src/target_capability_status.dart';
export 'src/target_capabilities.dart';
export 'src/target_inspection_feature.dart';

export 'src/target_inspector.dart';

export 'src/filesystem_entry.dart';
export 'src/filesystem_entry_kind.dart';
export 'src/filesystem_metadata.dart';
export 'src/filesystem_permissions.dart';
export 'src/filesystem_identity.dart';
