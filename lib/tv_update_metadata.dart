class TvUpdateMetadata {
  const TvUpdateMetadata({
    required this.enabled,
    required this.versionCode,
    required this.version,
    required this.title,
    required this.changelog,
    required this.force,
    required this.apkUrl,
    required this.sha256,
  });

  final bool enabled;
  final int versionCode;
  final String version;
  final String title;
  final String changelog;
  final bool force;
  final String? apkUrl;

  /// Expected APK digest from the separately fetched update manifest.
  /// Null means the manifest is legacy and the artifact is unverified.
  final String? sha256;
}

/// Parses the TV update manifest without performing network or filesystem work.
///
/// Supports the legacy field aliases and APK URL fallback order used by the app.
/// Invalid core metadata or a malformed present SHA-256 value is rejected;
/// an invalid/missing APK URL is represented as null so existing no-download
/// flows remain intact. A missing/null digest preserves legacy compatibility.
TvUpdateMetadata? parseTvUpdateMetadata(Object? value) {
  if (value is! Map) return null;

  final rawCode = value['version_code'] ?? value['versionCode'] ?? 0;
  final code = int.tryParse('$rawCode') ?? 0;
  final version = '${value['version'] ?? ''}';
  if (code <= 0 || version.trim().isEmpty) return null;

  String? sha256;
  final rawSha256 = value['sha256'];
  if (rawSha256 != null) {
    if (rawSha256 is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(rawSha256)) {
      return null;
    }
    sha256 = rawSha256.toLowerCase();
  }

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
    sha256: sha256,
  );
}
