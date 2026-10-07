import 'dart:convert';

import '../models/jwt_payload.dart';

/// Lightweight JWT payload decoder.
///
/// Decodes the payload segment of a JWT token without verifying
/// the signature. Matches the browser SDK's `_parseJwt()` behavior.
class JwtDecoder {
  JwtDecoder._();

  /// Decode the payload of a JWT token string.
  ///
  /// Returns `null` if the token is malformed or missing required claims.
  static JwtPayload? decode(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;

      final payload = parts[1];
      // Normalize base64url to base64
      final normalized = base64Url.normalize(payload);
      final jsonString = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      // Require `sub` and `domain` claims (same as browser SDK)
      if (json['sub'] == null || json['domain'] == null) return null;

      return JwtPayload.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Whether [token]'s `exp` claim is in the past (with [skew] tolerance).
  ///
  /// Returns `false` if the token has no readable `exp` claim. Does not
  /// require `sub`/`domain`, so it also works for `call_token`s.
  static bool isExpired(
    String token, {
    Duration skew = const Duration(seconds: 30),
  }) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return false;
      final json = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = json is Map ? json['exp'] : null;
      if (exp is! num) return false;
      final nowSec = DateTime.now().millisecondsSinceEpoch / 1000;
      return nowSec >= exp - skew.inSeconds;
    } catch (_) {
      return false;
    }
  }
}
