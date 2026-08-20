import 'package:flutter/material.dart';

import '../../models/auth_session.dart';
import '../../services/auth_session_storage.dart';

import '../auth/login_page.dart';
import 'local_first_info_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.authSessionNotifier,
    required this.onExportBackup,
    required this.onRestoreBackup,
  });

  final ValueNotifier<AuthSession?> authSessionNotifier;
  final Future<void> Function() onExportBackup;
  final Future<void> Function() onRestoreBackup;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('账户与服务', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          ValueListenableBuilder<AuthSession?>(
            valueListenable: authSessionNotifier,
            builder: (context, session, child) {
              if (session == null) {
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('登录'),
                    subtitle: const Text('可选功能，不登录也能继续使用本地记录'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final loggedInSession = await Navigator.of(context)
                          .push<AuthSession>(
                            MaterialPageRoute<AuthSession>(
                              builder: (_) => const LoginPage(),
                            ),
                          );

                      if (!context.mounted || loggedInSession == null) {
                        return;
                      }

                      authSessionNotifier.value = loggedInSession;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '登录成功，欢迎回来：${loggedInSession.user.displayName}',
                          ),
                        ),
                      );
                    },
                  ),
                );
              }

              final user = session.user;

              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(user.displayName),
                      subtitle: Text(user.email),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('退出登录'),
                      subtitle: const Text('退出不会删除本地记录'),
                      onTap: () async {
                        await AuthSessionStorage.instance.deleteAccessToken();

                        authSessionNotifier.value = null;

                        if (!context.mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已退出登录，本地记录仍然保留')),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 24),
          Text('数据管理', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('导出备份'),
                  subtitle: const Text('将全部本地记录导出为 JSON 文件'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await onExportBackup();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('恢复备份'),
                  subtitle: const Text('选择并验证诺亚方舟 JSON 备份'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await onRestoreBackup();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('隐私', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('本地优先'),
              subtitle: const Text('核心记录保存在当前设备的 SQLite 中'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LocalFirstInfoPage(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text('关于', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.sailing_outlined),
              title: Text('诺亚方舟'),
              subtitle: Text('把重要的想法留下来'),
            ),
          ),
        ],
      ),
    );
  }
}
