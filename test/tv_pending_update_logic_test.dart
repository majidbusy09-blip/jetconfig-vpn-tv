import 'package:flutter_test/flutter_test.dart';
import 'package:jet_vpn_tv/tv_pending_update_logic.dart';

void main() {
  group('Pending update decision logic', () {
    PendingUpdateDecision evaluate({
      bool hasPath = true,
      bool fileExists = true,
      int actualSize = 2000,
      int expectedSize = 0,
      int pendingVersionCode = 115,
      int currentVersionCode = 114,
    }) =>
        evaluatePendingUpdate(
          hasPath: hasPath,
          fileExists: fileExists,
          actualSize: actualSize,
          expectedSize: expectedSize,
          pendingVersionCode: pendingVersionCode,
          currentVersionCode: currentVersionCode,
        );

    test('does nothing when no pending path is stored', () {
      final result = evaluate(hasPath: false, fileExists: false);
      expect(result.action, PendingUpdateAction.none);
      expect(result.isUsable, isFalse);
    });

    test('clears preferences when the stored file is missing', () {
      final result = evaluate(fileExists: false);
      expect(result.action, PendingUpdateAction.clearPreferences);
      expect(result.isUsable, isFalse);
    });

    test('deletes files smaller than the existing 1000-byte minimum', () {
      final result = evaluate(actualSize: 999);
      expect(result.action, PendingUpdateAction.deleteFileAndClearPreferences);
      expect(result.isUsable, isFalse);
    });

    test('preserves the existing 95 percent expected-size threshold', () {
      final below = evaluate(actualSize: 949, expectedSize: 1000);
      final boundary = evaluate(actualSize: 950, expectedSize: 1000);
      expect(below.action, PendingUpdateAction.deleteFileAndClearPreferences);
      expect(boundary.action, PendingUpdateAction.none);
      expect(boundary.isUsable, isTrue);
    });

    test('deletes a pending file when its version is already installed', () {
      final result = evaluate(pendingVersionCode: 114, currentVersionCode: 114);
      expect(result.action, PendingUpdateAction.deleteFileAndClearPreferences);
      expect(result.isUsable, isFalse);
    });

    test('keeps unknown version code compatible with the prior behavior', () {
      final result = evaluate(pendingVersionCode: 0);
      expect(result.action, PendingUpdateAction.none);
      expect(result.isUsable, isTrue);
    });

    test('accepts a sufficiently sized newer pending file', () {
      final result = evaluate(
        actualSize: 10000,
        expectedSize: 10000,
        pendingVersionCode: 115,
        currentVersionCode: 114,
      );
      expect(result.action, PendingUpdateAction.none);
      expect(result.isUsable, isTrue);
    });

    test('ignores expected size when it is unknown or non-positive', () {
      final unknown = evaluate(actualSize: 1000, expectedSize: 0);
      final negative = evaluate(actualSize: 1000, expectedSize: -10);
      expect(unknown.isUsable, isTrue);
      expect(negative.isUsable, isTrue);
    });
  });
}
