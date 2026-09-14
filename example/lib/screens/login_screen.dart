import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:flutter/material.dart';

import 'home_screen.dart';

/// Login screen — enter workspace domain and JWT to connect.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _domainController = TextEditingController();
  final _jwtController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _domainController.dispose();
    _jwtController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final domain = _domainController.text.trim();
    final jwt = _jwtController.text.trim();

    if (domain.isEmpty || jwt.isEmpty) {
      setState(() => _error = 'Domain and JWT are required');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = FiretellClient(jwt: jwt, domain: domain);
      final session = await client.ready;

      debugPrint('Connected as ${session.username}');

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(client: client, session: session),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firetell SDK Example')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.phone_in_talk, size: 64),
            const SizedBox(height: 32),

            // Domain field
            TextField(
              controller: _domainController,
              decoration: const InputDecoration(
                labelText: 'Workspace Domain',
                hintText: 'ws_xxx.firetell.app',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dns),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // JWT field
            TextField(
              controller: _jwtController,
              decoration: const InputDecoration(
                labelText: 'Agent JWT',
                hintText: 'eyJhbGciOiJIUzI1NiIs...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
              maxLines: 3,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: 24),

            // Error message
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),

            // Connect button
            FilledButton.icon(
              onPressed: _loading ? null : _connect,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(_loading ? 'Connecting...' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
