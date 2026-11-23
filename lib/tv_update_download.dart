import 'dart:io';

import 'tv_update_integrity.dart';

/// Promotes a fully downloaded APK only after its size and optional digest
/// have been verified. The staged file must be in the same directory so the
/// rename stays on one filesystem. An existing destination is left untouched
/// when validation fails.
Future<File> promoteVerifiedApk({
  required File stagedFile,
  required File destinationFile,
  required String? expectedSha256,
}) async {
  if (!await stagedFile.exists()) {
    throw StateError('Staged APK does not exist');
  }

  if (await stagedFile.length() < 1000) {
    throw StateError('Staged APK is too small');
  }

  if (expectedSha256 != null) {
    final actualSha256 = await calculateSha256(stagedFile.openRead());
    if (!sha256Matches(expectedSha256, actualSha256)) {
      throw StateError('Staged APK SHA-256 mismatch');
    }
  }

  return stagedFile.rename(destinationFile.path);
}
