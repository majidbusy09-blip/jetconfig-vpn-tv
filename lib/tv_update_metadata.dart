class TvUpdateMetadata {
  const TvUpdateMetadata({
    required this.enabled,
    required this.versionCode,
    required this.version,
    required this.title,
    required this.changelog,
    required this.force,
    required this.apkUrl,
  });

  final bool enabled;
  final int versionCode;
  final String version;
  final String title;
  final String changelog;
  final bool force;
  final String? apkUrl;
}

/// Parses the TV update manifest without performing network or filesystem work.
///
/// Supports the legacy field aliases and APK URL fallback order used by the app.
/// Invalid core metadata is rejected; an invalid/missing APK URL is represented
/// as null so disabled-update and "no downloadable package" flows remain intact.
TvUpdateMetadata? parseTvUpdateMetadata(Object? value) {
  if (value is! Map) return null;

  final rawCode = value['version_code'] ?? value['versionCode'] ?? 0;
  final code = int.tryParse('$rawCode') ?? 0;
  final version = '${value['version'] ?? ''}';
  if (code <= 0 || version.trim().isEmpty) return null;

  final title = '${value['title'] ?? 'نسخه جدید JET TV'}';
  final changelog = '${value['changelog'] ?? ''}';
  final enabled = value['enabled'] == true;
  final force = value['force'] == true;

  final urls = value['urls'];
  var rawUrl = '';
  if (urls is Map) {
    rawUrl = '${urls['arm32'] ?? urls['armeabi-v7a'] ?? urls['arm64'] ?? urls['universal'] ?? ''}';
  }
  if (rawUrl.isEmpty) {
    rawUrl = '${value['apk_arm32'] ?? value['apk_arm64'] ?? value['apk'] ?? ''}';
  }

  String? apkUrl;
  if (rawUrl.trim().isNotEmpty) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty) {
      apkUrl = rawUrl.trim();
    }
  }

  return TvUpdateMetadata(
    enabled: enabled,
    versionCode: code,
    version: version,
    title: title,
    changelog: changelog,
    force: force,
    apkUrl: apkUrl,
  );
}
