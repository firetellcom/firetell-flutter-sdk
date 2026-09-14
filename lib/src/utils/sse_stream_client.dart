import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Parsed SSE event from the server event stream.
class SseEvent {
  const SseEvent({
    required this.event,
    required this.data,
    this.id,
  });

  /// Event type (defaults to `"message"` if not specified by server).
  final String event;

  /// Parsed event data (JSON-decoded if valid JSON, otherwise raw string).
  final dynamic data;

  /// Optional event ID from the server.
  final String? id;

  @override
  String toString() => 'SseEvent(event: $event)';
}

/// Connection state of the SSE stream.
enum SseConnectionState { connecting, connected, disconnected }

/// Lightweight SSE (Server-Sent Events) stream client with
/// `Authorization: Bearer` header support.
///
/// Uses `http` package streamed requests to maintain a long-lived
/// connection. Parses the `text/event-stream` format and auto-reconnects
/// with exponential backoff on disconnection.
///
/// This is a Dart port of the browser SDK's `SseStreamClient`.
class SseStreamClient {
  SseStreamClient({
    required this.url,
    this.token,
    this.headers,
    this.initialReconnectDelay = const Duration(seconds: 3),
    this.maxReconnectDelay = const Duration(seconds: 60),
  });

  /// SSE endpoint URL.
  final String url;

  /// Bearer token for the `Authorization` header.
  final String? token;

  /// Additional HTTP headers to send.
  final Map<String, String>? headers;

  /// Initial delay before first reconnection attempt.
  final Duration initialReconnectDelay;

  /// Maximum reconnection delay (caps exponential backoff).
  final Duration maxReconnectDelay;

  final _eventController = StreamController<SseEvent>.broadcast();
  final _stateController =
      StreamController<SseConnectionState>.broadcast();

  http.Client? _httpClient;
  StreamSubscription<List<int>>? _streamSubscription;
  Timer? _reconnectTimer;
  Duration _currentReconnectDelay = Duration.zero;
  bool _isExplicitlyClosed = false;
  bool _connected = false;

  /// Stream of parsed SSE events.
  Stream<SseEvent> get events => _eventController.stream;

  /// Stream of connection state changes.
  Stream<SseConnectionState> get connectionState => _stateController.stream;

  /// Whether the stream is currently connected.
  bool get isConnected => _connected;

  /// Start or restart the SSE connection.
  void connect() {
    _isExplicitlyClosed = false;
    _currentReconnectDelay = initialReconnectDelay;
    _cleanup();
    _doConnect();
  }

  /// Stop the SSE connection and cancel reconnect timers.
  void close() {
    _isExplicitlyClosed = true;
    _connected = false;
    _cleanup();
    _emitState(SseConnectionState.disconnected);
  }

  /// Permanently close and release all resources.
  void dispose() {
    close();
    _eventController.close();
    _stateController.close();
  }

  // ─── Internal ──────────────────────────────────────────────────────

  Future<void> _doConnect() async {
    _emitState(SseConnectionState.connecting);

    _httpClient = http.Client();

    final requestHeaders = <String, String>{
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      if (token != null) 'Authorization': 'Bearer $token',
      ...?headers,
    };

    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(requestHeaders);

      final response = await _httpClient!.send(request);

      if (response.statusCode != 200) {
        throw http.ClientException(
          'SSE connection failed: HTTP ${response.statusCode}',
        );
      }

      _connected = true;
      _currentReconnectDelay = initialReconnectDelay;
      _emitState(SseConnectionState.connected);

      // Parse the SSE text/event-stream byte stream
      final buffer = StringBuffer();
      var currentEvent = 'message';
      var currentData = StringBuffer();
      var currentId = '';

      _streamSubscription = response.stream.listen(
        (bytes) {
          buffer.write(utf8.decode(bytes, allowMalformed: true));

          // Process complete lines
          final raw = buffer.toString();
          final lines = raw.split(RegExp(r'\r?\n'));

          // Keep the last potentially incomplete line in the buffer
          buffer.clear();
          buffer.write(lines.removeLast());

          for (final line in lines) {
            final trimmed = line.trim();

            if (trimmed.isEmpty) {
              // Empty line = end of SSE event block (\n\n)
              if (currentData.isNotEmpty) {
                final rawData = currentData.toString();
                dynamic parsedData = rawData;
                try {
                  parsedData = jsonDecode(rawData);
                } catch (_) {
                  // Keep as raw string if not valid JSON
                }
                _eventController.add(SseEvent(
                  event: currentEvent,
                  data: parsedData,
                  id: currentId.isNotEmpty ? currentId : null,
                ));
                currentEvent = 'message';
                currentData = StringBuffer();
                currentId = '';
              }
              continue;
            }

            // Comment / keep-alive ping
            if (trimmed.startsWith(':')) continue;

            if (trimmed.startsWith('event:')) {
              currentEvent = trimmed.substring(6).trim();
            } else if (trimmed.startsWith('data:')) {
              final dataPart = trimmed.substring(5).trim();
              if (currentData.isNotEmpty) {
                currentData.write('\n');
              }
              currentData.write(dataPart);
            } else if (trimmed.startsWith('id:')) {
              currentId = trimmed.substring(3).trim();
            }
          }
        },
        onDone: () {
          // Server closed the stream
          _connected = false;
          if (!_isExplicitlyClosed) {
            _scheduleReconnect();
          }
        },
        onError: (Object error) {
          _connected = false;
          if (!_isExplicitlyClosed) {
            _scheduleReconnect();
          }
        },
        cancelOnError: false,
      );
    } catch (error) {
      _connected = false;
      if (!_isExplicitlyClosed) {
        _scheduleReconnect();
      }
    }
  }

  void _scheduleReconnect() {
    if (_isExplicitlyClosed) return;
    _cleanup();
    _emitState(SseConnectionState.disconnected);

    // Exponential backoff with jitter
    final jitter = Duration(
      milliseconds: Random().nextInt(1000),
    );
    final delay = _currentReconnectDelay + jitter;
    _currentReconnectDelay = Duration(
      milliseconds: min(
        (_currentReconnectDelay.inMilliseconds * 2),
        maxReconnectDelay.inMilliseconds,
      ),
    );

    _emitState(SseConnectionState.connecting);
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_isExplicitlyClosed) {
        _doConnect();
      }
    });
  }

  void _emitState(SseConnectionState state) {
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  void _cleanup() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _httpClient?.close();
    _httpClient = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }
}
