/// Authenticated session information returned after workspace metadata fetch.
class Session {
  const Session({
    required this.sessionId,
    required this.username,
    required this.displayName,
    required this.domain,
    required this.expiresAt,
  });

  /// Unique session identifier.
  final String sessionId;

  /// Agent username (from JWT `sub` claim).
  final String username;

  /// Display name for the agent.
  final String displayName;

  /// Workspace domain.
  final String domain;

  /// Session expiration timestamp (milliseconds since epoch).
  final int expiresAt;

  @override
  String toString() =>
      'Session(sessionId: $sessionId, username: $username, domain: $domain)';
}
