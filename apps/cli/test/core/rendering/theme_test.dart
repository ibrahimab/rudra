import 'package:rudra_cli/src/core/rendering/theme.dart';
import 'package:test/test.dart';

/// Verifies Rudra's shared semantic terminal themes.
///
/// These tests exercise the public rendering theme contracts.
///
/// No terminal input, ANSI encoding, SDK services, or
/// filesystem operations are required.
///
/// The contracts must remain valid regardless of which
/// rendering backend consumes the theme.
void main() {
  group('TerminalStyle', () {
    test('defaults to an unstyled representation', () {
      const style = TerminalStyle();

      expect(style.foreground, isNull);
      expect(style.bold, isFalse);
      expect(style.reverse, isFalse);
      expect(style.is_plain, isTrue);
    });

    test('preserves explicitly configured properties', () {
      const style = TerminalStyle(
        foreground: TerminalColor.cyan,
        bold: true,
        reverse: true,
      );

      expect(style.foreground, TerminalColor.cyan);
      expect(style.bold, isTrue);
      expect(style.reverse, isTrue);
      expect(style.is_plain, isFalse);
    });

    test('recognizes each styling property independently', () {
      const colored = TerminalStyle(foreground: TerminalColor.blue);

      const bold = TerminalStyle(bold: true);

      const reversed = TerminalStyle(reverse: true);

      expect(colored.is_plain, isFalse);
      expect(bold.is_plain, isFalse);
      expect(reversed.is_plain, isFalse);
    });
  });

  group('TerminalTheme', () {
    test('preserves the supplied theme identifier', () {
      final theme = TerminalTheme(name: 'custom-theme');

      expect(theme.name, 'custom-theme');
    });

    test('rejects empty and whitespace-only identifiers', () {
      for (final name in ['', ' ', '\t', '\n']) {
        expect(
          () => TerminalTheme(name: name),
          throwsA(isA<ArgumentError>()),
          reason: 'Theme identifier "$name" must be rejected.',
        );
      }
    });

    test('returns plain styles for unconfigured roles', () {
      final theme = TerminalTheme(name: 'minimal');

      for (final role in TerminalRole.values) {
        final style = theme.style_for(role);

        expect(
          style.is_plain,
          isTrue,
          reason: 'Unconfigured role ${role.name} must be plain.',
        );
      }
    });

    test('preserves configured semantic styles', () {
      const directory_style = TerminalStyle(
        foreground: TerminalColor.blue,
        bold: true,
      );

      final theme = TerminalTheme(
        name: 'custom',
        styles: {TerminalRole.directory: directory_style},
      );

      final result = theme.style_for(TerminalRole.directory);

      expect(result, same(directory_style));
      expect(result.foreground, TerminalColor.blue);
      expect(result.bold, isTrue);
      expect(result.reverse, isFalse);

      // An unrelated role must retain its default style.
      expect(theme.style_for(TerminalRole.error).is_plain, isTrue);
    });

    test('defensively copies supplied style mappings', () {
      final styles = <TerminalRole, TerminalStyle>{
        TerminalRole.directory: const TerminalStyle(
          foreground: TerminalColor.blue,
        ),
      };

      final theme = TerminalTheme(name: 'immutable', styles: styles);

      // Mutating the original map must not change the theme.
      styles[TerminalRole.directory] = const TerminalStyle(
        foreground: TerminalColor.red,
      );

      styles[TerminalRole.warning] = const TerminalStyle(bold: true);

      expect(
        theme.style_for(TerminalRole.directory).foreground,
        TerminalColor.blue,
      );

      expect(theme.style_for(TerminalRole.warning).is_plain, isTrue);

      styles.clear();

      expect(
        theme.style_for(TerminalRole.directory).foreground,
        TerminalColor.blue,
      );
    });

    test('keeps separately constructed themes independent', () {
      final first = TerminalTheme(
        name: 'first',
        styles: {
          TerminalRole.heading: const TerminalStyle(
            foreground: TerminalColor.green,
          ),
        },
      );

      final second = TerminalTheme(
        name: 'second',
        styles: {
          TerminalRole.heading: const TerminalStyle(
            foreground: TerminalColor.yellow,
          ),
        },
      );

      expect(
        first.style_for(TerminalRole.heading).foreground,
        TerminalColor.green,
      );

      expect(
        second.style_for(TerminalRole.heading).foreground,
        TerminalColor.yellow,
      );
    });
  });

  group('TerminalTheme.plain', () {
    test('has the expected identifier', () {
      expect(TerminalTheme.plain.name, 'plain');
    });

    test('disables styling for every semantic role', () {
      for (final role in TerminalRole.values) {
        final style = TerminalTheme.plain.style_for(role);

        expect(
          style.foreground,
          isNull,
          reason: '${role.name} must not request a color.',
        );

        expect(
          style.bold,
          isFalse,
          reason: '${role.name} must not request bold text.',
        );

        expect(
          style.reverse,
          isFalse,
          reason: '${role.name} must not request reverse video.',
        );

        expect(style.is_plain, isTrue);
      }
    });
  });

  group('TerminalTheme.ansi', () {
    test('has the expected identifier', () {
      expect(TerminalTheme.ansi.name, 'ansi');
    });

    test('defines title and heading emphasis', () {
      final title = TerminalTheme.ansi.style_for(TerminalRole.title);

      final heading = TerminalTheme.ansi.style_for(TerminalRole.heading);

      expect(title.foreground, TerminalColor.cyan);
      expect(title.bold, isTrue);

      expect(heading.foreground, TerminalColor.cyan);
      expect(heading.bold, isTrue);
    });

    test('distinguishes filesystem entry kinds', () {
      final theme = TerminalTheme.ansi;

      final directory = theme.style_for(TerminalRole.directory);

      final file = theme.style_for(TerminalRole.regular_file);

      final link = theme.style_for(TerminalRole.symbolic_link);

      final other = theme.style_for(TerminalRole.other_entry);

      expect(directory.foreground, TerminalColor.blue);
      expect(directory.bold, isTrue);

      expect(file.is_plain, isTrue);

      expect(link.foreground, TerminalColor.cyan);
      expect(link.bold, isFalse);

      expect(other.foreground, TerminalColor.gray);
    });

    test('uses reverse video for selected entries', () {
      final selected = TerminalTheme.ansi.style_for(TerminalRole.selected);

      expect(selected.bold, isTrue);
      expect(selected.reverse, isTrue);
    });

    test('distinguishes warnings and errors', () {
      final warning = TerminalTheme.ansi.style_for(TerminalRole.warning);

      final error = TerminalTheme.ansi.style_for(TerminalRole.error);

      expect(warning.foreground, TerminalColor.yellow);
      expect(warning.bold, isTrue);

      expect(error.foreground, TerminalColor.red);
      expect(error.bold, isTrue);
    });

    test('uses muted styling for secondary information', () {
      final muted = TerminalTheme.ansi.style_for(TerminalRole.muted);

      expect(muted.foreground, TerminalColor.gray);
      expect(muted.bold, isFalse);
      expect(muted.reverse, isFalse);
    });

    test('leaves ordinary text unstyled', () {
      final text_style = TerminalTheme.ansi.style_for(TerminalRole.text);

      expect(text_style.is_plain, isTrue);
    });
  });
}
