/// Maximum permitted length of a stable message type identifier.
const int maximum_message_type_id_length = 128;

/// Reserved wire identifier for communication-owned request failures.
const String communication_error_type_id = 'communication.error.v1';

/// Permitted syntax for stable message type identifiers.
final RegExp _message_type_id_pattern = RegExp(r'^[a-z][a-z0-9_.-]*$');

/// Determines whether [type_id] is a valid stable wire identifier.
///
/// Returns true when the identifier satisfies the protocol's syntax
/// and length requirements, including reserved protocol identifiers.
bool is_valid_message_type_id(String type_id) {
  if (type_id.length > maximum_message_type_id_length) {
    return false;
  }

  final match = _message_type_id_pattern.firstMatch(type_id);

  return match != null && match.end == type_id.length;
}

/// Determines whether [type_id] may identify an application message.
///
/// Returns true when the identifier is valid and does not conflict
/// with a communication-owned message type.
bool is_application_message_type_id(String type_id) =>
    is_valid_message_type_id(type_id) && type_id != communication_error_type_id;
