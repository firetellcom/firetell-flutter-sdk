/// Decoded JWT payload claims from the agent authentication token.
class JwtPayload {
  const JwtPayload({
    required this.sub,
    required this.domain,
    this.exp,
    this.iat,
    this.aud,
    this.workspaceId,
  });

  factory JwtPayload.fromJson(Map<String, dynamic> json) {
    return JwtPayload(
      sub: json['sub'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      exp: (json['exp'] as num?)?.toInt(),
      iat: (json['iat'] as num?)?.toInt(),
      aud: json['aud'] as String?,
      workspaceId: json['workspace_id'] as String?,
    );
  }

  /// Subject — agent username.
  final String sub;

  /// Workspace domain.
  final String domain;

  /// Expiration timestamp (seconds since epoch).
  final int? exp;

  /// Issued-at timestamp (seconds since epoch).
  final int? iat;

  /// Audience claim.
  final String? aud;

  /// Workspace identifier.
  final String? workspaceId;

  /// Whether this token has expired.
  bool get isExpired {
    if (exp == null) return false;
    return DateTime.now().millisecondsSinceEpoch > exp! * 1000;
  }

  @override
  String toString() => 'JwtPayload(sub: $sub, domain: $domain)';
}
