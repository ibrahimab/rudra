import 'package:rudra_target_contracts/rudra_target_contracts.dart';

/// Immutable identity and original bindings of an established workflow.
///
/// A workflow retains these values throughout its lifetime, including
/// after reaching a terminal state.
///
/// [workflow_id] uniquely identifies the workflow.
/// [os_user_id] identifies its operating-system user owner.
/// [target_id] identifies its configured filesystem target.
/// [root] is the original inspection root.
///
/// The OS user identity must come from a trusted platform boundary.
/// Constructing this object does not establish that the supplied owner
/// has been authenticated or authorized.
///
/// Paths retain their target-native syntax. This object does not
/// resolve paths or establish filesystem-object identity.
///
/// Example:
/// ```dart
/// final identity = WorkflowIdentity(
///   workflow_id: 'workflow-1',
///   os_user_id: 'user-1',
///   target_id: 'local-macos',
///   root: TargetPath('/Users/example/Downloads'),
/// );
///
/// print(identity.workflow_id);
/// // workflow-1
/// ```
final class WorkflowIdentity {
  /// Creates the immutable identity of an established workflow.
  ///
  /// All identifiers must contain non-whitespace characters.
  /// Their original spelling is preserved.
  ///
  /// Throws [ArgumentError] for blank identifiers.
  ///
  /// This constructor performs no filesystem operations.
  WorkflowIdentity({
    required String workflow_id,
    required String os_user_id,
    required String target_id,
    required this.root,
  })  : workflow_id = _require_identifier(workflow_id, 'workflow_id'),
        os_user_id = _require_identifier(os_user_id, 'os_user_id'),
        target_id = _require_identifier(target_id, 'target_id');

  /// Stable identifier of this workflow.
  final String workflow_id;

  /// Operating-system user who owns the workflow.
  ///
  /// This is an identity reference, not authorization evidence.
  final String os_user_id;

  /// Configured filesystem target of the original workflow.
  final String target_id;

  /// Original inspection root, preserved without normalization.
  final TargetPath root;

  /// Validates an identifier without changing its representation.
  static String _require_identifier(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        name,
        'The identifier must not be blank.',
      );
    }

    return value;
  }
}
