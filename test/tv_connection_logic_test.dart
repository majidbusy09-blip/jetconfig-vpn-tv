import 'package:flutter_test/flutter_test.dart';
import 'package:jet_vpn_tv/tv_connection_logic.dart';

void main() {
  group('connection status parsing', () {
    test('recognizes CONNECTED and CONNECT case-insensitively', () {
      expect(statusMeansConnected('CONNECTED'), isTrue);
      expect(statusMeansConnected(' connect '), isTrue);
      expect(statusMeansConnected('connected'), isTrue);
    });

    test('does not mistake disconnect messages for connected', () {
      expect(statusMeansConnected('DISCONNECTED'), isFalse);
      expect(statusMeansConnected('DISCONNECTING'), isFalse);
      expect(statusMeansConnected(null), isFalse);
      expect(statusMeansConnected('  '), isFalse);
    });

    test('recognizes known disconnected states', () {
      for (final state in ['DISCONNECTED', 'IDLE', 'STOPPED', 'NONE']) {
        expect(statusMeansDisconnected(state), isTrue, reason: state);
      }
      expect(statusMeansDisconnected('CONNECTED'), isFalse);
      expect(statusMeansDisconnected(null), isFalse);
    });
  });

  group('server ping ranking', () {
    test('places unknown and failed pings last', () {
      expect(serverPingScore(-1), 999999);
      expect(serverPingScore(0), 999999);
      expect(compareServerPing(85, -1), lessThan(0));
    });

    test('penalizes suspicious sub-30ms readings', () {
      expect(serverPingScore(1), 5001);
      expect(serverPingScore(29), 5029);
      expect(serverPingScore(30), 30);
      expect(compareServerPing(29, 30), greaterThan(0));
    });

    test('orders ordinary valid readings by latency', () {
      expect(compareServerPing(45, 90), lessThan(0));
      expect(compareServerPing(90, 45), greaterThan(0));
    });
  });
}
