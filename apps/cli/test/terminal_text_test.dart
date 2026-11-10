import 'package:rudra_cli/src/rendering/terminal_text.dart';
import 'package:test/test.dart';

/// Verifies shared terminal text processing for Rudra's CLI.
///
/// Tests cover sanitization of untrusted filesystem strings,
/// approximate Unicode display widths, truncation, and padding.
///
/// No filesystem, SDK, terminal, or rendering backend is used.
///
/// These tests deliberately verify the documented limitations
/// of the initial bare terminal implementation rather than
/// claiming full Unicode grapheme-width compatibility.
void main() {
  group('TerminalText.sanitize', () {
    test('preserves ordinary printable text', () {
      const value = 'README.md café 文件 🙂';

      expect(TerminalText.sanitize(value), value);
    });

    test('preserves empty strings', () {
      expect(TerminalText.sanitize(''), isEmpty);
    });

    test('replaces ASCII terminal controls', () {
      const value = 'first\nsecond\rthird\tfourth';

      expect(
        TerminalText.sanitize(value),
        'first?second?third?fourth',
      );
    });

    test('neutralizes ANSI escape sequences', () {
      const value = '\x1B[31mred\x1B[0m';

      final safe = TerminalText.sanitize(value);

      expect(safe, '?[31mred?[0m');
      expect(safe.contains('\x1B'), isFalse);
    });

    test('neutralizes terminal clearing sequences', () {
      const filename = '/fixture/\x1B[2Jexample.txt';

      final safe = TerminalText.sanitize(filename);

      expect(safe, '/fixture/?[2Jexample.txt');
      expect(safe.contains('\x1B'), isFalse);
    });

    test('replaces DEL and C1 control characters', () {
      const value = 'a\x7Fb\u009Bc';

      expect(
        TerminalText.sanitize(value),
        'a?b?c',
      );
    });

    test('replaces bidirectional formatting controls', () {
      const value = 'a\u202Eb\u202Cc\u2066d\u2069e';

      expect(
        TerminalText.sanitize(value),
        'a?b?c?d?e',
      );
    });

    test('replaces direction marks and Arabic letter mark', () {
      const value = 'a\u200Eb\u200Fc\u061Cd';

      expect(
        TerminalText.sanitize(value),
        'a?b?c?d',
      );
    });

    test('replaces Unicode line and paragraph separators', () {
      const value = 'a\u2028b\u2029c';

      expect(
        TerminalText.sanitize(value),
        'a?b?c',
      );
    });

    test('replaces the Unicode byte-order mark', () {
      const value = 'a\uFEFFb';

      expect(
        TerminalText.sanitize(value),
        'a?b',
      );
    });

    test('preserves combining marks', () {
      const value = 'e\u0301';

      expect(
        TerminalText.sanitize(value),
        value,
      );
    });
  });

  group('TerminalText.estimated_columns', () {
    test('returns zero for empty strings', () {
      expect(
        TerminalText.estimated_columns(''),
        0,
      );
    });

    test('counts ordinary ASCII characters', () {
      expect(
        TerminalText.estimated_columns('hello'),
        5,
      );
    });

    test('counts common wide characters as two columns', () {
      expect(
        TerminalText.estimated_columns('文件'),
        4,
      );
    });

    test('counts common emoji as two columns', () {
      expect(
        TerminalText.estimated_columns('🙂'),
        2,
      );
    });

    test('does not count combining marks separately', () {
      expect(
        TerminalText.estimated_columns('e\u0301'),
        1,
      );
    });

    test('accounts for mixed ordinary and wide text', () {
      expect(
        TerminalText.estimated_columns('a文b'),
        4,
      );
    });

    test('sanitizes unsafe characters before measurement', () {
      expect(
        TerminalText.estimated_columns('a\nb'),
        3,
      );
    });

    test('recognizes zero-width joiners in its estimate', () {
      expect(
        TerminalText.estimated_columns('a\u200Db'),
        2,
      );
    });
  });

  group('TerminalText.truncate', () {
    test('preserves strings that fit', () {
      expect(
        TerminalText.truncate(
          'hello',
          max_columns: 5,
        ),
        'hello',
      );
    });

    test('preserves shorter strings without padding', () {
      expect(
        TerminalText.truncate(
          'abc',
          max_columns: 10,
        ),
        'abc',
      );
    });

    test('truncates long ASCII strings with an ellipsis', () {
      expect(
        TerminalText.truncate(
          'abcdefghij',
          max_columns: 6,
        ),
        'abcde…',
      );
    });

    test('handles a one-column limit', () {
      expect(
        TerminalText.truncate(
          'abcdef',
          max_columns: 1,
        ),
        '…',
      );
    });

    test('returns empty text for a zero-column limit', () {
      expect(
        TerminalText.truncate(
          'abcdef',
          max_columns: 0,
        ),
        isEmpty,
      );
    });

    test('does not split wide Unicode code points', () {
      final result = TerminalText.truncate(
        '文件report',
        max_columns: 4,
      );

      expect(result, '文…');

      expect(
        TerminalText.estimated_columns(result),
        lessThanOrEqualTo(4),
      );
    });

    test('keeps combining marks attached in common cases', () {
      final result = TerminalText.truncate(
        'e\u0301clair',
        max_columns: 4,
      );

      expect(result, 'e\u0301cl…');
    });

    test('sanitizes text even when truncation is unnecessary', () {
      expect(
        TerminalText.truncate(
          'a\x1Bb',
          max_columns: 20,
        ),
        'a?b',
      );
    });

    test('rejects negative widths', () {
      expect(
        () => TerminalText.truncate(
          'abc',
          max_columns: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('TerminalText.pad_right', () {
    test('pads ordinary text with spaces', () {
      expect(
        TerminalText.pad_right(
          'DIR',
          min_columns: 6,
        ),
        'DIR   ',
      );
    });

    test('does not truncate text exceeding the width', () {
      expect(
        TerminalText.pad_right(
          'DIRECTORY',
          min_columns: 3,
        ),
        'DIRECTORY',
      );
    });

    test('accounts for wide Unicode characters', () {
      final result = TerminalText.pad_right(
        '文件',
        min_columns: 7,
      );

      expect(result, '文件   ');
      expect(
        TerminalText.estimated_columns(result),
        7,
      );
    });

    test('accounts for combining characters', () {
      final result = TerminalText.pad_right(
        'e\u0301',
        min_columns: 4,
      );

      expect(result, 'e\u0301   ');
      expect(
        TerminalText.estimated_columns(result),
        4,
      );
    });

    test('sanitizes the input before padding', () {
      expect(
        TerminalText.pad_right(
          'a\nb',
          min_columns: 5,
        ),
        'a?b  ',
      );
    });

    test('accepts a zero-width minimum', () {
      expect(
        TerminalText.pad_right(
          'abc',
          min_columns: 0,
        ),
        'abc',
      );
    });

    test('rejects negative widths', () {
      expect(
        () => TerminalText.pad_right(
          'abc',
          min_columns: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('TerminalText.pad_left', () {
    test('pads ordinary text on the left', () {
      expect(
        TerminalText.pad_left(
          '42',
          min_columns: 5,
        ),
        '   42',
      );
    });

    test('does not truncate text exceeding the width', () {
      expect(
        TerminalText.pad_left(
          '123456',
          min_columns: 3,
        ),
        '123456',
      );
    });

    test('accounts for wide Unicode characters', () {
      final result = TerminalText.pad_left(
        '文件',
        min_columns: 7,
      );

      expect(result, '   文件');
      expect(
        TerminalText.estimated_columns(result),
        7,
      );
    });

    test('accounts for emoji widths', () {
      final result = TerminalText.pad_left(
        '🙂',
        min_columns: 5,
      );

      expect(result, '   🙂');
      expect(
        TerminalText.estimated_columns(result),
        5,
      );
    });

    test('sanitizes input before padding', () {
      expect(
        TerminalText.pad_left(
          'a\tb',
          min_columns: 5,
        ),
        '  a?b',
      );
    });

    test('accepts a zero-width minimum', () {
      expect(
        TerminalText.pad_left(
          'abc',
          min_columns: 0,
        ),
        'abc',
      );
    });

    test('rejects negative widths', () {
      expect(
        () => TerminalText.pad_left(
          'abc',
          min_columns: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
