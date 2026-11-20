/// Identifies one physical key received from a terminal.
///
/// A terminal key describes user input, not application intent.
///
/// Implementations must not encode Rudra operations such as
/// starting a workflow, stopping a workflow, or deleting files.
///
/// Application components interpret physical keys through
/// their own navigation rules or registered action bindings.
///
/// This separation allows new application shortcuts to be
/// introduced without modifying terminal decoding.
///
/// Example:
/// ```dart
/// const key = TerminalCharacterKey('s');
///
/// // The decoder knows only that the user pressed S.
/// // A registered action decides what S means.
/// ```
abstract interface class TerminalKey {}

/// Identifies a supported non-printable terminal key.
///
/// Values represent physical input after ANSI escape-sequence
/// decoding. They do not represent application commands.
///
/// Arrow keys are separated from printable shortcuts so
/// applications can reserve navigation independently.
///
/// [interrupt] represents a raw ETX byte received through
/// terminal input. OS-delivered SIGINT remains the
/// responsibility of the terminal host.
enum TerminalSpecialKey implements TerminalKey {
  /// The terminal's Up arrow.
  up,

  /// The terminal's Down arrow.
  down,

  /// The terminal's Left arrow.
  left,

  /// Enter, represented by either CR or LF.
  enter,

  /// Backspace, represented by BS or DEL.
  backspace,

  /// Raw Ctrl+C represented by ETX.
  interrupt,
}

/// Represents one printable ASCII character.
///
/// The original character and its case are preserved.
/// Shortcut normalization belongs to the action registry,
/// not to the terminal decoder.
///
/// This value object supports equality by character so
/// decoded input can be compared deterministically.
///
/// Example:
/// ```dart
/// const lower = TerminalCharacterKey('s');
/// const upper = TerminalCharacterKey('S');
///
/// assert(lower != upper);
/// assert(lower == const TerminalCharacterKey('s'));
/// ```
final class TerminalCharacterKey implements TerminalKey {
  /// Creates a printable character key.
  ///
  /// [character] must contain exactly one character.
  ///
  /// The terminal decoder is responsible for ensuring
  /// that decoded character values belong to the
  /// supported printable input range.
  const TerminalCharacterKey(this.character) : assert(character.length == 1);

  /// Original character received from the terminal.
  final String character;

  /// Compares keys by their original character.
  @override
  bool operator ==(Object other) =>
      other is TerminalCharacterKey && other.character == character;

  /// Hash derived from the original character.
  @override
  int get hashCode => character.hashCode;

  /// Returns a diagnostic representation of this key.
  @override
  String toString() => 'TerminalCharacterKey($character)';
}
