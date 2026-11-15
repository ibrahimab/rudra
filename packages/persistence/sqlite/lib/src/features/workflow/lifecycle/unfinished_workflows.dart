import 'package:drift/drift.dart';

/// Transactional ownership of unfinished workflows.
///
/// Each trusted operating-system user may own at most one
/// unfinished workflow in the coordination database.
///
/// Rows are derived coordination state, not authoritative
/// event history.
///
/// Removing a reservation requires a valid committed
/// terminal workflow transition.
class UnfinishedWorkflows extends Table {
  /// Trusted operating-system user identity.
  TextColumn get os_user_id => text()();

  /// Unique identity of the unfinished workflow.
  TextColumn get workflow_id => text().unique()();

  /// Immutable configured filesystem target.
  TextColumn get target_id => text()();

  /// Original target-native inspection root.
  TextColumn get root_path => text()();

  /// Last committed workflow event version.
  IntColumn get version => integer()();

  /// Guarantees one unfinished workflow per user.
  @override
  Set<Column> get primaryKey => {os_user_id};

  @override
  bool get isStrict => true;
}
