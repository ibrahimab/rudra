import '../terminal_text.dart';
import '../theme.dart';

/// Encodes safely sanitized text with ANSI terminal styling.
///
/// This class belongs exclusively to Rudra's bare rendering
/// backend.
///
/// It translates [TerminalStyle] properties into standard
/// Select Graphic Rendition (SGR) escape sequences.
///
/// Supported presentation properties:
/// - Basic foreground colors.
/// - Bold text.
/// - Reverse video.
/// - Combined foreground and text attributes.
/// - Resetting styles after each formatted segment.
///
/// All input text is sanitized through [TerminalText] before
/// ANSI escape sequences are introduced.
///
/// This prevents untrusted filesystem names and inspection
/// diagnostics from injecting terminal control sequences.
///
/// ANSI output is disabled by default.
///
/// Terminal capability detection belongs to the application
/// composition or terminal hosting layer. This class never
/// attempts to inspect stdin, stdout, environment variables,
/// or terminal settings.
///
/// The class does not:
/// - Access Rudra SDK services.
/// - Inspect or modify the filesystem.
/// - Write directly to stdout or stderr.
/// - Manage terminal lifecycle.
/// - Implement layout, navigation, or selection behavior.
///
/// Example:
/// ```dart
/// const encoder = AnsiText(enabled: true);
///
/// final formatted = encoder.format(
///   'Documents/',
///   style: TerminalTheme.ansi.style_for(
///     TerminalRole.directory,
///   ),
/// );
///
/// print(formatted);
/// ```
///
/// The resulting string includes ANSI formatting and a
/// terminal style reset after the displayed text.
final class AnsiText {
  /// Creates an ANSI text encoder.
  ///
  /// When [enabled] is false, formatting produces sanitized
  /// plain text without terminal escape sequences.
  ///
  /// A caller must explicitly enable ANSI output after
  /// determining that the destination supports it.
  ///
  /// Construction performs no terminal or filesystem I/O.
  const AnsiText({
    this.enabled = false,
  });

  /// Whether ANSI styling is permitted.
  ///
  /// This setting does not alter the supplied [TerminalStyle].
  ///
  /// A disabled encoder always produces plain sanitized text.
  final bool enabled;

  /// Formats text using the supplied terminal style.
  ///
  /// [value] is treated as untrusted display content and
  /// sanitized before formatting.
  ///
  /// [style] describes the desired visual appearance.
  ///
  /// When ANSI output is disabled, the style is plain,
  /// or the sanitized input is empty, the sanitized text
  /// is returned without escape sequences.
  ///
  /// Otherwise, the result contains:
  /// 1. One ANSI SGR sequence enabling requested attributes.
  /// 2. The sanitized display content.
  /// 3. An ANSI SGR reset sequence.
  ///
  /// A reset is always appended to styled nonempty output
  /// to prevent styling from leaking into subsequent content.
  ///
  /// Formatting is not designed for nested ANSI segments.
  /// Templates should format individual text segments rather
  /// than passing already-formatted ANSI strings back into
  /// this method.
  ///
  /// This method never writes to a terminal.
  ///
  /// Example:
  /// ```dart
  /// const encoder = AnsiText(enabled: true);
  ///
  /// final result = encoder.format(
  ///   'Warning',
  ///   style: const TerminalStyle(
  ///     foreground: TerminalColor.yellow,
  ///     bold: true,
  ///   ),
  /// );
  /// ```
  String format(
    String value, {
    required TerminalStyle style,
  }) {
    // Sanitization must precede generation of ANSI codes.
    // Already-styled strings must not be passed as input.
    final safe_text = TerminalText.sanitize(value);

    if (!enabled || style.is_plain || safe_text.isEmpty) {
      return safe_text;
    }

    final codes = <int>[];

    if (style.bold) {
      codes.add(_bold_code);
    }

    if (style.reverse) {
      codes.add(_reverse_code);
    }

    final foreground_code = _foreground_code(
      style.foreground,
    );

    if (foreground_code != null) {
      codes.add(foreground_code);
    }

    // TerminalStyle.is_plain guarantees at least one code
    // when an enabled, nonempty styled value reaches here.
    final sequence = codes.join(';');

    return '\x1B[${sequence}m$safe_text\x1B[${_reset_code}m';
  }

  /// ANSI SGR code enabling bold text.
  static const int _bold_code = 1;

  /// ANSI SGR code enabling reverse video.
  static const int _reverse_code = 7;

  /// ANSI SGR code resetting all text attributes.
  static const int _reset_code = 0;

  /// Maps abstract theme colors to ANSI foreground codes.
  ///
  /// The mapping is intentionally private to the bare
  /// rendering backend.
  ///
  /// A null color means that no foreground color has been
  /// explicitly requested.
  ///
  /// The gray role uses the standard bright-black SGR code.
  ///
  /// No terminal capability detection occurs here.
  static int? _foreground_code(TerminalColor? color) {
    return switch (color) {
      TerminalColor.blue => 34,
      TerminalColor.cyan => 36,
      TerminalColor.green => 32,
      TerminalColor.yellow => 33,
      TerminalColor.red => 31,
      TerminalColor.gray => 90,
      null => null,
    };
  }
}
