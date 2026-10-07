import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'call.dart';
import 'constants/api_endpoints.dart';
import 'constants/ice_servers.dart';
import 'enums/enums.dart';
import 'models/models.dart';
import 'push/push_token_service.dart';
import 'utils/device_id.dart';
import 'utils/jwt_decoder.dart';
import 'utils/ice_server_cache.dart';
import 'utils/sse_stream_client.dart';

/// SDK version.
const sdkVersion = '1.1.2';

/// Main Firetell client for managing VoIP calls and Call Center SMS conversations.
///
/// Handles authentication, workspace metadata fetching, SSE real-time event
/// streaming, call lifecycle management, and SMS inbox/messaging.
///
/// Usage:
/// ```dart
/// final client = FiretellClient(
///   jwt: 'your_agent_jwt',
///   domain: 'ws_123.firetell.app',
/// );
///
/// final session = await client.ready;
///
/// // Outbound call
/// final call = await client.makeOutboundCall(to: '+1234567890');
///
/// // Listen for incoming calls
/// client.onCallRing.listen((params) {
///   // Show incoming call UI
/// });
///
/// // Call Center SMS Inbox
/// final inbox = await client.getConversations();
/// client.onMessageReceived.listen((event) {
///   print('New SMS from ${event.from}: ${event.body}');
/// });
/// ```
class FiretellClient {
  /// Create a new FiretellClient.
  ///
  /// [jwt] — Agent authentication JWT.
  /// [domain] — Workspace API domain (e.g. `ws_123.firetell.app`
  /// or `https://ws_123.firetell.app`).
  FiretellClient({
    required String jwt,
    required String domain,
  })  : _jwt = jwt,
        _jwtPayload = JwtDecoder.decode(jwt) {
    if (jwt.isEmpty) throw ArgumentError('jwt is required');
    if (_jwtPayload == null) throw ArgumentError('Invalid JWT');

    _baseUrl = _validateDomain(domain);
    _readyCompleter = Completer<Session>();
    _fetchWorkspaceMetadata();
  }

  // ─── Public Properties ────────────────────────────────────────────

  /// Current active calls: `Map<call_id, Call>`.
  final Map<String, Call> activeCalls = {};

  /// ICE servers from workspace metadata (or defaults).
  ///
  /// May contain short-lived TURN credentials; use [ensureIceServers] to get
  /// a list that is guaranteed fresh (the SDK does this before every call).
  List<Map<String, dynamic>> iceServers = List.from(defaultIceServers);

  /// Local time at which the current TURN credentials expire, or `null` if
  /// the ICE servers do not expire (no TURN configured).
  ///
  /// Computed as `now + ice_servers_ttl` using the device clock (the server's
  /// `ice_servers_expires_at` is ignored to avoid clock-skew issues).
  DateTime? get iceServersExpiresAt => _iceServersExpiresAt;

  /// Whether the SSE stream is currently connected.
  bool get isConnected => _connected;

  /// The SDK version string.
  String get version => sdkVersion;

  /// Workspace base URL.
  String get baseUrl => _baseUrl;

  /// Current JWT.
  String get jwt => _jwt;

  /// Current session info (null if not yet authenticated).
  Session? get session => _session;

  /// Decoded JWT payload.
  JwtPayload? get jwtPayload => _jwtPayload;

  /// Future that completes when the client is fully initialized.
  Future<Session> get ready => _readyCompleter.future;

  // ─── Event Streams ─────────────────────────────────────────────────

  final _callRingController = StreamController<CallRingParams>.broadcast();
  final _callOfferController = StreamController<Call>.broadcast();
  final _callCreatedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _callStartedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _callAnsweredController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _callEndedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _callCanceledController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _agentStateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _sessionController = StreamController<Session?>.broadcast();
  final _errorController = StreamController<Object>.broadcast();
  final _connectionStateController =
      StreamController<SseConnectionState>.broadcast();

