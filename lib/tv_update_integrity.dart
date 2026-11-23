import 'package:crypto/crypto.dart';

/// Returns true only for a 64-character hexadecimal SHA-256 digest.
bool isValidSha256(String value) =>
    RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

/// Computes the SHA-256 digest of a byte stream without loading the whole file.
Future<String> calculateSha256(Stream<List<int>> bytes) async {
  final digest = await sha256.bind(bytes).first;
  return digest.toString();
}

/// Compares an expected manifest digest with a computed digest.
bool sha256Matches(String expected, String actual) {
  return isValidSha256(expected) &&
      isValidSha256(actual) &&
      expected.toLowerCase() == actual.toLowerCase();
}
