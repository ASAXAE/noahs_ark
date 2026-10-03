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
          Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('诺亚方舟数据与隐私说明\n适用于当前开发和测试版本 · 更新于 2026-10-03'),
          ),
          ListTile(
            leading: Icon(Icons.phone_android_outlined),
            title: Text('记录保存在本机'),
            subtitle: Text(
              '正式记录、闪念草稿和转写文本保存在当前设备。'
              '无需账号即可使用本地记录功能，登录不会自动上传记录或录音。'
              '本地内容没有自动过期时间，由你主动删除。',
            ),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.mic_none_outlined),
            title: Text('录音与转写由你选择'),
            subtitle: Text(
              '点击开始录音后才申请麦克风及必要的通知权限。'
              '录音可在后台继续，请点击停止并保存结束。'
              '保存后不会自动转写；选择转写时，录音在本机处理，'
              '录音和转写结果不会由应用上传。转写后原始录音仍然保留。',
            ),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.download_outlined),
            title: Text('首次转写需要下载模型'),
            subtitle: Text(
              '缺少模型时，应用会先征求你的确认，再从 Hugging Face '
              '下载约 228 MB 的模型及词表，使用网络流量和设备空间。'
              '下载服务可接收到 IP 地址和文件请求，但不会收到你的录音、'
              '转写文本或本地记录。取消下载时不会转写所选录音。'
              '模型安装后可离线转写，模型文件会继续保留在本机。',
            ),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.backup_outlined),
            title: Text('备份由你控制'),
            subtitle: Text(
              '主动导出的 JSON 文件包含正式记录，不包含原始录音。'
              '你选择的保存位置或分享应用可能接收文件。'
              '本地记录及 JSON 备份未由应用单独加密，请妥善保管。'
              '删除应用内数据不会修改之前的备份，外部副本需另行删除。',
            ),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('服务器功能仍在实验中'),
            subtitle: Text(
              '注册、登录等账号操作会向配置的后端发送必要的昵称、邮箱、'
              '密码或令牌。服务器保存账号信息和密码、令牌的哈希。'
              'Railway 测试部署只用于一次性测试账号和测试记录，'
              '目前没有接入真实邮件服务。同步及云端 AI 处理尚未启用。',
            ),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('删除范围分别管理'),
            subtitle: Text(
              '删除正式记录会保留关联的闪念草稿和录音；'
              '成功删除闪念会删除该草稿及原始录音，保留已转换出的正式记录。'
              '删除账号会删除服务器账号及其关联数据，并清除本机登录凭据，'
              '保留本地记录、录音和导出文件。服务器旧备份仍可能包含已删除数据。',
            ),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.schedule_outlined),
            title: Text('服务器数据的保留'),
            subtitle: Text(
              '当前测试账号及历史令牌没有定时清理机制，令牌失效不代表记录已删除。'
              '测试环境数据库备份按运维规则保留最近七组成功副本，人工清理旧副本。'
              '应用请求日志不记录正文、密码或原始令牌；托管平台日志按其规则保留。'
              '正式服务的数据清理周期和流程尚待上线前落实。',
            ),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('其他第三方处理'),
            subtitle: Text(
              '当前没有接入广告、第三方行为分析或云端内容处理服务。'
              '联网服务可能处理必要的网络信息，分享文件由所选应用继续处理。'
              '第三方政策可查看或复制下方地址。',
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SelectableText(
              'Hugging Face：https://huggingface.co/privacy\n'
              'Railway：https://railway.com/legal/privacy',
            ),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.warning_amber_outlined),
            title: Text('卸载前请先备份'),
            subtitle: Text(
              'Android 已配置排除应用数据的系统云备份和设备迁移。'
              '不同厂商工具的行为仍需实际验证，请使用主动导出，'
              '不要依赖系统自动恢复。卸载或清除应用数据可能删除本地记录和录音；'
              '当前 JSON 备份不包含录音。',
            ),
          ),
        ],
      ),
    );
  }
}
