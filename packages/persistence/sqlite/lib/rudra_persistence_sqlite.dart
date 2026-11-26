/// SQLite persistence implementations for Rudra.
///
/// Provides concrete Drift-backed adapters for the
/// platform-independent persistence contracts in Rudra SDK.
///
/// Each host constructs one owner-scoped context with its own SQLite
/// connection and post-commit notification channel. Separate production
/// hosts use the same machine-wide file. Schema setup and durable writes
/// coordinate through SQLite transactions.
///
/// Example:
/// ```dart
/// final persistence = RudraSqlitePersistence(
///   database_file: shared_database,
///   scope_id: trusted_os_user_id,
///   runtime: runtime,
///   require_existing_wal: true,
/// );
/// try {
///   await execute_application(persistence);
/// } finally {
///   await persistence.close();
/// }
/// ```
library;

export 'src/sqlite_persistence.dart';
