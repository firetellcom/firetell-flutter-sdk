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
