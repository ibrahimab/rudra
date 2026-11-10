import 'dart:async';

/// Navigation actions recognized by Rudra's interactive CLI.
///
/// These actions describe user intent rather than terminal-specific
/// byte sequences.
///
/// Unknown keys and unsupported terminal sequences are ignored.
///
/// No action in this enum authorizes filesystem modification.
enum ExplorerKey {
  /// Moves selection to the preceding entry.
  up,

  /// Moves selection to the following entry.
  down,

  /// Opens the selected entry if it is a directory.
  open,

  /// Returns to the previously visited directory.
  back,

  /// Ends the current interactive explorer.
  quit,
}

/// Decodes terminal input bytes into explorer navigation actions.
///
/// Terminal input arrives as chunks of bytes. A single key may
/// produce multiple bytes, and a sequence may span several chunks.
///
/// Supported input:
/// - ANSI CSI and SS3 up, down, and left arrows.
/// - Enter (CR or LF).
/// - Backspace (BS or DEL).
/// - Lowercase and uppercase Q.
///
/// Unsupported keys and escape sequences produce no event.
///
/// This class does not:
/// - Read directly from stdin.
/// - Change terminal echo or line mode.
/// - Render terminal output.
/// - Inspect or modify the filesystem.
/// - Manage navigation state.
///
/// Terminal configuration and restoration belong to the
/// interactive terminal runner.
///
/// Example:
/// ```dart
/// final input = TerminalInput(
///   source: Stream<List<int>>.fromIterable([
///     [0x1B],
///     [0x5B, 0x41],
///     [0x0D],
///     [0x71],
///   ]),
/// );
///
/// await for (final key in input.read_keys()) {
///   print(key);
/// }
/// ```
///
/// Produces up, open, and quit in that order.
final class TerminalInput {
  /// Creates a decoder for the supplied byte stream.
  ///
  /// [source] must provide raw terminal input bytes.
  ///
  /// The source may be stdin or an injected stream used by tests.
  ///
  /// Construction does not subscribe to the stream or change
  /// terminal settings.
  const TerminalInput({
    required Stream<List<int>> source,
  }) : _source = source;

  /// Raw terminal input supplied by the caller.
  final Stream<List<int>> _source;

  /// Reads supported explorer navigation actions.
  ///
  /// Escape-sequence state is retained across input chunks.
  ///
  /// Both CSI (ESC [) and SS3 (ESC O) cursor-key sequences
  /// are supported.
  ///
  /// CSI parameter bytes are ignored until the final command
  /// byte is received. Unsupported commands are discarded.
  ///
  /// An incomplete escape sequence at end-of-stream is ignored.
  ///
  /// When [source] finishes, this stream completes normally.
  /// Errors from [source] propagate to the subscriber.
  ///
  /// Each invocation establishes a new source subscription.
  /// Callers should consume this stream once for each
  /// interactive terminal session.
  ///
  /// This method performs no filesystem operations.
  ///
  /// Consecutive CRLF bytes produce a single open event,
  /// including when the bytes arrive in separate chunks.
  Stream<ExplorerKey> read_keys() async* {
    var state = _EscapeState.idle;
    var previous_was_carriage_return = false;

    await for (final chunk in _source) {
      for (final byte in chunk) {
        // CRLF represents one Enter key, even across chunks.
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

          // An unsupported escape prefix is discarded.
          // The current byte may still be a valid key.
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

  /// Maps a terminal cursor-key command to navigation intent.
  ///
  /// Unrecognized commands do not produce an action.
  static ExplorerKey? _arrow_key(int byte) {
    return switch (byte) {
      0x41 => ExplorerKey.up,
      0x42 => ExplorerKey.down,
      0x44 => ExplorerKey.back,
      _ => null,
    };
  }

  /// Maps ordinary ASCII control and character bytes.
  ///
  /// Both common Backspace encodings are supported because
  /// terminal configurations vary.
  ///
  /// Unrecognized bytes are ignored.
  static ExplorerKey? _ordinary_key(int byte) {
    return switch (byte) {
      0x0A || 0x0D => ExplorerKey.open,
      0x08 || 0x7F => ExplorerKey.back,
      0x71 || 0x51 => ExplorerKey.quit,
      _ => null,
    };
  }
}

/// Tracks decoding of a terminal escape sequence.
///
/// State exists only while consuming one input stream.
enum _EscapeState {
  /// No escape sequence is currently being decoded.
  idle,

  /// An ESC byte has been received.
  prefix,

  /// An ANSI Control Sequence Introducer was received.
  csi,

  /// An ANSI Single Shift Three sequence was received.
  ss3,
}