  // Call Center SMS real-time streams
  final _messageReceivedController =
      StreamController<MessageReceivedEvent>.broadcast();
  final _messageSentController =
      StreamController<MessageSentEvent>.broadcast();
  final _messageUpdatedController =
      StreamController<MessageUpdatedEvent>.broadcast();
  final _conversationUpdatedController =
      StreamController<ConversationUpdatedEvent>.broadcast();

  /// Incoming call ring notification (from SSE stream).
  Stream<CallRingParams> get onCallRing => _callRingController.stream;

  /// Incoming call offer with SDP ready (Call has WS connected).
  Stream<Call> get onCallOffer => _callOfferController.stream;

  /// New call created in workspace.
  Stream<Map<String, dynamic>> get onCallCreated =>
      _callCreatedController.stream;

  /// Call started (ringing at destination).
  Stream<Map<String, dynamic>> get onCallStarted =>
      _callStartedController.stream;

  /// Call answered.
  Stream<Map<String, dynamic>> get onCallAnswered =>
      _callAnsweredController.stream;

  /// Call ended.
  Stream<Map<String, dynamic>> get onCallEnded => _callEndedController.stream;

  /// Call canceled (before answer).
  Stream<Map<String, dynamic>> get onCallCanceled =>
      _callCanceledController.stream;

  /// Agent state changed.
  Stream<Map<String, dynamic>> get onAgentState =>
      _agentStateController.stream;

  /// Session state changed (null on logout/destroy).
  Stream<Session?> get onSession => _sessionController.stream;

  /// Error event.
  Stream<Object> get onError => _errorController.stream;

  /// SSE connection state changes.
  Stream<SseConnectionState> get onConnectionState =>
      _connectionStateController.stream;

  /// Inbound SMS/MMS message received from customer.
  Stream<MessageReceivedEvent> get onMessageReceived =>
      _messageReceivedController.stream;

  /// Outbound SMS/MMS message sent by any agent in the workspace/team.
  Stream<MessageSentEvent> get onMessageSent =>
      _messageSentController.stream;

  /// Message carrier delivery status updated (`queued`, `sent`, `delivered`, `failed`).
  Stream<MessageUpdatedEvent> get onMessageUpdated =>
      _messageUpdatedController.stream;

  /// Conversation thread updated (status, assignment, unread count, or last message).
  Stream<ConversationUpdatedEvent> get onConversationUpdated =>
      _conversationUpdatedController.stream;

  // ─── Private State ─────────────────────────────────────────────────

  String _jwt;
  JwtPayload? _jwtPayload;
  late String _baseUrl;
  List<String> _wsServers = [];
  Session? _session;
  bool _connected = false;
  late Completer<Session> _readyCompleter;
  SseStreamClient? _sseClient;
  StreamSubscription<SseEvent>? _sseSub;
  StreamSubscription<SseConnectionState>? _sseStateSub;
  DateTime? _iceServersExpiresAt;
  Future<bool>? _iceRefreshFuture;
  bool _metadataLoaded = false;

  // ─── Initialization ────────────────────────────────────────────────

  String _validateDomain(String domain) {
    if (domain.isEmpty) throw ArgumentError('Workspace domain is required');
    var d = domain;
    if (d.endsWith('/')) d = d.substring(0, d.length - 1);
    if (!d.startsWith('https://') && !d.startsWith('http://')) {
      d = 'https://$d';
    }
    return d;
  }

  Future<void> _fetchWorkspaceMetadata() async {
    try {
      final uri = Uri.parse('$_baseUrl${ApiEndpoints.workspaceMetadata}');
      final response = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      });

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _wsServers = (data['ws_servers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      _applyIceServers(data);
      _metadataLoaded = true;

      // Start SSE event stream
      _initEventStream();

      // Mark session ready
      final session = Session(
        sessionId: 'ses_${DateTime.now().millisecondsSinceEpoch}',
        username: _jwtPayload?.sub ?? '',
        displayName: _jwtPayload?.sub ?? '',
        domain: _jwtPayload?.domain ?? '',
        expiresAt: (_jwtPayload?.exp ?? 0) * 1000,
      );
      _session = session;
      _sessionController.add(session);
      _readyCompleter.complete(session);
    } catch (e) {
      developer.log(
        'FiretellClient: Error fetching workspace metadata: $e',
        name: 'FiretellSDK',
      );
      _readyCompleter.completeError(
        e is Exception ? e : Exception('Failed to fetch workspace metadata'),
      );
    }
  }

