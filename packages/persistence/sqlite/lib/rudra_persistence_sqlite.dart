/// SQLite persistence implementations for Rudra.
///
/// Provides concrete Drift-backed adapters for the
/// platform-independent persistence contracts in Rudra SDK.
///
/// Application composition constructs these adapters and
/// injects them into SDK services.
///
/// The SDK does not depend on this package.
library;

export 'src/sqlite_persistence.dart';
