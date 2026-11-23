import 'package:flutter_test/flutter_test.dart';
import 'package:jet_vpn_tv/tv_pending_update_record.dart';

void main() {
  group('Pending update record persistence', () {
    test('legacy cleanup failure does not invalidate a committed record', () async {
      var recordWritten = false;
      final attemptedKeys = <String>[];
      final cleanupErrors = <String>[];

      await persistPendingUpdateRecord(
        writeRecord: () async {
          recordWritten = true;
          return true;
        },
        legacyKeys: const ['old_path', 'old_version', 'old_hash'],
        removeLegacyKey: (key) async {
          attemptedKeys.add(key);
          if (key == 'old_path') {
            throw StateError('simulated preferences cleanup failure');
          }
          return true;
        },
        onCleanupError: (key, error, stackTrace) {
          cleanupErrors.add(key);
        },
      );

      expect(recordWritten, isTrue);
      expect(attemptedKeys, ['old_path', 'old_version', 'old_hash']);
      expect(cleanupErrors, ['old_path']);
    });

    test('failed record write aborts before legacy cleanup', () async {
      final attemptedKeys = <String>[];

      await expectLater(
        persistPendingUpdateRecord(
          writeRecord: () async => false,
          legacyKeys: const ['old_path'],
          removeLegacyKey: (key) async {
            attemptedKeys.add(key);
            return true;
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(attemptedKeys, isEmpty);
    });
  });
}
