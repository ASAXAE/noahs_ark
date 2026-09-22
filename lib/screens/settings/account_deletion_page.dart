import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../utils/auth_error_message.dart';

class AccountDeletionPage extends StatefulWidget {
  const AccountDeletionPage({super.key, this.apiService});

  final ApiService? apiService;

  @override
  State<AccountDeletionPage> createState() => _AccountDeletionPageState();
}

class _AccountDeletionPageState extends State<AccountDeletionPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();

  late final ApiService _apiService;

  bool _isDeleting = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
  }

  Future<void> _deleteAccount() async {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _isDeleting = true;
    });

    try {
      await _apiService.deleteAccount(password: _passwordController.text);

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isDeleting = false;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('删除云端账号')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              color: colors.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: colors.onErrorContainer,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '此操作不可恢复',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: colors.onErrorContainer),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '服务器将永久删除你的云端账号、'
                      '服务器测试记录、验证令牌、'
                      '密码重置令牌和全部登录会话。',
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: ListTile(
                leading: Icon(Icons.phone_android_outlined),
                title: Text('当前设备上的内容会保留'),
                subtitle: Text(
                  '本机 SQLite 正式记录、闪念草稿、'
                  '原始录音和已导出的 JSON 备份'
                  '不会被删除。',
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('确认身份', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              '请输入当前账号密码，确认是你本人'
              '在执行永久删除。',
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const Key('account-deletion-password'),
                    controller: _passwordController,
                    enabled: !_isDeleting,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: '当前密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                        onPressed: _isDeleting
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

                      if (password.isEmpty) {
                        return '请输入当前密码';
                      }

                      if (password.length > 72) {
                        return '密码不能超过 72 个字符';
                      }

                      return null;
                    },
                    onFieldSubmitted: (_) {
                      if (!_isDeleting) {
                        _deleteAccount();
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('account-deletion-button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.error,
                      foregroundColor: colors.onError,
                    ),
                    onPressed: _isDeleting ? null : _deleteAccount,
                    icon: _isDeleting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_forever),
                    label: Text(_isDeleting ? '正在删除…' : '永久删除云端账号'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
