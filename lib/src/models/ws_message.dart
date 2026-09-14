/// Native WebSocket event-based message shape used for per-call signaling.
///
/// Format: `{ "event": "<event_name>", "data": { ... } }`
class WsEventMessage {
  const WsEventMessage({required this.event, this.data});

  factory WsEventMessage.fromJson(Map<String, dynamic> json) {
    return WsEventMessage(
      event: json['event'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  /// Event name (e.g. `session.connect`, `call.offer`, `call.answer`).
  final String event;

  /// Event payload data.
  final Map<String, dynamic>? data;

  Map<String, dynamic> toJson() => {
        'event': event,
        if (data != null) 'data': data,
      };

  @override
  String toString() => 'WsEventMessage(event: $event)';
}
