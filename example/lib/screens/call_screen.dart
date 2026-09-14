import 'dart:async';

import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:flutter/material.dart';

/// In-call screen with call controls: mute, hold, DTMF, transfer, hangup.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.call});

  final Call call;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  CallState _state = CallState.initiated;
  bool _muted = false;
  bool _speakerOn = false;
  bool _onHold = false;
  bool _showDtmf = false;
  String _duration = '00:00';
  Timer? _durationTimer;
  DateTime? _callStartTime;

  late final StreamSubscription<
      ({CallState state, String? reason, Map<String, dynamic>? data})> _stateSub;
  late final StreamSubscription<bool> _muteSub;
  late final StreamSubscription<bool> _speakerSub;

  @override
  void initState() {
    super.initState();
    _state = widget.call.callState;
    _muted = widget.call.isMuted;
    _speakerOn = widget.call.isSpeakerOn;
    _onHold = widget.call.isHold;

    _stateSub = widget.call.onStateChange.listen((event) {
      if (!mounted) return;
      setState(() => _state = event.state);

      if (event.state == CallState.active ||
          event.state == CallState.answered) {
        _startDurationTimer();
      }

      if (event.state == CallState.onHold) {
        setState(() => _onHold = true);
      } else if (event.state == CallState.active) {
        setState(() => _onHold = false);
      }

      if (event.state == CallState.ended ||
          event.state == CallState.error ||
          event.state == CallState.cancel) {
        _durationTimer?.cancel();
        // Auto-pop after 1.5s
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });

    _muteSub = widget.call.onMuteChange.listen((muted) {
      if (!mounted) return;
      setState(() => _muted = muted);
    });

    _speakerSub = widget.call.onSpeakerChange.listen((speaker) {
      if (!mounted) return;
      setState(() => _speakerOn = speaker);
    });
  }

  @override
  void dispose() {
    _stateSub.cancel();
    _muteSub.cancel();
    _speakerSub.cancel();
    _durationTimer?.cancel();
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

  Future<void> _toggleSpeaker() async {
    await widget.call.toggleSpeaker();
  }

  Future<void> _toggleHold() async {
    if (_onHold) {
      await widget.call.unhold();
    } else {
      await widget.call.onhold();
    }
  }

  void _sendDtmf(String digit) {
    widget.call.sendDTMF(digit);
  }

  void _showTransferDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transfer Call'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Transfer to',
            hintText: 'Extension, number, or agent',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final target = controller.text.trim();
              if (target.isNotEmpty) {
                Navigator.of(ctx).pop();
                await widget.call.transfer(target);
              }
            },
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnded = _state == CallState.ended ||
        _state == CallState.error ||
        _state == CallState.cancel;
    final isActive =
        _state == CallState.active || _state == CallState.onHold;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),

            // Caller info
            Text(
              widget.call.fromName.isNotEmpty
                  ? widget.call.fromName
                  : widget.call.to.isNotEmpty
                      ? widget.call.to
                      : 'Unknown',
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.call.to.isNotEmpty ? widget.call.to : widget.call.from,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),

            // State & duration
            Text(
              isActive ? _duration : _stateLabel(_state),
              style: theme.textTheme.titleMedium?.copyWith(
                color: _stateColor(_state),
              ),
            ),

            const Spacer(),

            // DTMF pad (toggled)
            if (_showDtmf && isActive)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: _DtmfGrid(onDigit: _sendDtmf),
              ),

            const SizedBox(height: 24),

            // Call controls
            if (!isEnded)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mute
                    _ControlButton(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      label: _muted ? 'Unmute' : 'Mute',
                      active: _muted,
                      onPressed: isActive ? _toggleMute : null,
                    ),

                    // Speaker
                    _ControlButton(
                      icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                      label: _speakerOn ? 'Speaker' : 'Earpiece',
                      active: _speakerOn,
                      onPressed: isActive ? _toggleSpeaker : null,
                    ),

                    // Hold
                    _ControlButton(
                      icon: _onHold ? Icons.play_arrow : Icons.pause,
                      label: _onHold ? 'Resume' : 'Hold',
                      active: _onHold,
                      onPressed: isActive ? _toggleHold : null,
                    ),

                    // DTMF
                    _ControlButton(
                      icon: Icons.dialpad,
                      label: 'Keypad',
                      active: _showDtmf,
                      onPressed: isActive
                          ? () => setState(() => _showDtmf = !_showDtmf)
                          : null,
                    ),

                    // Transfer
                    _ControlButton(
                      icon: Icons.call_split,
                      label: 'Transfer',
                      onPressed: isActive ? _showTransferDialog : null,
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // Hangup button
            if (!isEnded)
              SizedBox(
                width: 72,
                height: 72,
                child: FloatingActionButton(
                  onPressed: _hangup,
                  backgroundColor: Colors.red,
                  child:
                      const Icon(Icons.call_end, size: 32, color: Colors.white),
                ),
              ),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  String _stateLabel(CallState state) {
    return switch (state) {
      CallState.none => 'Idle',
      CallState.initiated => 'Calling...',
      CallState.trying => 'Trying...',
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

// ─── Control Button Widget ──────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  const _ControlButton({
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
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: active
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            foregroundColor: active
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

// ─── DTMF Grid Widget ──────────────────────────────────────────────

class _DtmfGrid extends StatelessWidget {
  const _DtmfGrid({required this.onDigit});

  final void Function(String digit) onDigit;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['*', '0', '#'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _rows
          .map(
            (row) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row
                  .map(
                    (d) => Padding(
                      padding: const EdgeInsets.all(4),
                      child: SizedBox(
                        width: 56,
                        height: 44,
                        child: OutlinedButton(
                          onPressed: () => onDigit(d),
                          child: Text(d, style: const TextStyle(fontSize: 18)),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    );
  }
}
