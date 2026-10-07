import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/ice_servers.dart';

const _storageKey = 'firetell_ice_servers';
const _expiresAtKey = 'firetell_ice_servers_expires_at';

/// Caches workspace ICE servers to local storage so they are available
/// during cold-start push-to-call flow (no FiretellClient needed).
///
/// Flow:
/// 1. `FiretellClient` fetches workspace metadata → gets ICE servers
/// 2. `IceServerCache.save(servers, expiresAt: ...)` → persists to SharedPreferences
/// 3. On cold start, `IceServerCache.load()` → cached servers or defaults
///
/// TURN credentials are short-lived. When the cached credentials have
/// expired, [load] drops the TURN entries and keeps only STUN servers
/// (expired TURN credentials would just fail allocation).
class IceServerCache {
  IceServerCache._();

  /// Save ICE servers to local storage.
  ///
  /// [expiresAt] is the local time at which TURN credentials expire
  /// (computed from `ice_servers_ttl`). Pass `null` when the servers do not
  /// expire (e.g. STUN only).
  ///
  /// Called by `FiretellClient` after fetching / refreshing ICE servers.
  static Future<void> save(
    List<Map<String, dynamic>> servers, {
    DateTime? expiresAt,
  }) async {
    if (servers.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(servers));
    if (expiresAt != null) {
      await prefs.setInt(_expiresAtKey, expiresAt.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_expiresAtKey);
    }
  }

  /// Load cached ICE servers from local storage.
  ///
  /// Returns the cached servers if available, otherwise [defaultIceServers].
  /// If the cached TURN credentials have expired, TURN entries are removed
  /// (STUN entries are kept; falls back to [defaultIceServers] if none remain).
  static Future<List<Map<String, dynamic>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return List.from(defaultIceServers);

      final decoded = jsonDecode(raw) as List<dynamic>;
      if (decoded.isEmpty) return List.from(defaultIceServers);

      var servers = decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final expiresAtMs = prefs.getInt(_expiresAtKey);
      if (expiresAtMs != null &&
          DateTime.now().millisecondsSinceEpoch >= expiresAtMs) {
        servers = servers.where((s) => !_isTurnServer(s)).toList();
        if (servers.isEmpty) return List.from(defaultIceServers);
      }

      return servers;
    } catch (_) {
      return List.from(defaultIceServers);
    }
  }

  /// Local time at which the cached TURN credentials expire, or `null`
  /// if nothing is cached / the cached servers do not expire.
  static Future<DateTime?> expiresAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_expiresAtKey);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  /// Clear cached ICE servers (e.g., on logout / workspace switch).
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_expiresAtKey);
  }

  static bool _isTurnServer(Map<String, dynamic> server) {
    final urls = server['urls'] ?? server['url'];
    final list = urls is List ? urls : [urls];
    return list.any((u) {
      final s = u?.toString().toLowerCase() ?? '';
      return s.startsWith('turn:') || s.startsWith('turns:');
    });
  }
}
