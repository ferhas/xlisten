import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/text_utils.dart';
import '../models/timeline_item.dart';

/// 大字号安全的列表行(不用固定高度的 ListTile)。
/// 整行点击进入全屏抖音式播放;已读条目变淡 + 显示对勾(下次刷新才移除)。
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.item,
    required this.active,
    required this.onOpen,
  });

  final TimelineItem item;
  final bool active;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cleaned = clean(item.text);
    final preview = cleaned.isEmpty ? item.text : cleaned;
    final read = item.read;
    return InkWell(
      onTap: onOpen,
      child: Opacity(
        opacity: read && !active ? 0.5 : 1.0,
        child: Container(
          color: active ? cs.primary.withOpacity(0.12) : null,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 10),
                child: Icon(
                  active
                      ? Icons.graphic_eq
                      : (read ? Icons.check_circle : Icons.fiber_manual_record),
                  size: active ? 22 : (read ? 18 : 10),
                  color: active
                      ? cs.primary
                      : (read ? cs.onSurfaceVariant : cs.primary),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.author.isEmpty ? item.handle : item.author,
                      maxLines: 2,
                      softWrap: true,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: active ? cs.primary : null),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (item.truncated || isEnglish(item.text))
                          _chip(context, Icons.translate, '看全文/译'),
                        if (relativeTime(item.time).isNotEmpty)
                          Text(relativeTime(item.time),
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext ctx, IconData ic, String t) {
    final cs = Theme.of(ctx).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ic, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(t, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
