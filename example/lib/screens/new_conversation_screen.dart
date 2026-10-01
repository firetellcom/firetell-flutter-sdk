import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:flutter/material.dart';

import 'chat_screen.dart';

/// Screen for initiating a new SMS conversation with a client phone number.
///
/// Features:
/// - Select workspace DID (Caller ID) from accessible phone numbers
/// - Enter customer phone number (E.164 format)
/// - Compose initial greeting/inquiry SMS
/// - Directly opens the chat thread upon successful dispatch
class NewConversationScreen extends StatefulWidget {
  const NewConversationScreen({super.key, required this.client});

  final FiretellClient client;

  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clientNumberController = TextEditingController();
  final _bodyController = TextEditingController();

  List<PhoneNumber> _phoneNumbers = [];
  String? _selectedCallerId;
  bool _loadingNumbers = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadPhoneNumbers();
  }

  @override
  void dispose() {
    _clientNumberController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadPhoneNumbers() async {
    try {
      final numbers = await widget.client.getPhoneNumbers();
      if (!mounted) return;
      // Filter DIDs with outbound SMS capability
      final smsCapableNumbers = numbers.where((n) => n.canSendSms).toList();
      setState(() {
        _phoneNumbers = smsCapableNumbers;
        if (smsCapableNumbers.isNotEmpty) {
          _selectedCallerId = smsCapableNumbers.first.number;
        }
        _loadingNumbers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingNumbers = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load phone numbers: $e')),
      );
    }
  }

  Future<void> _startConversation() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCallerId == null || _selectedCallerId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a sender DID number')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final payload = StartConversationPayload(
        from: _selectedCallerId!,
        clientNumber: _clientNumberController.text.trim(),
        body: _bodyController.text.trim(),
      );

      final result = await widget.client.startConversation(payload);

      if (!mounted) return;
      // Navigate straight to the chat thread
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            client: widget.client,
            conversation: result.conversation,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start conversation: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New SMS Conversation'),
      ),
      body: _loadingNumbers
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Sender DID selector
                    Text(
                      'Send From (Workspace DID)',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (_phoneNumbers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber),
                        ),
                        child: const Text(
                          'No SMS-enabled phone numbers assigned to your account. Outbound SMS requires an active DID number with SMS capability.',
                          style: TextStyle(color: Colors.amber),
                        ),
                      )
                    else DropdownButtonFormField<String>(
                        initialValue: _selectedCallerId,
                        decoration: InputDecoration(
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.phone_outlined),
                        ),
                        items: _phoneNumbers.map((phone) {
                          return DropdownMenuItem<String>(
                            value: phone.number,
                            child: Text(phone.displayLabel),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() => _selectedCallerId = val);
                        },
                        validator: (val) =>
                            val == null || val.isEmpty ? 'Required' : null,
                      ),
                    const SizedBox(height: 20),

                    // Client Phone Number input
                    Text(
                      'Recipient Client Number',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _clientNumberController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: '+1234567890 (E.164 format)',
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter recipient phone number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Initial Message body
                    Text(
                      'Initial Message',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _bodyController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(
                        hintText: 'Type your greeting or message here...',
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.message_outlined),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter an initial message';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),

                    // Start Conversation button
                    FilledButton.icon(
                      onPressed: _isSending ? null : _startConversation,
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send),
                      label: Text(_isSending ? 'Sending SMS...' : 'Start Conversation'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
