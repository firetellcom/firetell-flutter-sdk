import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:firetell_flutter_sdk/src/constants/signaling.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwt({required int exp, String sub = 'agent_1'}) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256'})}.'
      '${seg({'sub': sub, 'domain': 'ws_test.firetell.app', 'exp': exp})}.sig';
}

int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// Minimal Firetell per-call signaling server.
class _FakeSignalingServer {
  late final HttpServer _server;
  final sockets = <WebSocket>[];
  final received = <Map<String, dynamic>>[];

  /// Reply `session.connected` to `session.connect`.
  bool autoConnect = true;

  /// Reply `session.pong` to `session.ping`.
  bool replyPong = true;

  /// Accept WebSocket upgrades (false → HTTP 503).
  bool acceptConnections = true;

  String get url => 'ws://127.0.0.1:${_server.port}/ws';

  List<Map<String, dynamic>> events(String name) =>
      received.where((m) => m['event'] == name).toList();

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      if (!acceptConnections) {
        req.response.statusCode = HttpStatus.serviceUnavailable;
        await req.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(req);
      sockets.add(ws);
      ws.listen((raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        received.add(msg);
        if (msg['event'] == 'session.connect' && autoConnect) {
          ws.add(jsonEncode({'event': 'session.connected', 'data': {}}));
        } else if (msg['event'] == 'session.ping' && replyPong) {
          ws.add(jsonEncode({'event': 'session.pong', 'data': {}}));
        }
      });
    });
  }

  Future<void> dropLast([int code = 4001]) => sockets.last.close(code);

  Future<void> stop() async {
    for (final s in sockets) {
      await s.close();
    }
    await _server.close(force: true);
  }
}

