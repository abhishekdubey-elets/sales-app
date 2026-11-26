import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_controller.dart';

/// Which sign-in the user picked. The server refuses an account of the other kind (`wrong_portal`).
enum SignInPortal {
  admin(
    'admin',
    'Admin',
    'Continue as Admin',
    'Team, AI agents, campaigns, reports and settings',
    Icons.admin_panel_settings_outlined,
  ),
  employee(
    'employee',
    'Employee',
    'Continue as Employee',
    'Sales executives and managers: leads, calls, follow-ups',
    Icons.badge_outlined,
  );

  const SignInPortal(this.value, this.label, this.cta, this.description, this.icon);

  final String value;
  final String label;
  final String cta;
  final String description;
  final IconData icon;
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  SignInPortal? _portal;
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _choose(SignInPortal? portal) => setState(() {
    _portal = portal;
    _error = null;
  });

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).login(_email.text, _password.text, portal: _portal?.value);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.isUnauthorized ? 'Incorrect email or password.' : errorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _changeServer() async {
    final saved = await showDialog<String>(context: context, builder: (_) => const ServerDialog());
    if (saved == null || !mounted) return;
    setState(() => _error = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Server set to $saved')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = ref.watch(authControllerProvider).message;
    final portal = _portal;
    return PopScope(
      // System back on the form returns to the Admin / Employee choice.
      canPop: portal == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _choose(null);
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.headset_mic, color: Colors.white, size: 28),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      portal == null ? 'Welcome to Elets SalesCall AI' : '${portal.label} sign in',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      portal == null
                          ? 'How are you signing in?'
                          : 'Use the email and password your administrator gave you.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    if (message != null && _error == null) _Banner(text: message, color: AppColors.warning),
                    if (_error != null) _Banner(text: _error!, color: theme.colorScheme.error),
                    if (portal == null) ...[
                      for (final option in SignInPortal.values) ...[
                        _PortalCard(portal: option, onTap: () => _choose(option)),
                        const SizedBox(height: 12),
                      ],
                    ] else
                      _form(theme, portal),
                    const SizedBox(height: 20),
                    Center(
                      child: TextButton.icon(
                        onPressed: _submitting ? null : _changeServer,
                        icon: const Icon(Icons.dns_outlined, size: 18),
                        label: Text('Server: ${Env.apiBaseUrl}', overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    Text(
                      'Each person signs in with their own account, created by your administrator.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(ThemeData theme, SignInPortal portal) {
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                key: const ValueKey('portal-change'),
                avatar: Icon(portal.icon, size: 18),
                label: Text('Signing in as ${portal.label} · Change'),
                onPressed: _submitting ? null : () => _choose(null),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email, AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Work email', prefixIcon: Icon(Icons.mail_outline)),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Enter your email';
                if (!value.contains('@') || !value.contains('.')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Sign in as ${portal.label}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalCard extends StatelessWidget {
  const _PortalCard({required this.portal, required this.onTap});

  final SignInPortal portal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey('portal-${portal.value}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Icon(portal.icon),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(portal.cta, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      portal.description,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lets the user point the installed app at a backend (e.g. `http://192.168.1.20:8000`
/// on the office network, or the production https URL). Checks `/health` before saving.
class ServerDialog extends StatefulWidget {
  const ServerDialog({super.key});

  @override
  State<ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<ServerDialog> {
  final _controller = TextEditingController(text: Env.apiBaseUrl);
  bool _checking = false;
  String? _error;
  bool _offerSaveAnyway = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save({bool skipCheck = false}) async {
    final url = Env.normalizeServerUrl(_controller.text);
    if (url == null) {
      setState(() {
        _error = 'Enter an address like http://192.168.1.20:8000 or https://api.example.com';
        _offerSaveAnyway = false;
      });
      return;
    }
    if (!skipCheck) {
      setState(() {
        _checking = true;
        _error = null;
      });
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 6)));
      try {
        final res = await dio.get<dynamic>('$url/health');
        final ok = res.data is Map && (res.data as Map)['database'] == true;
        if (!ok) throw Exception('unexpected response');
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _checking = false;
          _error = 'Could not reach an Elets SalesCall server at $url. Check the address, that the phone is on the '
              'same network, and that the server is running.';
          _offerSaveAnyway = true;
        });
        return;
      } finally {
        dio.close(force: true);
      }
    }
    await Env.setServer(url);
    if (mounted) Navigator.of(context).pop(url);
  }

  Future<void> _reset() async {
    await Env.setServer(null);
    if (mounted) Navigator.of(context).pop(Env.apiBaseUrl);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server address'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enabled: !_checking,
            decoration: const InputDecoration(hintText: 'http://192.168.1.20:8000', prefixIcon: Icon(Icons.dns_outlined)),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask your administrator for this address.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        if (Env.isCustomServer)
          TextButton(onPressed: _checking ? null : _reset, child: const Text('Use default')),
        if (_offerSaveAnyway)
          TextButton(onPressed: _checking ? null : () => _save(skipCheck: true), child: const Text('Save anyway')),
        TextButton(onPressed: _checking ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _checking ? null : _save,
          child: _checking
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Connect'),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}
