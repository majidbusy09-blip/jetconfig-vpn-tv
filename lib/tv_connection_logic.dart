/// Pure connection-state and server-ranking rules used by the TV app.
///
/// Kept free of Flutter and platform dependencies so regression tests can
/// exercise the exact rules used by the runtime code.
bool statusMeansConnected(String? state) {
  final normalized = (state ?? '').toUpperCase().trim();
  if (normalized.isEmpty) return false;
  if (normalized.contains('DISCONNECT')) return false;
  return normalized == 'CONNECTED' || normalized == 'CONNECT';
}

bool statusMeansDisconnected(String? state) {
  final normalized = (state ?? '').toUpperCase().trim();
  return normalized.contains('DISCONNECT') ||
      normalized == 'IDLE' ||
      normalized == 'STOPPED' ||
      normalized == 'NONE';
}

/// Preserves the existing policy: unknown/non-positive pings sort last, and
/// sub-30ms readings are penalized as suspicious rather than preferred.
int serverPingScore(int pingMs) {
  if (pingMs <= 0) return 999999;
  if (pingMs < 30) return 5000 + pingMs;
  return pingMs;
}

int compareServerPing(int firstPingMs, int secondPingMs) =>
    serverPingScore(firstPingMs).compareTo(serverPingScore(secondPingMs));
