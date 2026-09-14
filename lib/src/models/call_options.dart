/// Options for creating a new [Call] instance.
class CallOptions {
  const CallOptions({
    this.to = '',
    this.from = '',
    this.fromName = '',
    this.fromAvatar,
    this.isVideo = false,
    this.isTransfer = false,
    this.transferReason,
  });

  /// Destination number or extension.
  final String to;

  /// Caller number or extension.
  final String from;

  /// Caller display name.
  final String fromName;

  /// Caller avatar URL.
  final String? fromAvatar;

  /// Whether this is a video call.
  final bool isVideo;

  /// Whether this call is a transfer.
  final bool isTransfer;

  /// Reason for the transfer, if applicable.
  final String? transferReason;
}