  // ─── ICE Servers / TURN Credentials ────────────────────────────────

  /// Store ICE servers and compute their local expiry from the server-provided
  /// TTL (TTL-based, so it is not affected by device clock skew).
  void _applyIceServers(Map<String, dynamic> data) {
    final rawIce = data['ice_servers'];
    iceServers = rawIce is List && rawIce.isNotEmpty
        ? rawIce.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : List.from(defaultIceServers);

    final rawTtl = data['ice_servers_ttl'];
    final ttl = rawTtl is num ? rawTtl : num.tryParse('${rawTtl ?? ''}');
    _iceServersExpiresAt = ttl != null && ttl > 0
        ? DateTime.now().add(Duration(milliseconds: (ttl * 1000).round()))
        : null;

    // Cache for cold-start push-to-call flow
    unawaited(
      IceServerCache.save(iceServers, expiresAt: _iceServersExpiresAt)
          .catchError((Object _) {}),
    );
  }

  /// Ensure ICE servers (TURN credentials) stay valid for at least
  /// [minValidity] (default 6h), refreshing from the server when needed.
  ///
  /// Never throws: on failure the cached servers are returned (STUN keeps
  /// working even if TURN credentials expired). Called automatically before
  /// each call's `RTCPeerConnection` is created, and prefetched (without
  /// awaiting) when an incoming call rings.
  Future<List<Map<String, dynamic>>> ensureIceServers({
    Duration minValidity = iceRefreshThreshold,
  }) async {
    // Workspace metadata (initial ICE servers) still loading: wait for it
    // briefly instead of issuing a duplicate request.
    if (!_metadataLoaded && !_readyCompleter.isCompleted) {
      try {
        await ready.timeout(iceRefreshTimeout);
      } catch (_) {
        // Fall through with whatever is cached.
      }
    }

    final expiresAt = _iceServersExpiresAt;
    if (expiresAt == null ||
        expiresAt.difference(DateTime.now()) > minValidity) {
      return iceServers;
    }
    await refreshIceServers();
    return iceServers;
  }

  /// Fetch fresh ICE servers (TURN credentials) from
  /// `GET /api/v1/ice-servers`.
  ///
  /// Concurrent calls share the same in-flight request. Times out after 3s.
  /// Never throws; returns `true` if the servers were refreshed, `false` on
  /// failure (cached servers are kept).
  Future<bool> refreshIceServers() {
    return _iceRefreshFuture ??= _fetchIceServers().whenComplete(() {
      _iceRefreshFuture = null;
    });
  }

