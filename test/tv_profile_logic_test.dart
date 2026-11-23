import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_vpn_tv/tv_profile_logic.dart';

void main() {
  group('profile persistence serialization', () {
    test('inserts the newest profile first and removes exact username duplicate', () {
      final raw = json.encode([
        {'u': 'old', 'p': 'old-pass'},
        {'u': 'current', 'p': 'stale-pass'},
        {'u': 'other', 'p': 'other-pass'},
      ]);

      final result = json.decode(
        upsertProfileJson(raw, 'current', 'new-pass'),
      ) as List;

      expect(result, [
        {'u': 'current', 'p': 'new-pass'},
        {'u': 'old', 'p': 'old-pass'},
        {'u': 'other', 'p': 'other-pass'},
      ]);
    });

    test('keeps no more than twelve profiles', () {
      final raw = json.encode(List.generate(
        14,
        (i) => {'u': 'user$i', 'p': 'pass$i'},
      ));

      final result = json.decode(
        upsertProfileJson(raw, 'new-user', 'new-pass'),
      ) as List;

      expect(result, hasLength(12));
      expect(result.first['u'], 'new-user');
      expect(result.last['u'], 'user10');
    });

    test('recovers from malformed or non-list JSON', () {
      expect(json.decode(upsertProfileJson('{broken', 'u', 'p')), [
        {'u': 'u', 'p': 'p'}
      ]);
      expect(json.decode(upsertProfileJson('{"u":"x"}', 'u', 'p')), [
        {'u': 'u', 'p': 'p'}
      ]);
    });

    test('ignores non-map entries while preserving other profile values', () {
      final raw = json.encode([
        'invalid',
        {'u': 'valid', 'p': 'secret'},
      ]);
      final result = json.decode(
        upsertProfileJson(raw, 'new', 'pass'),
      ) as List;

      expect(result, [
        {'u': 'new', 'p': 'pass'},
        {'u': 'valid', 'p': 'secret'},
      ]);
    });
  });

  group('profile persistence parsing', () {
    test('loads valid profiles and converts missing values to empty strings', () {
      final raw = json.encode([
        {'u': 'alice', 'p': 'pw'},
        {'u': 'bob'},
        {'p': 'orphan'},
        'invalid',
        {'u': '', 'p': 'empty-user'},
      ]);

      expect(loadProfilesFromJson(raw), [
        {'u': 'alice', 'p': 'pw'},
        {'u': 'bob', 'p': ''},
      ]);
    });

    test('returns an empty list for malformed or non-list JSON', () {
      expect(loadProfilesFromJson('{broken'), isEmpty);
      expect(loadProfilesFromJson('{"u":"alice"}'), isEmpty);
    });

    test('preserves exact username and password strings', () {
      expect(
        loadProfilesFromJson('[{"u":" User ","p":" p@ss "}]'),
        [
          {'u': ' User ', 'p': ' p@ss '}
        ],
      );
    });
  });
}
