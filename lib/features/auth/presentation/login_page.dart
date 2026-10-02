import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/widgets/common.dart';
import '../application/session_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _submitting = false;
  bool _obscure = true;
  String? _error;
  String? _emailError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _error = null;
      _emailError = null;
    });
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await ref.read(sessionControllerProvider.notifier).login(
            email: _email.text.trim(),
            password: _password.text,
          );
      // Navigation follows the session state (router redirect).
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        // Wrong credentials / inactive account come back as an `email` error.
        // failure.message is already translated (framework messages replaced).
        _emailError = failure.kind == FailureKind.validation && failure.fieldError('email') != null
            ? failure.message
            : null;
        _error = _emailError == null ? failure.message : null;
        _password.clear();
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(sessionControllerProvider.select((s) => s.message));

    return Scaffold(
      body: SafeArea(
        child: CenteredPane(
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: Alignment.topRight, child: EnvironmentBadge()),
                  const BrandMark(),
                  const SizedBox(height: 32),
                  if (notice != null && _error == null && _emailError == null) ...[
                    MessageBanner(notice, tone: BannerTone.info),
                    const SizedBox(height: 16),
                  ],
                  if (_error != null) ...[
                    MessageBanner(_error!),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    key: const Key('login-email'),
                    controller: _email,
                    enabled: !_submitting,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email, AutofillHints.username],
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.mail_outline),
                      errorText: _emailError,
                      errorMaxLines: 2,
                    ),
                    validator: (value) {
                      final v = value?.trim() ?? '';
                      if (v.isEmpty) return 'Email wajib diisi.';
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) return 'Format email tidak valid.';
                      return null;
                    },
                    onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('login-password'),
                    controller: _password,
                    focusNode: _passwordFocus,
                    enabled: !_submitting,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Tampilkan password' : 'Sembunyikan password',
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (value) => (value ?? '').isEmpty ? 'Password wajib diisi.' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('login-submit'),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                              SizedBox(width: 12),
                              Text('Memproses...'),
                            ],
                          )
                        : const Text('MASUK'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
