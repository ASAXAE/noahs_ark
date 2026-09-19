import 'package:flutter/material.dart';

import '../../models/auth_session.dart';
import '../../services/api_service.dart';
import '../../utils/auth_error_message.dart';

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({
    super.key,
    required this.session,
    required this.authSessionNotifier,
    this.apiService,
  });

  final AuthSession session;
  final ValueNotifier<AuthSession?> authSessionNotifier;
  final ApiService? apiService;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();

  late final ApiService _apiService;
  late AuthSession _session;

  bool _isResending = false;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _session = widget.session;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resendVerificationEmail() async {
    setState(() {
      _isResending = true;
    });

    try {
      await _apiService.resendVerificationEmail();

      if (!mounted) return;

      _showMessage('验证请求已提交。如果后端使用本地假发送器，不会收到真实邮件。');
    } catch (error) {
      if (!mounted) return;
      _showMessage(authErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  Future<void> _confirmVerification() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isConfirming = true;
    });

    try {
      await _apiService.confirmEmailVerification(token: _tokenController.text);

      try {
        final refreshedUser = await _apiService.fetchCurrentUser(
          accessToken: _session.accessToken,
        );

        final refreshedSession = AuthSession(
          accessToken: _session.accessToken,
          user: refreshedUser,
        );

        if (!mounted) return;

        widget.authSessionNotifier.value = refreshedSession;

        setState(() {
          _session = refreshedSession;
          _tokenController.clear();
        });

        _showMessage('邮箱验证成功');
      } catch (error) {
        if (!mounted) return;

        _showMessage('邮箱已经验证，但账户状态刷新失败。返回设置页面后重新进入即可刷新。');
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(authErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _isConfirming = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _session.user;
    final isVerified = user.isEmailVerified;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('邮箱验证')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.phone_android_outlined),
                SizedBox(width: 12),
                Expanded(child: Text('邮箱验证只影响账户状态，不会限制本地记录、闪念、录音或备份。')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    isVerified
                        ? Icons.verified_outlined
                        : Icons.mark_email_unread_outlined,
                    color: isVerified ? colors.primary : colors.tertiary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isVerified ? '邮箱已验证' : '邮箱尚未验证',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.outline),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isVerified) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '重新发送',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text('请求后端重新生成验证令牌。频率限制为每分钟一次、每天五次。'),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _isResending || _isConfirming
                          ? null
                          : _resendVerificationEmail,
                      icon: _isResending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(_isResending ? '正在发送…' : '重新发送验证邮件'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '确认验证',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text('粘贴验证邮件中的令牌。本地假发送器不会真正发送邮件，稍后可使用本地测试令牌完成联调。'),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _tokenController,
                        enabled: !_isConfirming && !_isResending,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: '验证令牌',
                          hintText: '64 位十六进制令牌',
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                        validator: (value) {
                          final token = value?.trim() ?? '';

                          if (token.isEmpty) {
                            return '请输入验证令牌';
                          }

                          if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
                            return '验证令牌应为 64 位小写十六进制字符';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _isConfirming || _isResending
                            ? null
                            : _confirmVerification,
                        icon: _isConfirming
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.verified_outlined),
                        label: Text(_isConfirming ? '正在确认…' : '确认邮箱验证'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
