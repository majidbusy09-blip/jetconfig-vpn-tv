import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_vpn_tv/tv_update_download.dart';
import 'package:jet_vpn_tv/tv_update_integrity.dart';

void main() {
  group('Verified APK promotion', () {
    late Directory directory;
    late File staged;
    late File destination;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('jet-tv-update-');
      staged = File('${directory.path}/update.apk.part');
      destination = File('${directory.path}/update.apk');
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('startup cleanup removes only interrupted staged APK files', () async {
      final interrupted = File('${directory.path}/interrupted.apk.part');
      final valid = File('${directory.path}/valid.apk');
      await interrupted.writeAsString('partial');
      await valid.writeAsString('verified');

      await cleanupStaleStagedApks(directory);

      expect(await interrupted.exists(), isFalse);
      expect(await valid.exists(), isTrue);
    });

    test('promotes a correctly hashed staged APK over the old destination',
        () async {
      await destination.writeAsString('old verified APK');
      final bytes = List<int>.generate(2048, (index) => index % 251);
      await staged.writeAsBytes(bytes);
      // Use the known digest of the actual test payload rather than a fixture
      // literal, then verify the promotion path end to end.
      final digest = await calculateSha256(staged.openRead());
      final promoted = await promoteVerifiedApk(
        stagedFile: staged,
        destinationFile: destination,
        expectedSha256: digest,
      );

      expect(promoted.path, destination.path);
      expect(await destination.readAsBytes(), bytes);
      expect(await staged.exists(), isFalse);
    });

    test('keeps the existing destination when digest verification fails',
        () async {
      await destination.writeAsString('old verified APK');
      await staged.writeAsBytes(List<int>.filled(2048, 7));

      await expectLater(
        promoteVerifiedApk(
          stagedFile: staged,
          destinationFile: destination,
          expectedSha256: 'a' * 64,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await destination.readAsString(), 'old verified APK');
      expect(await staged.exists(), isTrue);
    });

    test('keeps the existing destination when the staged APK is too small',
        () async {
      await destination.writeAsString('old verified APK');
      await staged.writeAsString('short');

      await expectLater(
        promoteVerifiedApk(
          stagedFile: staged,
          destinationFile: destination,
          expectedSha256: null,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await destination.readAsString(), 'old verified APK');
    });

    test('preserves legacy no-digest compatibility for a complete APK',
        () async {
      final bytes = List<int>.filled(2048, 9);
      await staged.writeAsBytes(bytes);

      await promoteVerifiedApk(
        stagedFile: staged,
        destinationFile: destination,
        expectedSha256: null,
      );

      expect(await destination.readAsBytes(), bytes);
    });
  });
}
