import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Generates or retrieves a persistent unique device ID.
///
/// Prefers the native hardware device ID:
/// - **iOS**: `identifierForVendor` (stable per vendor/app reinstall)
/// - **Android**: `androidId` (stable per device + factory-reset)
///
/// Falls back to a randomly generated UUID (persisted via
/// `SharedPreferences`) when the native ID is unavailable.
class DeviceIdHelper {
  DeviceIdHelper._();

  static const _storageKey = 'firetell_device_id';
  static String? _cached;

  /// Get the device ID — returns the native hardware ID when available,
  /// otherwise generates and persists a fallback UUID.
  static Future<String> getOrCreate() async {
    // Return cached value if already resolved
    if (_cached != null) return _cached!;

    // Try native device ID first
    final nativeId = await _getNativeDeviceId();
    if (nativeId != null && nativeId.trim().isNotEmpty) {
      _cached = 'mob_$nativeId';
      return _cached!;
    }

    // Fallback: check SharedPreferences for a previously generated ID
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_storageKey);
    if (existing != null && existing.trim().isNotEmpty) {
      _cached = existing;
      return _cached!;
    }

    // Generate a new fallback UUID
    final newId = 'mob_${const Uuid().v4()}';
    await prefs.setString(_storageKey, newId);
    _cached = newId;
    return _cached!;
  }

  /// Clear the stored device ID (e.g., on logout).
  static Future<void> clear() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// Attempt to retrieve the native hardware device ID.
  static Future<String?> _getNativeDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor;
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      }
    } catch (_) {
      // device_info_plus unavailable or platform not supported
    }
    return null;
  }
}