Future<void> _waitFor(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late _FakeSignalingServer server;
  late List<SignalingStatus> statuses;

  Call newCall({String? token, String? fallback}) {
    final call = Call(
      iceServers: const [],
      fallbackTokenProvider: fallback == null ? null : () => fallback,
    )..callId = 'call_123';
    call.onSignaling.listen((e) => statuses.add(e.status));
    return call;
  }

  setUp(() async {
    SignalingConfig.reset();
    SignalingConfig.reconnectBaseDelay = const Duration(milliseconds: 50);
    SignalingConfig.reconnectMaxDelay = const Duration(milliseconds: 200);
    SignalingConfig.authTimeout = const Duration(milliseconds: 500);
    statuses = [];
    server = _FakeSignalingServer();
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    SignalingConfig.reset();
  });

  test('initial session.connect carries only call_token', () async {
    final token = _jwt(exp: _nowSec() + 3600);
    final call = newCall();
    await call.connectSignaling(server.url, token);

    expect(server.events('session.connect').single['data'], {
      'call_token': token,
    });
    await call.destroy();
  });

  test('auth timeout when session.connected never arrives', () async {
    server.autoConnect = false;
    final call = newCall();
    await expectLater(
      call.connectSignaling(server.url, _jwt(exp: _nowSec() + 3600)),
      throwsA(isA<TimeoutException>()),
    );
    await call.destroy();
  });

  test('unexpected drop → resumes with call_id + reconnect:true, flushes outbox',
      () async {
    final token = _jwt(exp: _nowSec() + 3600);
    final call = newCall()..active = true;
    await call.connectSignaling(server.url, token);

    server.autoConnect = false; // hold the resume until we queued an event
    await server.dropLast(4001);
    await _waitFor(() => call.isReconnecting);
    call.sendWsEvent('call.dtmf', {'digit': '5'});

    await _waitFor(() => server.events('session.connect').length == 2);
    expect(server.events('session.connect').last['data'], {
      'call_token': token,
      'call_id': 'call_123',
      'reconnect': true,
    });
    expect(server.events('call.dtmf'), isEmpty); // still queued

    // Let the next attempt succeed
    server.autoConnect = true;
    await _waitFor(() => statuses.contains(SignalingStatus.reconnected),
        timeout: const Duration(seconds: 8));

    expect(call.isReconnecting, isFalse);
    expect(statuses.first, SignalingStatus.reconnecting);
    await _waitFor(() => server.events('call.dtmf').length == 1);
    expect(server.events('call.dtmf').single['data'], {'digit': '5'});
    expect(call.callState, isNot(CallState.ended));
    await call.destroy();
  });

  test('close code 1000 → no reconnect, active call ends', () async {
    final call = newCall()..active = true;
    final states = <CallState>[];
    call.onStateChange.listen((e) => states.add(e.state));
    await call.connectSignaling(server.url, _jwt(exp: _nowSec() + 3600));

    await server.dropLast(1000);
    await _waitFor(() => call.callState == CallState.ended);

    expect(statuses, isEmpty);
    expect(server.events('session.connect').length, 1);
    expect(states, contains(CallState.ended));
  });

  test('reconnect window elapses → failed + call ended', () async {
    SignalingConfig.reconnectWindow = const Duration(milliseconds: 600);
    final call = newCall()..active = true;
    String? endReason;
    call.onStateChange.listen((e) {
      if (e.state == CallState.ended) endReason ??= e.reason;
    });
    await call.connectSignaling(server.url, _jwt(exp: _nowSec() + 3600));

    server.acceptConnections = false;
    await server.dropLast(4001);

    await _waitFor(() => statuses.contains(SignalingStatus.failed));
    expect(statuses.first, SignalingStatus.reconnecting);
    expect(call.callState, CallState.ended);
    expect(endReason, 'Signaling connection lost');
  });

  test('expired call_token → agent JWT used on resume', () async {
    final expiredToken = _jwt(exp: _nowSec() - 10);
    final agentJwt = _jwt(exp: _nowSec() + 3600, sub: 'agent_jwt');
    final call = newCall(fallback: agentJwt)..active = true;
    await call.connectSignaling(server.url, expiredToken);

    await server.dropLast(4001);
    await _waitFor(() => statuses.contains(SignalingStatus.reconnected));

    final connects = server.events('session.connect');
    expect(connects.first['data']['call_token'], expiredToken);
    expect(connects.last['data']['call_token'], agentJwt);
    await call.destroy();
  });

  test('sends session.ping periodically; pong keeps connection alive',
      () async {
    SignalingConfig.pingInterval = const Duration(milliseconds: 100);
    SignalingConfig.idleTimeout = const Duration(milliseconds: 250);
    final call = newCall()..active = true;
    await call.connectSignaling(server.url, _jwt(exp: _nowSec() + 3600));

    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(server.events('session.ping').length, greaterThanOrEqualTo(4));
    expect(statuses, isEmpty);
    expect(server.events('session.connect').length, 1);
    await call.destroy();
  });

  test('no inbound traffic past idle timeout → reconnect', () async {
    SignalingConfig.pingInterval = const Duration(milliseconds: 100);
    SignalingConfig.idleTimeout = const Duration(milliseconds: 250);
    server.replyPong = false;
    final call = newCall()..active = true;
    await call.connectSignaling(server.url, _jwt(exp: _nowSec() + 3600));

    await _waitFor(() => statuses.contains(SignalingStatus.reconnected));
    expect(server.events('session.connect').last['data']['reconnect'], true);
    await call.destroy();
  });

  test('destroy closes with 1000 and does not reconnect', () async {
    final call = newCall()..active = true;
    await call.connectSignaling(server.url, _jwt(exp: _nowSec() + 3600));
    final ws = server.sockets.single;

    await call.destroy(sendHangup: true);
    await ws.done;

    expect(ws.closeCode, 1000);
    expect(server.events('call.hangup').length, 1);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.events('session.connect').length, 1);
    expect(statuses, isEmpty);
  });

  test('JwtDecoder.isExpired', () {
    expect(JwtDecoder.isExpired(_jwt(exp: _nowSec() - 1)), isTrue);
    expect(JwtDecoder.isExpired(_jwt(exp: _nowSec() + 10)), isTrue); // 30s skew
    expect(JwtDecoder.isExpired(_jwt(exp: _nowSec() + 3600)), isFalse);
    expect(JwtDecoder.isExpired('garbage'), isFalse);
  });
}
