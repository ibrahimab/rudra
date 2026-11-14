import 'package:rudra_cli/src/core/rendering/bare/ansi_text.dart';
import 'package:rudra_cli/src/core/rendering/theme.dart';
import 'package:test/test.dart';

/// Verifies ANSI encoding for Rudra's bare rendering backend.
///
/// Tests cover:
/// - Default plain-text behavior.
/// - ANSI foreground color mappings.
/// - Bold and reverse-video attributes.
/// - Combined SGR attributes.
/// - Terminal style resets.
/// - Sanitization of untrusted display content.
/// - Integration with semantic terminal themes.
///
/// No real terminal, SDK service, or filesystem is required.
///
/// ANSI output is tested as raw strings to ensure stable,
/// deterministic formatting across rendering implementations.
void main() {
  group('AnsiText construction', () {
    test('disables ANSI output by default', () {
      const encoder = AnsiText();

      expect(encoder.enabled, isFalse);
    });

    test('supports explicitly enabling ANSI output', () {
      const encoder = AnsiText(enabled: true);

      expect(encoder.enabled, isTrue);
    });

    test('supports explicitly disabling ANSI output', () {
      const encoder = AnsiText(enabled: false);

      expect(encoder.enabled, isFalse);
    });
  });

  group('AnsiText plain output', () {
    test('returns ordinary text unchanged', () {
      const encoder = AnsiText();

      final result = encoder.format('README.md', style: const TerminalStyle());

      expect(result, 'README.md');
    });

    test('ignores styling when ANSI is disabled', () {
      const encoder = AnsiText(enabled: false);

      final result = encoder.format(
        'Documents/',
        style: const TerminalStyle(
          foreground: TerminalColor.blue,
          bold: true,
          reverse: true,
        ),
      );

      expect(result, 'Documents/');
      expect(result.contains('\x1B'), isFalse);
    });

    test('does not encode a plain style when enabled', () {
      const encoder = AnsiText(enabled: true);

      final result = encoder.format(
        'Normal text',
        style: const TerminalStyle(),
      );

      expect(result, 'Normal text');
    });

    test('returns empty text without ANSI sequences', () {
      const encoder = AnsiText(enabled: true);

      final result = encoder.format(
        '',
        style: const TerminalStyle(foreground: TerminalColor.red, bold: true),
      );

      expect(result, isEmpty);
    });

    test('preserves printable Unicode characters', () {
      const encoder = AnsiText(enabled: false);

      final result = encoder.format(
        'café 文件 🙂',
        style: const TerminalStyle(foreground: TerminalColor.cyan),
      );

      expect(result, 'café 文件 🙂');
    });
  });

  group('AnsiText foreground colors', () {
    final color_codes = <TerminalColor, int>{
      TerminalColor.blue: 34,
      TerminalColor.cyan: 36,
      TerminalColor.green: 32,
      TerminalColor.yellow: 33,
      TerminalColor.red: 31,
      TerminalColor.gray: 90,
    };

    for (final entry in color_codes.entries) {
      test('encodes ${entry.key.name} correctly', () {
        const encoder = AnsiText(enabled: true);

        final result = encoder.format(
          'example',
          style: TerminalStyle(foreground: entry.key),
        );

        expect(result, '\x1B[${entry.value}mexample\x1B[0m');
      });
    }

    test('does not add a foreground code for null', () {
      const encoder = AnsiText(enabled: true);

      final result = encoder.format(
        'example',
        style: const TerminalStyle(bold: true),
      );

      expect(result, '\x1B[1mexample\x1B[0m');
    });
  });

  group('AnsiText text attributes', () {
    test('encodes bold text', () {
      const encoder = AnsiText(enabled: true);

      final result = encoder.format(
        'Important',
        style: const TerminalStyle(bold: true),
      );

      expect(result, '\x1B[1mImportant\x1B[0m');
    });

    test('encodes reverse-video text', () {
      const encoder = AnsiText(enabled: true);

      final result = encoder.format(
        'Selected',
        style: const TerminalStyle(reverse: true),
      );

      expect(result, '\x1B[7mSelected\x1B[0m');
    });

    test('combines bold and reverse video', () {
      const encoder = AnsiText(enabled: true);

      final result = encoder.format(
        'Selected',
        style: const TerminalStyle(bold: true, reverse: true),
      );

      expect(result, '\x1B[1;7mSelected\x1B[0m');
    });

    test('combines all supported style properties', () {
      const encoder = AnsiText(enabled: true);

      final result = encoder.format(
        'Highlighted',
        style: const TerminalStyle(
          foreground: TerminalColor.cyan,
          bold: true,
          reverse: true,
        ),
      );

      // Attribute ordering is deterministic:
      // bold, reverse video, foreground color.
      expect(result, '\x1B[1;7;36mHighlighted\x1B[0m');
    });
  });

  group('AnsiText style resets', () {
    test('resets styling after formatted text', () {
      const encoder = AnsiText(enabled: true);

      final result = encoder.format(
        'Error',
        style: const TerminalStyle(foreground: TerminalColor.red),
      );

      expect(result.startsWith('\x1B[31m'), isTrue);
      expect(result.endsWith('\x1B[0m'), isTrue);
    });

    test('does not leak styling between segments', () {
      const encoder = AnsiText(enabled: true);

      final first = encoder.format(
        'Directory',
        style: const TerminalStyle(foreground: TerminalColor.blue, bold: true),
      );

      final second = encoder.format('File', style: const TerminalStyle());

      final combined = '$first $second';

      expect(combined, '\x1B[1;34mDirectory\x1B[0m File');

      expect(second.contains('\x1B'), isFalse);
    });

    test('produces independent styled segments', () {
      const encoder = AnsiText(enabled: true);

      final warning = encoder.format(
        'Warning',
        style: const TerminalStyle(foreground: TerminalColor.yellow),
      );

      final error = encoder.format(
        'Error',
        style: const TerminalStyle(foreground: TerminalColor.red),
      );

      expect(
        '$warning $error',
        '\x1B[33mWarning\x1B[0m '
            '\x1B[31mError\x1B[0m',
      );
    });
  });

  group('AnsiText security', () {
    test('neutralizes injected ANSI color sequences', () {
      const encoder = AnsiText(enabled: true);

      const malicious = 'file\x1B[31m.txt';

      final result = encoder.format(
        malicious,
        style: const TerminalStyle(foreground: TerminalColor.blue),
      );

      expect(result, '\x1B[34mfile?[31m.txt\x1B[0m');

      // Only the renderer-generated escape sequences
      // may appear in the resulting output.
      expect(RegExp(r'\x1B').allMatches(result).length, 2);
    });

    test('neutralizes terminal clearing sequences', () {
      const encoder = AnsiText(enabled: true);

      const malicious = 'before\x1B[2Jafter';

      final result = encoder.format(
        malicious,
        style: const TerminalStyle(bold: true),
      );

      expect(result, '\x1B[1mbefore?[2Jafter\x1B[0m');

      expect(result.contains('\x1B[2J'), isFalse);
    });

    test('replaces embedded line breaks', () {
      const encoder = AnsiText(enabled: false);

      final result = encoder.format(
        'first\nsecond\rthird',
        style: const TerminalStyle(),
      );

      expect(result, 'first?second?third');
    });

    test('neutralizes C1 control sequences', () {
      const encoder = AnsiText(enabled: false);

      final result = encoder.format(
        'before\u009B31mafter',
        style: const TerminalStyle(),
      );

      expect(result, 'before?31mafter');
    });

    test('neutralizes bidirectional overrides', () {
      const encoder = AnsiText(enabled: true);

      final result = encoder.format(
        'safe\u202Emalicious\u202C',
        style: const TerminalStyle(foreground: TerminalColor.red),
      );

      expect(result, '\x1B[31msafe?malicious?\x1B[0m');
    });

    test('sanitizes text even when styling is disabled', () {
      const encoder = AnsiText(enabled: false);

      final result = encoder.format(
        'name\x1B[0m.txt',
        style: const TerminalStyle(bold: true, reverse: true),
      );

      expect(result, 'name?[0m.txt');
      expect(result.contains('\x1B'), isFalse);
    });
  });

  group('AnsiText theme integration', () {
    test('renders directory styling from the ANSI theme', () {
      const encoder = AnsiText(enabled: true);

      final style = TerminalTheme.ansi.style_for(TerminalRole.directory);

      final result = encoder.format('Documents/', style: style);

      expect(result, '\x1B[1;34mDocuments/\x1B[0m');
    });

    test('renders selected-entry styling', () {
      const encoder = AnsiText(enabled: true);

      final style = TerminalTheme.ansi.style_for(TerminalRole.selected);

      final result = encoder.format('Selected entry', style: style);

      expect(result, '\x1B[1;7mSelected entry\x1B[0m');
    });

    test('renders warning and error roles differently', () {
      const encoder = AnsiText(enabled: true);

      final warning = encoder.format(
        'Warning',
        style: TerminalTheme.ansi.style_for(TerminalRole.warning),
      );

      final error = encoder.format(
        'Error',
        style: TerminalTheme.ansi.style_for(TerminalRole.error),
      );

      expect(warning, '\x1B[1;33mWarning\x1B[0m');
      expect(error, '\x1B[1;31mError\x1B[0m');
    });

    test('plain theme never introduces ANSI styling', () {
      const encoder = AnsiText(enabled: true);

      for (final role in TerminalRole.values) {
        final style = TerminalTheme.plain.style_for(role);

        final result = encoder.format('example', style: style);

        expect(
          result,
          'example',
          reason: 'Role ${role.name} must remain plain.',
        );
      }
    });

    test('disabled ANSI works with the colored theme', () {
      const encoder = AnsiText(enabled: false);

      for (final role in TerminalRole.values) {
        final style = TerminalTheme.ansi.style_for(role);

        final result = encoder.format('example', style: style);

        expect(
          result,
          'example',
          reason: 'Disabled ANSI must ignore ${role.name}.',
        );
      }
    });
  });
}
