import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../utils/auth_error_message.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final user = await ApiService().register(
        displayName: _displayNameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;

      Navigator.of(context).pop<String>(user.email);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      final message = authErrorMessage(error);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final colors = Theme.of(context).colorScheme;

    OutlineInputBorder fieldBorder(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: colors.outline),
      prefixIcon: Icon(icon, size: 20, color: colors.onSurfaceVariant),
      prefixIconConstraints: const BoxConstraints(minWidth: 48),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: fieldBorder(colors.outlineVariant),
      enabledBorder: fieldBorder(colors.outlineVariant),
      focusedBorder: fieldBorder(colors.primary, width: 1.5),
      errorBorder: fieldBorder(colors.error),
      focusedErrorBorder: fieldBorder(colors.error, width: 1.5),
      errorMaxLines: 2,
    );
  }

  Widget _fieldLabel(String label, {Widget? trailing}) {
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );
  }

  Widget _passwordRule(String label, {required bool isSatisfied}) {
    final colors = Theme.of(context).colorScheme;
    final color = isSatisfied ? colors.primary : colors.outline;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isSatisfied ? Icons.check_circle_outline : Icons.circle_outlined,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('创建账户')),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      Theme.of(context).colorScheme.primary.withAlpha(18),
                      Theme.of(context).colorScheme.surface,
                    ),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withAlpha(36),
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 19,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '账户功能仍在实验阶段，本地记录不会自动上传。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                _fieldLabel(
                  '显示名称',
                  trailing: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _displayNameController,
                    builder: (context, value, child) {
                      return Text(
                        '${value.text.length}/50',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _displayNameController,
                  enabled: !_isSubmitting,
                  textInputAction: TextInputAction.next,
                  maxLength: 50,
                  decoration: _inputDecoration(
                    hintText: '输入你的昵称',
                    icon: Icons.person_outline,
                  ).copyWith(counterText: ''),
                  validator: (value) {
                    final displayName = value?.trim() ?? '';

                    if (displayName.isEmpty) {
                      return '请输入显示名称';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),

                _fieldLabel('邮箱'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailController,
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: _inputDecoration(
                    hintText: 'name@example.com',
                    icon: Icons.email_outlined,
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';

                    final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

                    if (email.isEmpty) {
                      return '请输入邮箱';
                    }

                    if (!emailPattern.hasMatch(email)) {
                      return '请输入有效的邮箱';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),

                _fieldLabel('密码'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordController,
                  enabled: !_isSubmitting,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: _inputDecoration(
                    hintText: '输入密码',
                    icon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                      onPressed: _isSubmitting
                          ? null
                          : () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final password = value ?? '';

                    if (password.length < 8) {
                      return '密码至少需要 8 个字符';
                    }

                    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
                    final hasNumber = RegExp(r'\d').hasMatch(password);

                    if (!hasLetter || !hasNumber) {
                      return '密码至少需要包含一个英文字母和一个数字';
                    }

                    if (password.length > 72) {
                      return '密码不能超过 72 个字符';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _passwordController,
                  builder: (context, value, child) {
                    final password = value.text;

                    return Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _passwordRule(
                          '8+ 字符',
                          isSatisfied: password.length >= 8,
                        ),
                        _passwordRule(
                          '包含字母',
                          isSatisfied: RegExp(r'[A-Za-z]').hasMatch(password),
                        ),
                        _passwordRule(
                          '包含数字',
                          isSatisfied: RegExp(r'\d').hasMatch(password),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                _fieldLabel('确认密码'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _confirmPasswordController,
                  enabled: !_isSubmitting,
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  decoration: _inputDecoration(
                    hintText: '再次输入密码',
                    icon: Icons.lock_reset_outlined,
                    suffixIcon: IconButton(
                      tooltip: _obscureConfirmPassword ? '显示密码' : '隐藏密码',
                      onPressed: _isSubmitting
                          ? null
                          : () {
                              setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              });
                            },
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
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
                    if (!_isSubmitting) {
                      _register();
                    }
                  },
                ),
                const SizedBox(height: 24),

                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _register,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('创建账户'),
                  ),
                ),
                const SizedBox(height: 12),

                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('已经有账户？'),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () {
                              Navigator.of(context).pop();
                            },
                      child: const Text('直接登录'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
