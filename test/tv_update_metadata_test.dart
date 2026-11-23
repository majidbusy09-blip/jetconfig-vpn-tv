import 'package:flutter_test/flutter_test.dart';
import 'package:jet_vpn_tv/tv_update_metadata.dart';

void main() {
  group('TV update metadata validation', () {
    test('parses canonical manifest fields', () {
      final result = parseTvUpdateMetadata({
        'enabled': true,
        'version_code': 115,
        'version': 'tv-1.0.15',
        'title': 'نسخه جدید',
        'changelog': 'رفع اشکال',
        'force': true,
        'urls': {'arm32': 'https://example.com/tv.apk'},
      });

      expect(result, isNotNull);
      expect(result!.enabled, isTrue);
      expect(result.versionCode, 115);
      expect(result.version, 'tv-1.0.15');
      expect(result.title, 'نسخه جدید');
      expect(result.changelog, 'رفع اشکال');
      expect(result.force, isTrue);
      expect(result.apkUrl, 'https://example.com/tv.apk');
      expect(result.sha256, isNull);
    });

    test('supports legacy versionCode and APK URL aliases', () {
      final result = parseTvUpdateMetadata({
        'enabled': true,
        'versionCode': '116',
        'version': 'tv-1.0.16',
        'apk_arm32': 'https://example.com/legacy.apk',
      });

      expect(result, isNotNull);
      expect(result!.versionCode, 116);
      expect(result.apkUrl, 'https://example.com/legacy.apk');
    });

    test('uses the existing URL preference order', () {
      final result = parseTvUpdateMetadata({
        'version_code': 117,
        'version': 'tv-1.0.17',
        'urls': {
          'arm32': 'https://example.com/arm32.apk',
          'arm64': 'https://example.com/arm64.apk',
        },
      });

      expect(result!.apkUrl, 'https://example.com/arm32.apk');
    });

    test('rejects non-map, missing, zero, negative and non-numeric versions', () {
      expect(parseTvUpdateMetadata(null), isNull);
      expect(parseTvUpdateMetadata('{"version_code":2}'), isNull);
      expect(parseTvUpdateMetadata({'version_code': 0, 'version': 'x'}), isNull);
      expect(parseTvUpdateMetadata({'version_code': -1, 'version': 'x'}), isNull);
      expect(parseTvUpdateMetadata({'version_code': 'abc', 'version': 'x'}), isNull);
      expect(parseTvUpdateMetadata({'version_code': 2}), isNull);
      expect(parseTvUpdateMetadata({'version_code': 2, 'version': '  '}), isNull);
    });

    test('does not coerce truthy strings into enabled or force', () {
      final result = parseTvUpdateMetadata({
        'enabled': 'true',
        'force': 1,
        'version_code': 118,
        'version': 'tv-1.0.18',
        'apk': 'https://example.com/tv.apk',
      });

      expect(result, isNotNull);
      expect(result!.enabled, isFalse);
      expect(result.force, isFalse);
    });

    test('rejects unsafe or malformed APK URLs without rejecting manifest', () {
      for (final url in [
        'javascript:alert(1)',
        'file:///tmp/app.apk',
        'https:///missing-host.apk',
        'https://user:pass@example.com/app.apk',
        'not a url',
      ]) {
        final result = parseTvUpdateMetadata({
          'version_code': 119,
          'version': 'tv-1.0.19',
          'apk': url,
        });
        expect(result, isNotNull, reason: url);
        expect(result!.apkUrl, isNull, reason: url);
      }
    });

    test('keeps disabled metadata valid and applies defaults', () {
      final result = parseTvUpdateMetadata({
        'enabled': false,
        'version_code': 120,
        'version': 'tv-1.0.20',
      });

      expect(result, isNotNull);
      expect(result!.enabled, isFalse);
      expect(result.title, 'نسخه جدید JET TV');
      expect(result.changelog, '');
      expect(result.apkUrl, isNull);
      expect(result.sha256, isNull);
    });

    test('accepts a valid SHA-256 digest and normalizes it to lowercase', () {
      final digest = 'A' * 64;
      final result = parseTvUpdateMetadata({
        'version_code': 121,
        'version': 'tv-1.0.21',
        'sha256': digest,
      });

      expect(result, isNotNull);
      expect(result!.sha256, 'a' * 64);
    });

    test('preserves legacy behavior when SHA-256 is missing or null', () {
      for (final manifest in [
        {'version_code': 122, 'version': 'tv-1.0.22'},
        {'version_code': 123, 'version': 'tv-1.0.23', 'sha256': null},
      ]) {
        final result = parseTvUpdateMetadata(manifest);
        expect(result, isNotNull);
        expect(result!.sha256, isNull);
      }
    });

    test('rejects malformed present SHA-256 metadata', () {
      for (final digest in [
        '',
        'a' * 63,
        'a' * 65,
        'g' * 64,
        'a' * 63 + ' ',
        123,
        true,
      ]) {
        final result = parseTvUpdateMetadata({
          'version_code': 124,
          'version': 'tv-1.0.24',
          'sha256': digest,
        });
        expect(result, isNull, reason: '$digest');
      }
    });
  });
}
