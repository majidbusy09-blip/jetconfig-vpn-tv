import 'dart:convert';

/// A single-key representation of a downloaded update's pending metadata.
///
/// Keeping the record in one preference value avoids exposing a partially
/// written set of independent keys after an interrupted save.
class PendingUpdateRecord {
  const PendingUpdateRecord({
    required this.path,
    required this.version,
    required this.versionCode,
    required this.channel,
    required this.size,
    required this.url,
    required this.sha256,
  });

  final String path;
  final String version;
  final int versionCode;
  final String channel;
  final int size;
  final String url;
  final String? sha256;

  Map<String, Object?> toJson() => {
        'schema': 1,
        'path': path,
        'version': version,
        'version_code': versionCode,
        'channel': channel,
        'size': size,
        'url': url,
        'sha256': sha256,
      };

  static PendingUpdateRecord? fromJson(Object? value) {
    if (value is! Map<String, dynamic> || value['schema'] != 1) return null;
    final path = value['path'];
    final version = value['version'];
    final versionCode = value['version_code'];
    final channel = value['channel'];
    final size = value['size'];
    final url = value['url'];
    final sha256 = value['sha256'];
    if (path is! String || path.isEmpty ||
        version is! String ||
        versionCode is! int ||
        channel is! String ||
        size is! int || size < 0 ||
        url is! String ||
        (sha256 != null &&
            (sha256 is! String ||
                !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256)))) {
      return null;
    }
    return PendingUpdateRecord(
      path: path,
      version: version,
      versionCode: versionCode,
      channel: channel,
      size: size,
      url: url,
      sha256: (sha256 as String?)?.toLowerCase(),
    );
  }
}

String encodePendingUpdateRecord(PendingUpdateRecord record) =>
    jsonEncode(record.toJson());

PendingUpdateRecord? decodePendingUpdateRecord(String raw) {
  try {
    return PendingUpdateRecord.fromJson(jsonDecode(raw));
  } on FormatException {
    return null;
  }
}

/// Persists the new pending-update record before best-effort legacy cleanup.
///
/// A successful [writeRecord] is the commit point. Cleanup failures are
/// reported but never propagated, so callers do not discard the committed APK.
Future<void> persistPendingUpdateRecord({
  required Future<bool> Function() writeRecord,
  required List<String> legacyKeys,
  required Future<bool> Function(String key) removeLegacyKey,
  void Function(String key, Object error, StackTrace stackTrace)?
      onCleanupError,
}) async {
  final saved = await writeRecord();
  if (!saved) {
    throw StateError('Could not persist pending update metadata');
  }

  for (final key in legacyKeys) {
    try {
      await removeLegacyKey(key);
    } catch (error, stackTrace) {
      try {
        onCleanupError?.call(key, error, stackTrace);
      } catch (_) {
        // Diagnostic callbacks must not invalidate the committed record.
      }
    }
  }
}
