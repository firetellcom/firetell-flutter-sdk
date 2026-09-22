import 'dart:math';

/// Bidirectional registry that maps iOS CallKit UUIDs to Firetell server
/// call IDs (e.g. `call_xxxxxxxx`).
///
/// iOS CallKit requires call IDs to be UUIDs. Since the Firetell server uses
/// its own string format, this mapper generates a UUID per incoming call,
/// stores the `uuid ↔ serverCallId` mapping, and allows bidirectional lookup.
///
/// **Lifecycle:**
/// - Call [register] when a VoIP push arrives → get the UUID to pass to
///   `CallKitParams.id`.
/// - Call [serverIdFromUuid] when handling a CallKit event to get back the
///   server call ID needed for WebSocket / HTTP operations.
/// - Call [remove] when a call ends to avoid memory leaks.
///
/// Example:
/// ```dart
/// // On VoIP push received:
/// final iosUuid = CallIdMapper.instance.register(params.callId);
/// final callKitParams = CallKitParams(id: iosUuid, ...);
///
/// // On CallKit accept/decline event:
/// final iosUuid = event.callKitParams.id;
/// final serverId = CallIdMapper.instance.serverIdFromUuid(iosUuid);
/// ```
class CallIdMapper {
  CallIdMapper._();

  /// The singleton instance.
  static final instance = CallIdMapper._();

  final _uuidToServer = <String, String>{};
  final _serverToUuid = <String, String>{};

  // ─── Public API ────────────────────────────────────────────────────

  /// Register a server call ID and return its corresponding iOS UUID.
  ///
  /// If [serverCallId] is already registered, the existing UUID is returned.
  String register(String serverCallId) {
    final existing = _serverToUuid[serverCallId];
    if (existing != null) return existing;

    final uuid = _generateUuidV4();
    _uuidToServer[uuid] = serverCallId;
    _serverToUuid[serverCallId] = uuid;
    return uuid;
  }

  /// Lookup the server call ID for a given iOS CallKit UUID.
  ///
  /// Returns `null` if not found (e.g. the call was never registered or
  /// the UUID was already cleaned up).
  String? serverIdFromUuid(String uuid) => _uuidToServer[uuid];

  /// Lookup the iOS UUID for a given server call ID.
  ///
  /// Returns `null` if not found.
  String? uuidFromServerId(String serverId) => _serverToUuid[serverId];

  /// Remove both entries for a given server call ID.
  ///
  /// Call this after a call ends or is declined to prevent memory leaks.
  void remove(String serverCallId) {
    final uuid = _serverToUuid.remove(serverCallId);
    if (uuid != null) _uuidToServer.remove(uuid);
  }

  /// Remove both entries for a given iOS UUID.
  void removeByUuid(String uuid) {
    final serverId = _uuidToServer.remove(uuid);
    if (serverId != null) _serverToUuid.remove(serverId);
  }

  /// Clear all mappings (e.g. on logout).
  void clear() {
    _uuidToServer.clear();
    _serverToUuid.clear();
  }

  /// Returns the number of currently tracked calls.
  int get length => _serverToUuid.length;

  // ─── UUID v4 Generation ────────────────────────────────────────────

  static final _random = Random.secure();

  /// Generate a RFC 4122 version 4 UUID using `dart:math`.
  ///
  /// No external package required — uses `Random.secure()` which is
  /// cryptographically strong on both iOS and Android.
  static String _generateUuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));

    // Set version bits (version 4)
    bytes[6] = (bytes[6] & 0x0f) | 0x40;

    // Set variant bits (RFC 4122 variant)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
