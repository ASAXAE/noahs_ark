import 'package:flutter/material.dart';

class LocalFirstInfoPage extends StatelessWidget {
  const LocalFirstInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据与隐私')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(
            leading: Icon(Icons.phone_android_outlined),
            title: Text('记录保存在本机'),
            subtitle: Text(
              'V1 的记录保存在当前设备的 SQLite 数据库中，'
              '不会自动上传到服务器。',
            ),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.backup_outlined),
            title: Text('备份由你控制'),
            subtitle: Text(
              '只有主动点击导出备份时，应用才会生成 JSON 文件。'
              '备份可能包含私人内容，请妥善保存。',
            ),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('服务器功能仍在实验中'),
            subtitle: Text(
              '目前的 Express 和 PostgreSQL 功能用于开发测试，'
              '还不是正式的账号同步服务。',
            ),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.warning_amber_outlined),
            title: Text('卸载前请先备份'),
            subtitle: Text(
              '卸载应用或清除应用数据可能删除本地记录，'
              '建议定期导出备份。',
            ),
          ),
        ],
      ),
    );
  }
}
