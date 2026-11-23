enum PendingUpdateAction {
  none,
  clearPreferences,
  deleteFileAndClearPreferences,
}

class PendingUpdateDecision {
  const PendingUpdateDecision({
    required this.action,
    required this.isUsable,
  });

  final PendingUpdateAction action;
  final bool isUsable;
}

/// Mirrors the existing pending-APK cleanup rules without touching disk.
///
/// This is a size/version consistency check only. It does not authenticate an
/// APK, verify its signature, or prove that the bytes match the download URL.
PendingUpdateDecision evaluatePendingUpdate({
  required bool hasPath,
  required bool fileExists,
  required int actualSize,
  required int expectedSize,
  required int pendingVersionCode,
  required int currentVersionCode,
}) {
  if (!hasPath) {
    return const PendingUpdateDecision(
      action: PendingUpdateAction.none,
      isUsable: false,
    );
  }

  if (!fileExists) {
    return const PendingUpdateDecision(
      action: PendingUpdateAction.clearPreferences,
      isUsable: false,
    );
  }

  if (actualSize < 1000 ||
      (expectedSize > 0 && actualSize < expectedSize * 0.95)) {
    return const PendingUpdateDecision(
      action: PendingUpdateAction.deleteFileAndClearPreferences,
      isUsable: false,
    );
  }

  if (pendingVersionCode > 0 &&
      currentVersionCode >= pendingVersionCode) {
    return const PendingUpdateDecision(
      action: PendingUpdateAction.deleteFileAndClearPreferences,
      isUsable: false,
    );
  }

  return const PendingUpdateDecision(
    action: PendingUpdateAction.none,
    isUsable: true,
  );
}
