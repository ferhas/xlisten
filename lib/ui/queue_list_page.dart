import 'package:flutter/material.dart';

import '../state/listening_controller.dart';
import 'list_row.dart';

/// 单个 tab 的未读队列页。
class QueueListPage extends StatelessWidget {
  const QueueListPage({
    super.key,
    required this.controller,
    required this.tab,
    required this.onOpenPager,
  });

  final ListeningController controller;
  final String tab;
  final void Function(String tab, int index) onOpenPager;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AnimatedBuilder(
      animation: c,
      builder: (ctx, _) {
        final q = c.queue(tab);
        return RefreshIndicator(
          onRefresh: () async {
            final added = await c.refresh(tab);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(added > 0 ? '新增 $added 条' : '没有新内容'),
                duration: const Duration(seconds: 2),
              ));
            }
          },
          child: q.isEmpty
              ? _empty(ctx)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: q.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == 0) return _header(ctx, c.unreadCount(tab));
                    final it = q[i - 1];
                    final active = identical(c.currentItem, it);
                    return ListRow(
                      item: it,
                      active: active,
                      onOpen: () => onOpenPager(tab, i - 1),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _header(BuildContext ctx, int n) {
    final cs = Theme.of(ctx).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text('$n 条未听',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          if (n > 0)
            FilledButton.icon(
              onPressed: () {
                final q = controller.queue(tab);
                final idx = q.indexWhere((it) => !it.read);
                onOpenPager(tab, idx < 0 ? 0 : idx);
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('从头开始'),
            ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext ctx) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Icon(Icons.headphones, size: 56, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('这一批听完啦 🎧',
                    style: TextStyle(fontSize: 18), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text('下拉或点右上角刷新,抓取新内容',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: controller.loading ? null : () => controller.refresh(tab),
                  icon: const Icon(Icons.refresh),
                  label: const Text('抓取新内容'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
