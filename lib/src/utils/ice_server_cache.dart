import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/ice_servers.dart';

const _storageKey = 'firetell_ice_servers';

/// Caches workspace ICE servers to local storage so they are available
/// during cold-start push-to-call flow (no FiretellClient needed).
///
/// Flow:
/// 1. `FiretellClient` fetches workspace metadata → gets ICE servers
/// 2. `IceServerCache.save(servers)` → persists to SharedPreferences
/// 3. On cold start, `IceServerCache.load()` → cached servers or defaults
class IceServerCache {
  IceServerCache._();

  /// Save ICE servers to local storage.
  ///
  /// Called by `FiretellClient` after fetching workspace metadata.
  static Future<void> save(List<Map<String, dynamic>> servers) async {
    if (servers.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(servers));
  }

  /// Load cached ICE servers from local storage.
  ///
  /// Returns the cached servers if available, otherwise [defaultIceServers].
  static Future<List<Map<String, dynamic>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return List.from(defaultIceServers);

      final decoded = jsonDecode(raw) as List<dynamic>;
      if (decoded.isEmpty) return List.from(defaultIceServers);

      return decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return List.from(defaultIceServers);
    }
  }

  /// Clear cached ICE servers (e.g., on logout / workspace switch).
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
