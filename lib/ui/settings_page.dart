import 'package:flutter/material.dart';

import '../core/voices.dart';
import '../state/listening_controller.dart';
import 'history_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage(
      {super.key, required this.controller, required this.onRelogin});

  final ListeningController controller;
  final VoidCallback onRelogin;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AnimatedBuilder(
      animation: c,
      builder: (ctx, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: ListView(
            children: [
              _section(ctx, '朗读'),
              ListTile(
                title: const Text('音色'),
                subtitle: Text(voiceById(c.voice).name),
                trailing: TextButton.icon(
                  onPressed: () => c.previewVoice(),
                  icon: const Icon(Icons.volume_up, size: 18),
                  label: const Text('试听'),
                ),
              ),
              ...kVoices.map((v) => RadioListTile<String>(
                    value: v.id,
                    groupValue: c.voice,
                    onChanged: (x) {
                      if (x != null) c.setVoice(x);
                    },
                    title: Text(v.name),
                    subtitle: Text(v.desc),
                    secondary: IconButton(
                      icon: const Icon(Icons.play_arrow),
                      tooltip: '试听',
                      onPressed: () async {
                        await c.setVoice(v.id);
                        await c.previewVoice();
                      },
                    ),
                  )),
              const Divider(),
              ListTile(
                  title: const Text('语速'),
                  subtitle: Text(speedByRate(c.rate).label)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: kSpeeds
                      .map((s) => ChoiceChip(
                            label: Text(s.label),
                            selected: c.rate == s.rate,
                            onSelected: (_) => c.setRate(s.rate),
                          ))
                      .toList(),
                ),
              ),
              _section(ctx, '收听'),
              SwitchListTile(
                title: const Text('自动播放下一条'),
                value: c.autoAdvance,
                onChanged: c.setAutoAdvance,
              ),
              SwitchListTile(
                title: const Text('听完自动抓新内容'),
                value: c.autoFetch,
                onChanged: c.setAutoFetch,
              ),
              ListTile(
                title: const Text('收听历史'),
                subtitle: Text('已听 ${c.history.length} 条'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(ctx,
                    MaterialPageRoute(builder: (_) => HistoryPage(controller: c))),
              ),
              ListTile(
                title: const Text('清空收听历史'),
                subtitle: const Text('清掉已听记录,之前的内容可能再次出现'),
                onTap: () => _confirm(ctx, '清空收听历史?', c.clearHistory),
              ),
              ListTile(
                title: const Text('重新抓满'),
                subtitle: const Text('清空全部(队列+历史+已听),从头再来'),
                onTap: () => _confirm(ctx, '重新抓满?将清空全部记录', c.resetAll),
              ),
              _section(ctx, '账号'),
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('重新登录 X'),
                subtitle: const Text('在内置页面登录(登录后会自动记住,不用再登)'),
                onTap: () {
                  Navigator.pop(ctx);
                  onRelogin();
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_paste),
                title: const Text('导入登录(粘贴 cookie)'),
                subtitle: const Text('粘贴 auth_token / ct0,一次永久生效'),
                onTap: () => _importLogin(ctx),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('退出登录'),
                onTap: () => _confirm(ctx, '退出当前 X 登录?', () async {
                  await c.logout();
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    onRelogin();
                  }
                }),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  void _importLogin(BuildContext settingsCtx) {
    final tokenCtl = TextEditingController();
    final ct0Ctl = TextEditingController();
    showDialog(
      context: settingsCtx,
      builder: (dctx) => AlertDialog(
        title: const Text('导入登录'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  '从已登录 X 的电脑浏览器(F12 → Application → Cookies → x.com)或 PC 的 cookies.json 里复制粘贴:',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                  controller: tokenCtl,
                  decoration: const InputDecoration(
                      labelText: 'auth_token', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                  controller: ct0Ctl,
                  decoration: const InputDecoration(
                      labelText: 'ct0', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final t = tokenCtl.text.trim();
              final c0 = ct0Ctl.text.trim();
              Navigator.pop(dctx);
              if (t.isEmpty) return;
              await controller.importLogin(t, c0);
              if (settingsCtx.mounted) Navigator.pop(settingsCtx);
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext ctx, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t,
            style: TextStyle(
                color: Theme.of(ctx).colorScheme.primary,
                fontWeight: FontWeight.bold)),
      );

  void _confirm(BuildContext ctx, String msg, Future<void> Function() action) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await action();
              },
              child: const Text('确定')),
        ],
      ),
    );
  }
}
