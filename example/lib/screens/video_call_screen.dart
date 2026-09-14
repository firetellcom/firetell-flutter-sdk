import 'dart:async';

import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:flutter/material.dart';

/// Dedicated full-screen Video Call UI with local Picture-in-Picture preview
/// and interactive video/camera controls.
class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key, required this.call});

  final Call call;

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  CallState _state = CallState.initiated;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  bool _hasRemoteVideo = false;
  bool _hasLocalVideo = false;

  static const double _pipWidth = 105;
  static const double _pipHeight = 145;
  Offset? _pipPosition;
  bool _isDraggingPip = false;

  String _duration = '00:00';
  Timer? _durationTimer;
  DateTime? _callStartTime;

  late final StreamSubscription<
      ({CallState state, String? reason, Map<String, dynamic>? data})> _stateSub;
  late final StreamSubscription<bool> _muteSub;
  late final StreamSubscription<bool> _cameraSub;
  late final StreamSubscription<bool> _speakerSub;
  late final StreamSubscription<MediaStream?> _localStreamSub;
  late final StreamSubscription<MediaStream?> _remoteStreamSub;

  @override
  void initState() {
    super.initState();
    _state = widget.call.callState;
    _muted = widget.call.isMuted;
    _cameraOff = widget.call.isCameraOff;
    _speakerOn = widget.call.isSpeakerOn;

    _initRenderers();
    _setupSubscriptions();

    // Default speakerphone to on for video calls
    if (!_speakerOn) {
      widget.call.setSpeakerphoneOn(true);
    }
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    if (widget.call.localStream != null) {
      _localRenderer.srcObject = widget.call.localStream;
      if (mounted) {
        setState(() {
          _hasLocalVideo =
              widget.call.localStream!.getVideoTracks().isNotEmpty;
        });
      }
    }

    if (widget.call.remoteStream != null) {
      _remoteRenderer.srcObject = widget.call.remoteStream;
      if (mounted) {
        setState(() {
          _hasRemoteVideo =
              widget.call.remoteStream!.getVideoTracks().isNotEmpty;
        });
      }
    }
  }

  void _setupSubscriptions() {
    _stateSub = widget.call.onStateChange.listen((event) {
      if (!mounted) return;
      setState(() => _state = event.state);

      if (event.state == CallState.active ||
          event.state == CallState.answered) {
        _startDurationTimer();
      }

      if (event.state == CallState.ended ||
          event.state == CallState.error ||
          event.state == CallState.cancel) {
        _durationTimer?.cancel();
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });

    _muteSub = widget.call.onMuteChange.listen((muted) {
      if (!mounted) return;
      setState(() => _muted = muted);
    });

    _cameraSub = widget.call.onCameraChange.listen((off) {
      if (!mounted) return;
      setState(() => _cameraOff = off);
    });

    _speakerSub = widget.call.onSpeakerChange.listen((speaker) {
      if (!mounted) return;
      setState(() => _speakerOn = speaker);
    });

    _localStreamSub = widget.call.onLocalStream.listen((stream) {
      if (!mounted) return;
      _localRenderer.srcObject = stream;
      setState(() {
        _hasLocalVideo = stream != null && stream.getVideoTracks().isNotEmpty;
      });
    });

    _remoteStreamSub = widget.call.onRemoteStream.listen((stream) {
      if (!mounted) return;
      _remoteRenderer.srcObject = stream;
      setState(() {
        _hasRemoteVideo = stream != null && stream.getVideoTracks().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _stateSub.cancel();
    _muteSub.cancel();
    _cameraSub.cancel();
    _speakerSub.cancel();
    _localStreamSub.cancel();
    _remoteStreamSub.cancel();
    _durationTimer?.cancel();

    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _startDurationTimer() {
    _callStartTime ??= DateTime.now();
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _callStartTime == null) return;
      final elapsed = DateTime.now().difference(_callStartTime!);
      final mins = elapsed.inMinutes.toString().padLeft(2, '0');
      final secs = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
      setState(() => _duration = '$mins:$secs');
    });
  }

  Future<void> _hangup() async {
    await widget.call.hangup();
  }

  Future<void> _toggleMute() async {
    await widget.call.toggleMute();
  }

  Future<void> _toggleCamera() async {
    await widget.call.toggleCamera();
  }

  Future<void> _switchCamera() async {
    await widget.call.switchCamera();
  }

  Future<void> _toggleSpeaker() async {
    await widget.call.toggleSpeaker();
  }

  void _onPipPanUpdate(
    DragUpdateDetails details,
    double minX,
    double maxX,
    double minY,
    double maxY,
  ) {
    final current = _pipPosition ?? Offset(maxX, minY);
    final newX = (current.dx + details.delta.dx).clamp(minX, maxX);
    final newY = (current.dy + details.delta.dy).clamp(minY, maxY);
    setState(() {
      _pipPosition = Offset(newX, newY);
    });
  }

  void _onPipPanEnd(double minX, double maxX, double screenWidth) {
    if (_pipPosition == null) return;
    final snapX = (_pipPosition!.dx + _pipWidth / 2 < screenWidth / 2)
        ? minX
        : maxX;
    setState(() {
      _isDraggingPip = false;
      _pipPosition = Offset(snapX, _pipPosition!.dy);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);

    const minX = 16.0;
    final maxX = screenSize.width - _pipWidth - 16.0;
    final minY = padding.top + 60.0;
    final maxY = screenSize.height - padding.bottom - _pipHeight - 110.0;

    // Initialize PiP position to top-right on first layout
    _pipPosition ??= Offset(maxX, minY);

    final isEnded = _state == CallState.ended ||
        _state == CallState.error ||
        _state == CallState.cancel;
    final isActive =
        _state == CallState.active || _state == CallState.onHold;

    final displayName = widget.call.fromName.isNotEmpty
        ? widget.call.fromName
        : widget.call.to.isNotEmpty
            ? widget.call.to
            : 'Video Call';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ─── Remote Video View (Fullscreen) ──────────────────────────
          if (_hasRemoteVideo && isActive)
            Positioned.fill(
              child: RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            )
          else
            Positioned.fill(
              child: Container(
                color: const Color(0xFF121418),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.2),
                        child: Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : 'V',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isActive ? _duration : _stateLabel(_state),
                        style: TextStyle(
                          fontSize: 16,
                          color: _stateColor(_state),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ─── Top Header Overlay ──────────────────────────────────────
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.videocam,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isActive ? _duration : _stateLabel(_state),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (isActive && !_cameraOff)
                      IconButton.filledTonal(
                        onPressed: _switchCamera,
                        icon: const Icon(Icons.flip_camera_ios, size: 20),
                        tooltip: 'Switch Camera',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.5),
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ─── Local Video Preview (Draggable Picture-in-Picture) ─────
          if (_hasLocalVideo && !isEnded)
            AnimatedPositioned(
              duration: _isDraggingPip
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: _pipPosition?.dx ?? maxX,
              top: _pipPosition?.dy ?? minY,
              child: GestureDetector(
                onPanStart: (_) => setState(() => _isDraggingPip = true),
                onPanUpdate: (details) =>
                    _onPipPanUpdate(details, minX, maxX, minY, maxY),
                onPanEnd: (_) =>
                    _onPipPanEnd(minX, maxX, screenSize.width),
                onPanCancel: () =>
                    _onPipPanEnd(minX, maxX, screenSize.width),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: _pipWidth,
                    height: _pipHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2024),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isDraggingPip
                            ? theme.colorScheme.primary
                            : Colors.white.withValues(alpha: 0.2),
                        width: _isDraggingPip ? 2.0 : 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                              alpha: _isDraggingPip ? 0.6 : 0.4),
                          blurRadius: _isDraggingPip ? 16 : 10,
                          offset: Offset(0, _isDraggingPip ? 8 : 4),
                        ),
                      ],
                    ),
                    child: _cameraOff
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam_off,
                                    color: Colors.white54, size: 28),
                                SizedBox(height: 4),
                                Text(
                                  'Camera off',
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 10),
                                ),
                              ],
                            ),
                          )
                        : RTCVideoView(
                            _localRenderer,
                            mirror: true,
                            objectFit:
                                RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          ),
                  ),
                ),
              ),
            ),

          // ─── Bottom Floating Controls ────────────────────────────────
          if (!isEnded)
            Positioned(
              bottom: 36,
              left: 20,
              right: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2026).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mute / Unmute Mic
                    _VideoButton(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      label: _muted ? 'Unmute' : 'Mute',
                      active: _muted,
                      onPressed: isActive ? _toggleMute : null,
                    ),

                    // Camera On / Off
                    _VideoButton(
                      icon: _cameraOff
                          ? Icons.videocam_off
                          : Icons.videocam,
                      label: _cameraOff ? 'Start Cam' : 'Stop Cam',
                      active: _cameraOff,
                      onPressed: isActive ? _toggleCamera : null,
                    ),

                    // Switch Speakerphone
                    _VideoButton(
                      icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                      label: _speakerOn ? 'Speaker' : 'Earpiece',
                      active: _speakerOn,
                      onPressed: isActive ? _toggleSpeaker : null,
                    ),

                    // Hangup Call
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: FloatingActionButton(
                        onPressed: _hangup,
                        backgroundColor: Colors.red,
                        elevation: 2,
                        shape: const CircleBorder(),
                        child: const Icon(Icons.call_end,
                            size: 26, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _stateLabel(CallState state) {
    return switch (state) {
      CallState.none => 'Idle',
      CallState.initiated => 'Connecting...',
      CallState.trying => 'Connecting...',
      CallState.ringing => 'Ringing...',
      CallState.answered => 'Connecting...',
      CallState.active => 'Active',
      CallState.onHold => 'On Hold',
      CallState.ended => 'Call Ended',
      CallState.error => 'Error',
      CallState.cancel => 'Canceled',
    };
  }

  Color _stateColor(CallState state) {
    return switch (state) {
      CallState.active => Colors.green,
      CallState.onHold => Colors.orange,
      CallState.ended || CallState.error || CallState.cancel => Colors.red,
      _ => Colors.white70,
    };
  }
}

// ─── Video Control Button Widget ─────────────────────────────────────

class _VideoButton extends StatelessWidget {
  const _VideoButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onPressed,
          icon: Icon(icon, size: 22),
          style: IconButton.styleFrom(
            backgroundColor: active
                ? Colors.redAccent.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.12),
            foregroundColor: active ? Colors.redAccent : Colors.white,
            minimumSize: const Size(48, 48),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
