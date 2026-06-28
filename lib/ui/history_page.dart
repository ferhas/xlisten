import 'package:flutter/material.dart';

import '../core/text_utils.dart';
import '../state/listening_controller.dart';

/// 收听历史:已听归档,可重听。
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.controller});

  final ListeningController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AnimatedBuilder(
      animation: c,
      builder: (ctx, _) {
        final h = c.history;
        return Scaffold(
          appBar: AppBar(title: const Text('收听历史')),
          body: h.isEmpty
              ? const Center(child: Text('还没有听过的内容'))
              : ListView.separated(
                  itemCount: h.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final it = h[i];
                    final cl = clean(it.text);
                    final preview = cl.isEmpty ? it.text : cl;
                    return ListTile(
                      title: Text(it.author.isEmpty ? it.handle : it.author,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(preview,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.replay),
                        tooltip: '重听',
                        onPressed: () {
                          c.replayFromHistory(it);
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
