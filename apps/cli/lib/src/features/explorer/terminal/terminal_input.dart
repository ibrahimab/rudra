import 'dart:async';

import 'terminal_key.dart';

/// Decodes raw terminal bytes into physical keyboard input.
///
/// Terminal input arrives as ordered byte chunks. A physical
/// key may occupy multiple bytes, and an ANSI escape sequence
/// may cross multiple chunks.
///
/// Supported input includes:
/// - ANSI CSI and SS3 Up, Down, and Left arrows.
/// - Enter using CR or LF.
/// - Backspace using BS or DEL.
/// - Printable ASCII characters, preserving their case.
/// - Raw Ctrl+C using ETX.
///
/// Unsupported ANSI sequences are ignored.
///
/// The decoder retains no application-level knowledge:
/// - It does not map S or X to workflow operations.
/// - It does not interpret Q as an application exit.
/// - It does not inspect or modify the filesystem.
/// - It does not create or submit workflow events.
/// - It does not configure or restore terminal modes.
///
/// Terminal configuration and restoration belong to
/// ExplorerTerminalHost. Application shortcuts belong
/// to the action registration layer.
///
/// Example:
/// ```dart
/// final input = TerminalInput(
///   source: Stream<List<int>>.fromIterable([
///     [0x1B],
///     [0x5B, 0x41],
///     [0x73],
///   ]),
/// );
///
/// final keys = await input.read_keys().toList();
///
/// // Up arrow followed by the physical character 's'.
/// assert(keys.first == TerminalSpecialKey.up);
/// assert(keys.last == const TerminalCharacterKey('s'));
/// ```
final class TerminalInput {
  /// Creates a decoder using an injected raw byte stream.
  ///
  /// [source] may be a native terminal stream or a
  /// deterministic stream supplied by a test.
  ///
  /// Construction does not subscribe to [source] or
  /// modify terminal settings.
  ///
  /// Each [read_keys] invocation establishes its own
  /// subscription. Consumers should invoke it once
  /// per interactive terminal session.
  const TerminalInput({required Stream<List<int>> source}) : _source = source;

  /// Ordered terminal input chunks supplied by the host.
  final Stream<List<int>> _source;

  /// Emits physical keys in the order they are received.
  ///
  /// Escape-sequence state is retained across input chunks.
  ///
  /// CSI parameter bytes are consumed until a final
  /// command byte is received. Unsupported final commands
  /// produce no key.
  ///
  /// CRLF is treated as one Enter key, including when CR
  /// and LF arrive in separate chunks.
  ///
  /// Incomplete escape sequences at end-of-stream are
  /// discarded without producing an application action.
  ///
  /// Stream errors propagate to the caller unchanged.
  /// The interactive terminal host remains responsible
  /// for restoration after such failures.
  ///
  /// This method performs no application operations.
  ///
  /// Example:
  /// ```dart
  /// final input = TerminalInput(
  ///   source: Stream<List<int>>.value([0x70]),
  /// );
  ///
  /// final keys = await input.read_keys().toList();
  ///
  /// assert(keys.single == const TerminalCharacterKey('p'));
  /// ```
  Stream<TerminalKey> read_keys() async* {
    var state = _EscapeState.idle;
    var previous_was_carriage_return = false;

    await for (final chunk in _source) {
      for (final byte in chunk) {
        // A CRLF sequence represents one Enter key.
        // Preserve this rule across input chunk boundaries.
        if (previous_was_carriage_return && byte == 0x0A) {
          previous_was_carriage_return = false;
          continue;
        }

        previous_was_carriage_return = byte == 0x0D;

        if (state == _EscapeState.prefix) {
          if (byte == 0x5B) {
            state = _EscapeState.csi;
            continue;
          }

          if (byte == 0x4F) {
            state = _EscapeState.ss3;
            continue;
          }

          // Unsupported escape prefixes are discarded.
          // The current byte is still eligible for decoding.
          state = _EscapeState.idle;
        }

        if (state == _EscapeState.csi) {
          // ANSI CSI final bytes occupy 0x40 through 0x7E.
          // Parameter and intermediate bytes are consumed.
          if (byte >= 0x40 && byte <= 0x7E) {
            state = _EscapeState.idle;

            final key = _arrow_key(byte);

            if (key != null) {
              yield key;
            }
          }

          continue;
        }

        if (state == _EscapeState.ss3) {
          state = _EscapeState.idle;

          final key = _arrow_key(byte);

          if (key != null) {
            yield key;
          }

          continue;
        }

        if (byte == 0x1B) {
          state = _EscapeState.prefix;
          continue;
        }

        final key = _ordinary_key(byte);

        if (key != null) {
          yield key;
        }
      }
    }
  }

  /// Decodes an ANSI cursor-key final byte.
  ///
  /// Only supported directional keys are emitted.
  /// Unsupported cursor commands return null.
  static TerminalSpecialKey? _arrow_key(int byte) {
    return switch (byte) {
      0x41 => TerminalSpecialKey.up,
      0x42 => TerminalSpecialKey.down,
      0x44 => TerminalSpecialKey.left,
      _ => null,
    };
  }

  /// Decodes ordinary ASCII input into physical keys.
  ///
  /// Control characters are mapped to their corresponding
  /// special keys. Printable ASCII values are retained
  /// without interpreting application shortcuts.
  ///
  /// Unsupported control characters return null.
  static TerminalKey? _ordinary_key(int byte) {
    switch (byte) {
      case 0x0A:
      case 0x0D:
        return TerminalSpecialKey.enter;

      case 0x08:
      case 0x7F:
        return TerminalSpecialKey.backspace;

      case 0x03:
        return TerminalSpecialKey.interrupt;
    }

    // All supported printable ASCII characters are
    // available to future action registrations.
    if (byte >= 0x20 && byte <= 0x7E) {
      return TerminalCharacterKey(String.fromCharCode(byte));
    }

    return null;
  }
}

/// Internal state of the ANSI escape-sequence decoder.
///
/// State is local to one [TerminalInput.read_keys] invocation.
/// No decoding state is shared between terminal sessions.
enum _EscapeState {
  /// The decoder is not consuming an escape sequence.
  idle,

  /// ESC has been received.
  prefix,

  /// An ANSI Control Sequence Introducer is active.
  csi,

  /// An ANSI Single Shift Three sequence is active.
  ss3,
}
