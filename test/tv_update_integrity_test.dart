import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_vpn_tv/tv_update_integrity.dart';

void main() {
  group('TV update SHA-256 integrity', () {
    test('computes the standard SHA-256 digest for an empty stream', () async {
      final digest = await calculateSha256(const Stream<List<int>>.empty());
      expect(
        digest,
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('computes the standard SHA-256 digest across stream chunks', () async {
      final bytes = utf8.encode('abc');
      final digest = await calculateSha256(
        Stream<List<int>>.fromIterable([
          bytes.sublist(0, 1),
          bytes.sublist(1),
        ]),
      );
      expect(
        digest,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('validates only 64 hexadecimal characters', () {
      expect(isValidSha256('a' * 64), isTrue);
      expect(isValidSha256('A' * 64), isTrue);
      expect(isValidSha256('a' * 63), isFalse);
      expect(isValidSha256('a' * 65), isFalse);
      expect(isValidSha256('g' * 64), isFalse);
      expect(isValidSha256('a' * 63 + ' '), isFalse);
    });

    test('matches digests case-insensitively', () {
      final expected = 'A' * 64;
      expect(sha256Matches(expected, 'a' * 64), isTrue);
    });

    test('rejects mismatched, malformed, or changed-file digests', () {
      const knownAbc =
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      const knownChanged =
          'cb8379ac2098aa165029e3938a51da0bcecfc008fd6795f401178647f96c5b34';
      expect(sha256Matches(knownAbc, knownAbc), isTrue);
      expect(sha256Matches(knownAbc, knownChanged), isFalse);
      expect(sha256Matches('bad', knownAbc), isFalse);
    });
  });
}
