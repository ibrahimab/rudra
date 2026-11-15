import 'package:drift/drift.dart';

/// Durable inbox for submitted workflow commands.
///
/// A row records an accepted request, not a successful
/// workflow transition.
///
/// Requests remain pending until an SDK-owned processor
/// records their outcome.
///
/// Ordering is established by [sequence], never timestamps.
/// Idempotency keys are unique within their trusted scope.
class WorkflowSubmissions extends Table {
  /// Monotonically increasing database-local submission position.
  IntColumn get sequence => integer().autoIncrement()();

  /// Stable identity of the accepted event.
  TextColumn get event_id => text().unique()();

  /// Identifier shared with future processing outcomes.
  TextColumn get correlation_id => text()();

  /// Trusted submission scope, not frontend-supplied authority.
  TextColumn get scope_id => text()();

  /// Optional identity of a logical retry.
  TextColumn get idempotency_key => text().nullable()();

  /// Stable typed event identifier.
  TextColumn get event_type => text()();

  /// Serialized immutable command payload.
  TextColumn get payload_json => text()();

  /// Processing obligation, initially pending.
  TextColumn get processing_state =>
      text().withDefault(const Constant('pending'))();

  /// Stable reason recorded for a rejected submission.
  ///
  /// Null for pending and successfully completed commands.
  TextColumn get rejection_code => text().nullable()();

  /// UTC Unix timestamp when a business rejection was committed.
  ///
  /// Null for submissions that have not been rejected.
  IntColumn get rejected_at_unix_ms => integer().nullable()();

  /// UTC acceptance timestamp in Unix milliseconds.
  IntColumn get accepted_at_unix_ms => integer()();

  /// Prevents duplicate logical submissions within a scope.
  ///
  /// SQLite permits multiple NULL idempotency keys.
  @override
  List<Set<Column>> get uniqueKeys => [
    {scope_id, idempotency_key},
  ];

  /// Enforces strict SQLite storage types.
  @override
  bool get isStrict => true;
}
