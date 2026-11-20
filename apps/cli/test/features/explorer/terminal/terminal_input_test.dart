import 'dart:convert';

import 'package:rudra_cli/src/features/explorer/terminal/terminal_input.dart';
import 'package:rudra_cli/src/features/explorer/terminal/terminal_key.dart';
import 'package:test/test.dart';

/// Tests decoding terminal bytes into physical keyboard events.
///
/// Input is supplied as deterministic byte streams. Chunk boundaries
/// are preserved to exercise partial ANSI escape sequences.
void main() {
  group('TerminalInput', () {
    test('decodes navigation and control keys', () async {
      final keys = await _decode([ascii.encode('\x1B[A\x1B[B\x1B[D\r\b\x7F')]);

      expect(
        keys,
        orderedEquals([
          TerminalSpecialKey.up,
          TerminalSpecialKey.down,
          TerminalSpecialKey.left,
          TerminalSpecialKey.enter,
          TerminalSpecialKey.backspace,
          TerminalSpecialKey.backspace,
        ]),
      );
    });

    test('preserves printable characters and their case', () async {
      final keys = await _decode([ascii.encode('pPsSxXqQ? ')]);

      expect(
        keys,
        orderedEquals([
          const TerminalCharacterKey('p'),
          const TerminalCharacterKey('P'),
          const TerminalCharacterKey('s'),
          const TerminalCharacterKey('S'),
          const TerminalCharacterKey('x'),
          const TerminalCharacterKey('X'),
          const TerminalCharacterKey('q'),
          const TerminalCharacterKey('Q'),
          const TerminalCharacterKey('?'),
          const TerminalCharacterKey(' '),
        ]),
      );
    });

    test('supports LF as Enter', () async {
      expect(await _decode([ascii.encode('\n')]), [TerminalSpecialKey.enter]);
    });

    test('decodes CRLF as one Enter across chunks', () async {
      expect(await _decode([ascii.encode('\r'), ascii.encode('\n')]), [
        TerminalSpecialKey.enter,
      ]);
    });

    test('decodes ANSI sequences across chunks', () async {
      final keys = await _decode([
        ascii.encode('\x1B'),
        ascii.encode('['),
        <int>[],
        ascii.encode('A\x1B'),
        ascii.encode('['),
        ascii.encode('B\x1B[D'),
      ]);

      expect(
        keys,
        orderedEquals([
          TerminalSpecialKey.up,
          TerminalSpecialKey.down,
          TerminalSpecialKey.left,
        ]),
      );
    });

    test('supports SS3 cursor-key sequences', () async {
      expect(await _decode([ascii.encode('\x1BOA\x1BOB\x1BOD')]), [
        TerminalSpecialKey.up,
        TerminalSpecialKey.down,
        TerminalSpecialKey.left,
      ]);
    });

    test('accepts modified CSI arrow sequences', () async {
      final keys = await _decode([
        ascii.encode('\x1B[1;5A'),
        ascii.encode('\x1B[1;3B'),
        ascii.encode('\x1B[1;2D'),
      ]);

      expect(keys, [
        TerminalSpecialKey.up,
        TerminalSpecialKey.down,
        TerminalSpecialKey.left,
      ]);
    });

    test('ignores unsupported ANSI sequences', () async {
      final keys = await _decode([
        ascii.encode('\x1B[C'),
        ascii.encode('\x1B[H'),
        ascii.encode('\x1BOF'),
        ascii.encode('\x1B[2~'),
        ascii.encode('z'),
      ]);

      expect(keys, [const TerminalCharacterKey('z')]);
    });

    test('discards incomplete escape sequences at EOF', () async {
      expect(await _decode([ascii.encode('\x1B')]), isEmpty);

      expect(
        await _decode([ascii.encode('\x1B['), ascii.encode('1;5')]),
        isEmpty,
      );
    });

    test('emits raw Ctrl+C as an interrupt', () async {
      expect(
        await _decode([
          <int>[0x03],
        ]),
        [TerminalSpecialKey.interrupt],
      );
    });

    test('supports an empty input stream', () async {
      expect(await _decode([]), isEmpty);
    });

    test('propagates source stream failures', () async {
      final input = TerminalInput(
        source: Stream<List<int>>.error(
          StateError('Injected terminal read failure.'),
        ),
      );

      await expectLater(input.read_keys(), emitsError(isA<StateError>()));
    });
  });
}

/// Decodes terminal input supplied in ordered byte chunks.
///
/// [chunks] contains the byte sequences delivered by the terminal
/// source. Empty chunks and split ANSI sequences are permitted.
///
/// Returns the decoded physical keys in their original order.
///
/// Example:
/// ```dart
/// final keys = await _decode([
///   ascii.encode('\x1B'),
///   ascii.encode('[A'),
/// ]);
///
/// assert(keys.single == TerminalSpecialKey.up);
/// ```
Future<List<TerminalKey>> _decode(List<List<int>> chunks) {
  final input = TerminalInput(source: Stream<List<int>>.fromIterable(chunks));

  return input.read_keys().toList();
}
