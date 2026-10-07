/// Fallback STUN ICE servers used when workspace metadata does not
/// provide custom ICE server configuration.
///
/// Matches the default servers in the browser SDK.
const List<Map<String, List<String>>> defaultIceServers = [
  {
    'urls': [
      'stun:stun.l.google.com:19302',
      'stun:stun1.l.google.com:19302',
    ],
  },
  {
    'urls': ['stun:stun.cloudflare.com:3478'],
  },
];

/// Refresh TURN credentials when they are valid for less than this
/// (covers a long call started right before expiry).
const iceRefreshThreshold = Duration(hours: 6);

/// Max wait for the ICE servers refresh request before falling back to cache.
const iceRefreshTimeout = Duration(seconds: 3);