  Future<bool> _fetchIceServers() async {
    if (_jwt.isEmpty) return false;
    final httpClient = http.Client();
    try {
      final uri = Uri.parse('$_baseUrl${ApiEndpoints.iceServers}');
      final response = await httpClient.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      }).timeout(iceRefreshTimeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      _applyIceServers(jsonDecode(response.body) as Map<String, dynamic>);
      return true;
    } catch (e) {
      developer.log(
        'FiretellClient: ICE servers refresh failed, using cached servers: $e',
        name: 'FiretellSDK',
      );
      return false;
    } finally {
      // Closing the client also aborts the request on timeout.
      httpClient.close();
    }
  }

  // ─── SSE Event Stream ──────────────────────────────────────────────

  void _initEventStream() {
    _sseSub?.cancel();
    _sseStateSub?.cancel();
    _sseClient?.close();

    final sseUrl = '$_baseUrl${ApiEndpoints.eventStream}';
    _sseClient = SseStreamClient(url: sseUrl, token: _jwt);

    _sseSub = _sseClient!.events.listen(_handleSseEvent);
    _sseStateSub = _sseClient!.connectionState.listen((state) {
      _connected = state == SseConnectionState.connected;
      if (!_connectionStateController.isClosed) {
        _connectionStateController.add(state);
      }
    });

    _sseClient!.connect();
  }

  void _handleSseEvent(SseEvent msg) {
    final event = msg.event;
    final data = msg.data as Map<String, dynamic>? ?? {};

    switch (event) {
      case 'call.ring':
        // Refresh TURN credentials in parallel with ringing so accept() is fast
        unawaited(ensureIceServers());
        final ringParams = CallRingParams(
          callId: _extractCallId(data),
          callToken: data['call_token'] as String? ?? '',
          wsUrl: data['ws_url'] as String?,
          callerNumber: _extractNestedString(data, 'from', 'number') ??
              data['caller_number'] as String? ??
              '',
          callerName: _extractNestedString(data, 'from', 'name') ??
              data['caller_name'] as String? ??
              '',
          callerAvatar: _extractNestedString(data, 'from', 'avatar') ??
              data['caller_avatar'] as String?,
          calleeNumber: _extractNestedString(data, 'to', 'number') ??
              data['callee_number'] as String? ??
              '',
          calleeName: _extractNestedString(data, 'to', 'name') ??
              data['callee_name'] as String? ??
              '',
          isTransfer: data['is_transfer'] == true,
          transferReason: data['transfer_reason'] as String?,
          isVideo: data['is_video'] == true,
        );
        _callRingController.add(ringParams);

        // Auto-create call session if call_token is present
        if (ringParams.callToken.isNotEmpty) {
          final wsUrl = ringParams.wsUrl ??
              (_wsServers.isNotEmpty
                  ? _wsServers[0]
                  : 'wss://${_baseUrl.replaceFirst(RegExp(r'^https?://'), '')}/ws');
          unawaited(() async {
            try {
              await createCallSession(
                callToken: ringParams.callToken,
                wsUrl: wsUrl,
                callId: ringParams.callId,
                options: CallOptions(
                  to: ringParams.calleeNumber,
                  from: ringParams.callerNumber,
                  fromName: ringParams.callerName,
                  fromAvatar: ringParams.callerAvatar,
                  isVideo: ringParams.isVideo,
                  isTransfer: ringParams.isTransfer,
                  transferReason: ringParams.transferReason,
                ),
              );
            } catch (e) {
              developer.log(
                'FiretellClient: Error connecting call WS from SSE ring: $e',
                name: 'FiretellSDK',
              );
            }
          }());
        }

      case 'call.answered':
        final callId = _extractCallId(data);
        if (callId.isNotEmpty) {
          final call = activeCalls[callId];
          if (call != null && call.callState != CallState.active) {
            // Trigger state update on the call
          }
        }
        _callAnsweredController.add(data);

      case 'call.canceled':
        final callId = _extractCallId(data);
        if (callId.isNotEmpty) {
          final call = activeCalls[callId];
          if (call != null) {
            call.destroy(sendHangup: false);
          }
          activeCalls.remove(callId);
        }
        _callCanceledController.add(data);

      case 'call.ended':
        final callId = _extractCallId(data);
        if (callId.isNotEmpty) {
          final call = activeCalls[callId];
          if (call != null) {
            call.destroy(sendHangup: false);
          }
          activeCalls.remove(callId);
        }
        _callEndedController.add(data);

      case 'call.created':
        _callCreatedController.add(data);

      case 'call.started':
        _callStartedController.add(data);

      case 'agent.state' || 'agent.state.forced':
        _agentStateController.add(data);

      case 'message.received':
        final eventData = MessageReceivedEvent.fromJson(data);
        if (!_messageReceivedController.isClosed) {
          _messageReceivedController.add(eventData);
        }

      case 'message.sent':
        final eventData = MessageSentEvent.fromJson(data);
        if (!_messageSentController.isClosed) {
          _messageSentController.add(eventData);
        }

      case 'message.updated':
        final eventData = MessageUpdatedEvent.fromJson(data);
        if (!_messageUpdatedController.isClosed) {
          _messageUpdatedController.add(eventData);
        }

      case 'conversation.updated':
        final eventData = ConversationUpdatedEvent.fromJson(data);
        if (!_conversationUpdatedController.isClosed) {
          _conversationUpdatedController.add(eventData);
        }

      case 'system.error':
        developer.log(
          'SSE system error: $data',
          name: 'FiretellSDK',
        );
        if (data['code'] == 'SSE_LIMIT_EXCEEDED') {
          _sseClient?.close();
          _session = null;
          _errorController.add(
            Exception(data['message'] ?? 'SSE connection limit exceeded'),
          );
          _sessionController.add(null);
        }

      default:
        if (event != 'system.ping') {
          // Forward unhandled events for consumer flexibility
        }
    }
  }

  /// Ingest and parse an incoming push notification payload for SMS messages or conversations.
  ///
  /// Dispatches to [onMessageReceived] or [onConversationUpdated] if the push
  /// event matches `message.received` or `conversation.updated`.
  ///
  /// Returns `true` if the payload was recognized and handled.
  bool handlePushEvent(Map<String, dynamic> payload) {
    var data = payload;
    var event = payload['event']?.toString();

    // 1. Unwrap data if nested in 'data' map or 'data' JSON string (FCM payloads)
    if (payload['data'] != null) {
      if (payload['data'] is Map<String, dynamic>) {
        data = payload['data'] as Map<String, dynamic>;
        event ??= data['event']?.toString();
      } else if (payload['data'] is Map) {
        data = (payload['data'] as Map).cast<String, dynamic>();
        event ??= data['event']?.toString();
      } else if (payload['data'] is String) {
        try {
          final decoded = jsonDecode(payload['data'] as String);
          if (decoded is Map<String, dynamic>) {
            data = decoded;
            event ??= decoded['event']?.toString();
          } else if (decoded is Map) {
            data = decoded.cast<String, dynamic>();
            event ??= data['event']?.toString();
          }
        } catch (_) {}
      }
    }

    event ??= payload['event']?.toString() ??
        data['event']?.toString() ??
        payload['message_data']?['event']?.toString() ??
        payload['conversation_data']?['event']?.toString();

    if (event == 'message.received') {
      final msgEvent = MessageReceivedEvent.fromJson(data);
      if (!_messageReceivedController.isClosed) {
        _messageReceivedController.add(msgEvent);
      }
      return true;
    } else if (event == 'conversation.updated') {
      final convEvent = ConversationUpdatedEvent.fromJson(data);
      if (!_conversationUpdatedController.isClosed) {
        _conversationUpdatedController.add(convEvent);
      }
      return true;
    }
    return false;
  }

  // ─── REST API ──────────────────────────────────────────────────────

  /// Call the REST API to initiate a new outbound call.
  ///
  /// Returns call metadata including `call_id`, `call_token`, and `ws_url`.
  Future<MakeCallResponse> initiateCallRest(
    String to, {
    String? from,
    bool isVideo = false,
  }) async {
    final uri = Uri.parse('$_baseUrl${ApiEndpoints.makeCall}');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      },
      body: jsonEncode({
        'to': to,
        if (from != null) 'from': from,
        'type': isVideo ? 'video' : 'audio',
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final errData = _tryParseJson(response.body);
      throw Exception(
        errData?['message'] ??
            'HTTP ${response.statusCode}: Failed to make call',
      );
    }

    return MakeCallResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Fetch phone numbers (DIDs) accessible by the authenticated agent/team.
  ///
  /// Calls `GET /api/v1/call-center/phone-numbers` using the agent's JWT.
  ///
  /// Use these numbers as outbound caller ID (`from`) when calling external
  /// mobile or landline numbers (PSTN).
  Future<List<PhoneNumber>> getPhoneNumbers({
    int page = 1,
    int limit = 100,
  }) async {
    final res = await getPhoneNumbersResponse(page: page, limit: limit);
    return res.data;
  }

  /// Fetch paginated phone numbers response including metadata.
  Future<PhoneNumbersResponse> getPhoneNumbersResponse({
    int page = 1,
    int limit = 100,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl${ApiEndpoints.phoneNumbers}?page=$page&limit=$limit',
    );
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      },
    );

    if (response.statusCode != 200) {
      final errData = _tryParseJson(response.body);
      throw Exception(
        errData?['message'] ??
            'HTTP ${response.statusCode}: Failed to fetch phone numbers',
      );
    }

    return PhoneNumbersResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  // ─── Call Center SMS Conversations ─────────────────────────────────

  /// List conversation threads (SMS Inbox) for Call Center agents.
  ///
  /// Calls `GET /api/v1/call-center/conversations` using the agent's JWT.
  Future<ConversationsResponse> getConversations([
    ListConversationsQuery? query,
  ]) async {
    final qs = query?.toQueryParams();
    final uri = Uri.parse('$_baseUrl${ApiEndpoints.conversations}').replace(
      queryParameters: qs != null && qs.isNotEmpty ? qs : null,
    );

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      },
    );

    if (response.statusCode != 200) {
      final errData = _tryParseJson(response.body);
      throw Exception(
        errData?['message'] ??
            'HTTP ${response.statusCode}: Failed to fetch conversations',
      );
    }

    return ConversationsResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Get details of a single conversation thread.
  ///
  /// Calls `GET /api/v1/call-center/conversations/:id` using the agent's JWT.
  Future<Conversation> getConversation(String conversationId) async {
    final uri = Uri.parse(
      '$_baseUrl${ApiEndpoints.conversationDetails(conversationId)}',
    );
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      },
    );

    if (response.statusCode != 200) {
      final errData = _tryParseJson(response.body);
      throw Exception(
        errData?['message'] ??
            'HTTP ${response.statusCode}: Failed to fetch conversation',
      );
    }

    return Conversation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Start a new conversation thread or send initial outbound SMS to a client.
  ///
  /// Calls `POST /api/v1/call-center/conversations` using the agent's JWT.
  Future<StartConversationResponse> startConversation(
    StartConversationPayload payload,
  ) async {
    final target = payload.clientNumber.isNotEmpty
        ? payload.clientNumber
        : (payload.to ?? '');
    if (target.isEmpty) {
      throw ArgumentError('clientNumber is required to start a conversation');
    }

    final uri = Uri.parse('$_baseUrl${ApiEndpoints.conversations}');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      },
      body: jsonEncode(payload.toJson()),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final errData = _tryParseJson(response.body);
      throw Exception(
        errData?['message'] ??
            'HTTP ${response.statusCode}: Failed to start conversation',
      );
    }

    return StartConversationResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Update conversation thread metadata (assign agent, assign team, status open/closed).
  ///
  /// Calls `PATCH /api/v1/call-center/conversations/:id` using the agent's JWT.
  Future<Conversation> updateConversation(
    String conversationId,
    UpdateConversationPayload payload,
  ) async {
    final uri = Uri.parse(
      '$_baseUrl${ApiEndpoints.conversationDetails(conversationId)}',
    );
    final response = await http.patch(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      },
      body: jsonEncode(payload.toJson()),
    );

    if (response.statusCode != 200) {
      final errData = _tryParseJson(response.body);
      throw Exception(
        errData?['message'] ??
            'HTTP ${response.statusCode}: Failed to update conversation',
      );
    }

    return Conversation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Mark conversation messages as read by agent.
  ///
  /// Calls `PATCH /api/v1/call-center/conversations/:id/read` using the agent's JWT.
  Future<MarkAsReadResponse> markConversationAsRead(
    String conversationId,
  ) async {
    final uri = Uri.parse(
      '$_baseUrl${ApiEndpoints.conversationRead(conversationId)}',
    );
    final response = await http.patch(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      },
    );

    if (response.statusCode != 200) {
      final errData = _tryParseJson(response.body);
      throw Exception(
        errData?['message'] ??
            'HTTP ${response.statusCode}: Failed to mark conversation as read',
      );
    }

    return MarkAsReadResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Get message history for a conversation thread in chronological order.
  ///
  /// Calls `GET /api/v1/call-center/conversations/:id/messages` using the agent's JWT.
  Future<ConversationMessagesResponse> getConversationMessages(
    String conversationId, [
    ListMessagesQuery? query,
  ]) async {
    final qs = query?.toQueryParams();
    final uri = Uri.parse(
      '$_baseUrl${ApiEndpoints.conversationMessages(conversationId)}',
    ).replace(
      queryParameters: qs != null && qs.isNotEmpty ? qs : null,
    );

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      },
    );

    if (response.statusCode != 200) {
      final errData = _tryParseJson(response.body);
      throw Exception(
        errData?['message'] ??
            'HTTP ${response.statusCode}: Failed to fetch conversation messages',
      );
    }

    return ConversationMessagesResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Send SMS/MMS message to client in an existing conversation thread.
  ///
  /// Calls `POST /api/v1/call-center/conversations/:id/messages` using the agent's JWT.
  Future<ConversationMessage> sendConversationMessage(
    String conversationId,
    SendConversationMessagePayload payload,
  ) async {
    final uri = Uri.parse(
      '$_baseUrl${ApiEndpoints.conversationMessages(conversationId)}',
    );
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      },
      body: jsonEncode(payload.toJson()),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final errData = _tryParseJson(response.body);
      throw Exception(
        errData?['message'] ??
            'HTTP ${response.statusCode}: Failed to send message',
      );
    }

    return ConversationMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  // ─── Call Session Management ───────────────────────────────────────

  /// Create a new [Call] instance and connect its dedicated per-call
  /// WebSocket signaling channel.
  Future<Call> createCallSession({
    required String callToken,
    required String wsUrl,
    required String callId,
    CallOptions options = const CallOptions(),
  }) async {
    final call = Call(
      iceServers: iceServers,
      iceServersProvider: ensureIceServers,
      fallbackTokenProvider: _fallbackToken,
      options: options,
    );
    call.callId = callId;
    activeCalls[callId] = call;
    await call.connectSignaling(wsUrl, callToken);
    return call;
  }

  /// Initiate a new outbound call.
  ///
  /// Creates a [Call], sets up WebRTC media, gathers Full ICE candidates,
  /// calls the REST API, connects the per-call WebSocket, and sends
  /// the SDP offer.
  ///
  /// Returns the [Call] instance for controlling the call.
  Future<Call> makeOutboundCall({
    required String to,
    String? from,
    bool isVideo = false,
  }) async {
    final call = Call(
      iceServers: iceServers,
      iceServersProvider: ensureIceServers,
      fallbackTokenProvider: _fallbackToken,
      options: CallOptions(
        to: to,
        from: from ?? '',
        isVideo: isVideo,
      ),
    );

    try {
      // Setup WebRTC and gather Full ICE SDP
      final sdp = await call.prepareOffer();

      // REST API to create call
      final res = await initiateCallRest(to, from: from, isVideo: isVideo);
      call.callId = res.callId;
      activeCalls[res.callId] = call;

      // Connect dedicated per-call WebSocket
      await call.connectSignaling(res.wsUrl, res.callToken);

      // Send SDP offer over WebSocket
      call.sendWsEvent('call.offer', {'sdp': sdp.sdp});

      return call;
    } catch (e) {
      call.destroy(sendHangup: false);
      rethrow;
    }
  }

  /// Handle an incoming call from a VoIP push notification.
  ///
  /// Creates a [Call] instance from the push payload parameters and
  /// connects the signaling WebSocket. The call is NOT auto-answered —
  /// the consumer must call `call.accept()` when the user taps answer.
  ///
  /// ```dart
  /// final call = await client.handlePushIncomingCall(ringParams);
  /// // User taps "Answer" on CallKit / flutter_callkit_incoming
  /// await call.accept();
  /// ```
  Future<Call> handlePushIncomingCall(CallRingParams params) async {
    // Refresh TURN credentials in parallel (no-op if still valid / in flight)
    unawaited(ensureIceServers());

    final wsUrl = params.wsUrl ??
        (_wsServers.isNotEmpty
            ? _wsServers[0]
            : 'wss://${_baseUrl.replaceFirst(RegExp(r'^https?://'), '')}/ws');

    return createCallSession(
      callToken: params.callToken,
      wsUrl: wsUrl,
      callId: params.callId,
      options: CallOptions(
        to: params.calleeNumber,
        from: params.callerNumber,
        fromName: params.callerName,
        fromAvatar: params.callerAvatar,
        isVideo: params.isVideo,
        isTransfer: params.isTransfer,
        transferReason: params.transferReason,
      ),
    );
  }

  /// Send a call transfer via WebSocket or REST API fallback.
  Future<void> sendTransfer(
    String callId,
    String target, {
    String? reason,
  }) async {
    final call = activeCalls[callId];
    if (call != null) {
      await call.transfer(target, reason: reason);
      return;
    }

    // REST fallback
    final uri = Uri.parse('$_baseUrl${ApiEndpoints.transfer(callId)}');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwt',
      },
      body: jsonEncode({
        'target': target,
        if (reason != null) 'reason': reason,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final errData = _tryParseJson(response.body);
      throw Exception(
        errData?['message'] ??
            'HTTP ${response.statusCode}: Failed to transfer call',
      );
    }

    activeCalls.remove(callId);
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────

  /// Logout the agent — unregisters the device push token from the backend
  /// via `POST /api/v1/me/logout` (preventing incoming push notifications
  /// after logout), hangs up all active calls, closes the SSE stream,
  /// and cleans up the local session.
  ///
  /// If [deviceId] is omitted, it automatically uses the persistent device ID
  /// from [DeviceIdHelper.getOrCreate()].
  Future<void> logout({String? deviceId}) async {
    // 1. Unregister device push token from backend so device no longer rings
    try {
      final resolvedDeviceId = deviceId ?? await DeviceIdHelper.getOrCreate();
      await PushTokenService.logout(
        baseUrl: _baseUrl,
        jwt: _jwt,
        deviceId: resolvedDeviceId,
      );
    } catch (e) {
      developer.log(
        'FiretellClient.logout: failed to remove push token from backend: $e',
        name: 'FiretellSDK',
      );
    }

    // 2. Hangup all active calls
    for (final call in activeCalls.values) {
      call.destroy();
    }
    activeCalls.clear();

    // 3. Clean up local session and SSE stream
    _cleanupSession();
  }

  /// Fully destroy the client — cleanup everything without server
  /// communication.
  void destroy() {
    for (final call in activeCalls.values) {
      call.destroy();
    }
    activeCalls.clear();
    _sseSub?.cancel();
    _sseSub = null;
    _sseStateSub?.cancel();
    _sseStateSub = null;
    _sseClient?.dispose();
    _sseClient = null;
    _session = null;
    _jwtPayload = null;
    _jwt = '';
    _closeControllers();
  }

  void _cleanupSession() {
    _session = null;
    _sessionController.add(null);
    _sseSub?.cancel();
    _sseSub = null;
    _sseStateSub?.cancel();
    _sseStateSub = null;
    _sseClient?.close();
    _sseClient = null;
  }

  void _closeControllers() {
    _callRingController.close();
    _callOfferController.close();
    _callCreatedController.close();
    _callStartedController.close();
    _callAnsweredController.close();
    _callEndedController.close();
    _callCanceledController.close();
    _agentStateController.close();
    _sessionController.close();
    _errorController.close();
    _connectionStateController.close();

    _messageReceivedController.close();
    _messageSentController.close();
    _messageUpdatedController.close();
    _conversationUpdatedController.close();
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  /// Agent JWT used by [Call] when resuming signaling with an expired
  /// `call_token`.
  String? _fallbackToken() => _jwt.isEmpty ? null : _jwt;

  String _extractCallId(Map<String, dynamic> data) {
    return data['data']?['call_id']?.toString() ??
        data['data']?['id']?.toString() ??
        data['call_id']?.toString() ??
        data['id']?.toString() ??
        '';
  }

  String? _extractNestedString(
    Map<String, dynamic> data,
    String parentKey,
    String childKey,
  ) {
    final parent = data[parentKey];
    if (parent is Map) return parent[childKey]?.toString();
    return null;
  }

  Map<String, dynamic>? _tryParseJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
