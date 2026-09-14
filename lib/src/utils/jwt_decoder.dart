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
}
