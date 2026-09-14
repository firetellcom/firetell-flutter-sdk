import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:flutter/material.dart';

import 'call_screen.dart';

/// Dial pad screen for making outbound calls.
class DialpadScreen extends StatefulWidget {
  const DialpadScreen({super.key, required this.client});

  final FiretellClient client;

  @override
  State<DialpadScreen> createState() => _DialpadScreenState();
}

class _DialpadScreenState extends State<DialpadScreen> {
  final _numberController = TextEditingController();
  bool _calling = false;

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  void _appendDigit(String digit) {
    _numberController.text += digit;
  }

  void _backspace() {
    final text = _numberController.text;
    if (text.isNotEmpty) {
      _numberController.text = text.substring(0, text.length - 1);
    }
  }

  Future<void> _makeCall() async {
    final to = _numberController.text.trim();
    if (to.isEmpty) return;

    setState(() => _calling = true);

    try {
      final call = await widget.client.makeOutboundCall(to: to);

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CallScreen(call: call),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _calling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Call failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const digits = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['*', '0', '#'],
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Dial Pad')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Number display
            TextField(
              controller: _numberController,
              decoration: InputDecoration(
                hintText: 'Enter number or extension',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: _backspace,
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ),
              style: const TextStyle(
                fontSize: 24,
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
              readOnly: true,
            ),
            const SizedBox(height: 24),

            // Digit grid
            ...digits.map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: row
                      .map(
                        (digit) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: SizedBox(
                            width: 72,
                            height: 56,
                            child: OutlinedButton(
                              onPressed: () => _appendDigit(digit),
                              child: Text(
                                digit,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Call button
            SizedBox(
              width: 72,
              height: 72,
              child: FloatingActionButton(
                onPressed: _calling ? null : _makeCall,
                backgroundColor: Colors.green,
                child: _calling
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.call, size: 32, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
