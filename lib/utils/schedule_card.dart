import 'package:flutter/material.dart';

import '../models/nju_course.dart';

class ScheduleCard extends StatelessWidget {
  const ScheduleCard({
    super.key,
    required this.bundle,
  });

  final ScheduleBundle bundle;

  @override
  Widget build(BuildContext context) {
    final preview = bundle.events.take(8).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '课表预览',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('学期：${bundle.semesterName}'),
            Text('课程条目：${bundle.courseCount}'),
            Text('考试条目：${bundle.examCount}'),
            Text('最终生成事件数：${bundle.events.length}'),
            const SizedBox(height: 12),
            for (final item in preview)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(_formatDateTimeRange(item.start, item.end)),
                    if (item.location != null) Text(item.location!),
                  ],
                ),
              ),
            if (bundle.events.length > preview.length)
              Text('其余 ${bundle.events.length - preview.length} 条事件将在同步时写入日历。'),
          ],
        ),
      ),
    );
  }

  String _formatDateTimeRange(DateTime start, DateTime end) {
    final mm = start.month.toString().padLeft(2, '0');
    final dd = start.day.toString().padLeft(2, '0');
    final sh = start.hour.toString().padLeft(2, '0');
    final sm = start.minute.toString().padLeft(2, '0');
    final eh = end.hour.toString().padLeft(2, '0');
    final em = end.minute.toString().padLeft(2, '0');
    return '$mm-$dd $sh:$sm ~ $eh:$em';
  }
}
