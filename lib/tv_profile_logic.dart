import 'dart:convert';

/// Returns the persisted profile JSON after inserting [username] at the front.
///
/// This intentionally preserves the TV app's existing storage semantics:
/// exact username matching, most-recent-first ordering, and a 12-profile cap.
String upsertProfileJson(String raw, String username, String password) {
  List<dynamic> decoded;
  try {
    decoded = json.decode(raw) as List<dynamic>;
  } catch (_) {
    decoded = <dynamic>[];
  }

  final filtered = decoded
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .where((entry) => '${entry['u']}' != username)
      .toList();

  filtered.insert(0, <String, String>{'u': username, 'p': password});
  if (filtered.length > 12) {
    filtered.removeRange(12, filtered.length);
  }
  return json.encode(filtered);
}

/// Parses stored profile JSON using the app's existing compatibility rules.
List<Map<String, String>> loadProfilesFromJson(String raw) {
  try {
    final decoded = json.decode(raw) as List<dynamic>;
    return decoded
        .whereType<Map>()
        .map((entry) => <String, String>{
              'u': '${entry['u'] ?? ''}',
              'p': '${entry['p'] ?? ''}',
            })
        .where((entry) => entry['u']!.isNotEmpty)
        .toList();
  } catch (_) {
    return <Map<String, String>>[];
  }
}
