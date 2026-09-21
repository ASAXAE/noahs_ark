import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../utils/auth_error_message.dart';

class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({super.key, this.apiService, this.initialEmail});

  final ApiService? apiService;
  final String? initialEmail;

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final _requestFormKey = GlobalKey<FormState>();
  final _confirmationFormKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmationController = TextEditingController();

  late final ApiService _apiService;

  bool _isRequesting = false;
  bool _isResetting = false;
  bool _requestAccepted = false;
  bool _obscurePassword = true;
  bool _obscurePasswordConfirmation = true;

  bool get _isBusy => _isRequesting || _isResetting;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _emailController.text = widget.initialEmail?.trim() ?? '';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _tokenController.dispose();
    _passwordController.dispose();
    _passwordConfirmationController.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    if (_requestFormKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _isRequesting = true;
    });

    try {
      await _apiService.requestPasswordReset(email: _emailController.text);

      if (!mounted) return;

      setState(() {
        _isRequesting = false;
        _requestAccepted = true;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('如果该邮箱已注册，密码重置指引将会发送')));
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isRequesting = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
    }
  }

  Future<void> _confirmReset() async {
    if (_confirmationFormKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _isResetting = true;
    });

    try {
      await _apiService.confirmPasswordReset(
        token: _tokenController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isResetting = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
    }
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      border: const OutlineInputBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('重置密码')),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.privacy_tip_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('为保护账户隐私，无论邮箱是否注册，申请成功时都会显示相同提示。'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Form(
                key: _requestFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('password-reset-email'),
                      controller: _emailController,
                      enabled: !_isBusy,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.email],
                      decoration: _decoration(
                        label: '账户邮箱',
                        icon: Icons.email_outlined,
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';

                        if (email.isEmpty) {
                          return '请输入邮箱';
                        }

                        if (!email.contains('@')) {
                          return '请输入有效的邮箱';
                        }

                        return null;
                      },
                      onFieldSubmitted: (_) {
                        if (!_isBusy) {
                          _requestReset();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('password-reset-request-button'),
                      onPressed: _isBusy ? null : _requestReset,
                      icon: _isRequesting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.outgoing_mail),
                      label: const Text('发送重置指引'),
                    ),
                  ],
                ),
              ),
              if (_requestAccepted) ...[
                const SizedBox(height: 28),
                Text('设置新密码', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '如果该邮箱已注册，请粘贴收到的 64 位重置令牌，并设置新密码。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Form(
                  key: _confirmationFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const Key('password-reset-token'),
                        controller: _tokenController,
                        enabled: !_isBusy,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: _decoration(
                          label: '重置令牌',
                          icon: Icons.key_outlined,
                        ),
                        validator: (value) {
                          final token = value?.trim() ?? '';

                          if (token.isEmpty) {
                            return '请输入重置令牌';
                          }

                          if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(token)) {
                            return '请输入 64 位十六进制重置令牌';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('password-reset-password'),
                        controller: _passwordController,
                        enabled: !_isBusy,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: _decoration(
                          label: '新密码',
                          icon: Icons.lock_outline,
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                            onPressed: _isBusy
                                ? null
                                : () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          final password = value ?? '';

                          if (password.length < 8) {
                            return '密码至少需要 8 个字符';
                          }

                          if (password.length > 72) {
                            return '密码不能超过 72 个字符';
                          }

                          if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
                              !RegExp(r'\d').hasMatch(password)) {
                            return '密码必须同时包含英文字母和数字';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('password-reset-confirm-password'),
                        controller: _passwordConfirmationController,
                        enabled: !_isBusy,
                        obscureText: _obscurePasswordConfirmation,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: _decoration(
                          label: '确认新密码',
                          icon: Icons.lock_reset_outlined,
                          suffixIcon: IconButton(
                            tooltip: _obscurePasswordConfirmation
                                ? '显示确认密码'
                                : '隐藏确认密码',
                            onPressed: _isBusy
                                ? null
                                : () {
                                    setState(() {
                                      _obscurePasswordConfirmation =
                                          !_obscurePasswordConfirmation;
                                    });
                                  },
                            icon: Icon(
                              _obscurePasswordConfirmation
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value != _passwordController.text) {
                            return '两次输入的密码不一致';
                          }

                          return null;
                        },
                        onFieldSubmitted: (_) {
                          if (!_isBusy) {
                            _confirmReset();
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const Key('password-reset-confirm-button'),
                        onPressed: _isBusy ? null : _confirmReset,
                        child: _isResetting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('确认重置密码'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
