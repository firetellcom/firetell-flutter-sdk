import 'dart:convert';

import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _fakeJwt() {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${seg({'sub': 'agent_1', 'domain': 'ws_test.firetell.app', 'exp': 4102444800})}.'
      'sig';
}

const _turn = {
  'urls': ['turn:turn.firetell.app:3478'],
  'username': 'u1',
  'credential': 'c1',
};
const _turnFresh = {
  'urls': ['turn:turn.firetell.app:3478'],
  'username': 'u2',
  'credential': 'c2',
};
const _stun = {
  'urls': ['stun:stun.firetell.app:3478'],
};

/// Mock backend. Counts calls to `/api/v1/ice-servers`.
class _Backend {
  _Backend({
    required this.metadataTtl,
    this.refreshStatus = 200,
    this.refreshDelay = Duration.zero,
  });

  final Object? metadataTtl;
  final int refreshStatus;
  final Duration refreshDelay;
  int refreshCalls = 0;
  String? lastAuth;

  late final MockClient client = MockClient((req) async {
    switch (req.url.path) {
      case '/api/v1':
        return http.Response(
          jsonEncode({
            'ws_servers': ['wss://ws_test.firetell.app/ws'],
            'ice_servers': [_stun, _turn],
            'ice_servers_ttl': metadataTtl,
            'ice_servers_expires_at': '2000-01-01T00:00:00Z',
          }),
          200,
        );
      case '/api/v1/ice-servers':
        refreshCalls++;
        lastAuth = req.headers['Authorization'];
        await Future<void>.delayed(refreshDelay);
        if (refreshStatus != 200) return http.Response('boom', refreshStatus);
        return http.Response(
          jsonEncode({
            'ice_servers': [_stun, _turnFresh],
            'ice_servers_ttl': 86400,
            'ice_servers_expires_at': '2000-01-01T00:00:00Z',
          }),
          200,
        );
      default:
        // SSE stream etc. — keep it failing quietly.
        return http.Response('', 404);
    }
  });

  Future<T> run<T>(Future<T> Function() body) =>
      http.runWithClient(body, () => client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FiretellClient ICE servers / TURN refresh', () {
    test('computes local expiry from ice_servers_ttl (ignores expires_at)',
        () async {
      final backend = _Backend(metadataTtl: 86400);
      await backend.run(() async {
        final before = DateTime.now();
        final client = FiretellClient(jwt: _fakeJwt(), domain: 'ws_test.firetell.app');
        await client.ready;

        expect(client.iceServers, [_stun, _turn]);
        final exp = client.iceServersExpiresAt!;
        expect(
          exp.difference(before).inSeconds,
          inInclusiveRange(86400 - 5, 86400 + 5),
        );
        client.destroy();
      });
    });

    test('ttl null → no expiry, ensureIceServers never refreshes', () async {
      final backend = _Backend(metadataTtl: null);
      await backend.run(() async {
        final client = FiretellClient(jwt: _fakeJwt(), domain: 'ws_test.firetell.app');
        await client.ready;

        expect(client.iceServersExpiresAt, isNull);
        final servers = await client.ensureIceServers();
        expect(servers, [_stun, _turn]);
        expect(backend.refreshCalls, 0);
        client.destroy();
      });
    });

    test('valid > 6h → no refresh', () async {
      final backend = _Backend(metadataTtl: 86400);
      await backend.run(() async {
        final client = FiretellClient(jwt: _fakeJwt(), domain: 'ws_test.firetell.app');
        await client.ready;

        await client.ensureIceServers();
        expect(backend.refreshCalls, 0);
        client.destroy();
      });
    });

    test('valid < 6h → refreshes once, concurrent calls share request',
        () async {
      final backend = _Backend(metadataTtl: 3600);
      await backend.run(() async {
        final client = FiretellClient(jwt: _fakeJwt(), domain: 'ws_test.firetell.app');
        await client.ready;

        final results = await Future.wait([
          client.ensureIceServers(),
          client.ensureIceServers(),
          client.ensureIceServers(),
        ]);

        expect(backend.refreshCalls, 1);
        expect(backend.lastAuth, 'Bearer ${_fakeJwt()}');
        for (final r in results) {
          expect(r, [_stun, _turnFresh]);
        }
        expect(
          client.iceServersExpiresAt!.difference(DateTime.now()).inHours,
          greaterThanOrEqualTo(23),
        );

        // Now fresh → no further refresh
        await client.ensureIceServers();
        expect(backend.refreshCalls, 1);
        client.destroy();
      });
    });

    test('ensureIceServers waits for in-flight metadata instead of STUN',
        () async {
      final backend = _Backend(metadataTtl: 86400);
      await backend.run(() async {
        final client = FiretellClient(jwt: _fakeJwt(), domain: 'ws_test.firetell.app');
        // Called before `ready` completes
        final servers = await client.ensureIceServers();
        expect(servers, [_stun, _turn]);
        client.destroy();
      });
    });

    test('refresh error → no throw, keeps cached servers', () async {
      final backend = _Backend(metadataTtl: 3600, refreshStatus: 500);
      await backend.run(() async {
        final client = FiretellClient(jwt: _fakeJwt(), domain: 'ws_test.firetell.app');
        await client.ready;

        expect(await client.refreshIceServers(), isFalse);
        final servers = await client.ensureIceServers();
        expect(servers, [_stun, _turn]);
        client.destroy();
      });
    });

    test('refresh times out after 3s → no throw, keeps cached servers',
        () async {
      final backend = _Backend(
        metadataTtl: 3600,
        refreshDelay: const Duration(seconds: 10),
      );
      await backend.run(() async {
        final client = FiretellClient(jwt: _fakeJwt(), domain: 'ws_test.firetell.app');
        await client.ready;

        final sw = Stopwatch()..start();
        final servers = await client.ensureIceServers();
        sw.stop();

        expect(servers, [_stun, _turn]);
        expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
        client.destroy();
      });
    });
  });

  group('IceServerCache', () {
    test('returns cached servers while valid', () async {
      await IceServerCache.save(
        [_stun, _turn],
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(await IceServerCache.load(), [_stun, _turn]);
    });

    test('drops expired TURN entries, keeps STUN', () async {
      await IceServerCache.save(
        [_stun, _turn],
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(await IceServerCache.load(), [_stun]);
    });

    test('falls back to defaults when only expired TURN cached', () async {
      await IceServerCache.save(
        [_turn],
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      final loaded = await IceServerCache.load();
      expect(loaded.length, 2);
      expect(loaded.first['urls'], contains('stun:stun.l.google.com:19302'));
    });

    test('no expiry → servers returned as-is', () async {
      await IceServerCache.save([_stun, _turn]);
      expect(await IceServerCache.expiresAt(), isNull);
      expect(await IceServerCache.load(), [_stun, _turn]);
    });
  });
}
