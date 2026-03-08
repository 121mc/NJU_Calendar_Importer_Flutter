import 'package:flutter/material.dart';

import '../models/login_models.dart';

class FetchCard extends StatelessWidget {
  const FetchCard({
    super.key,
    required this.session,
    required this.includeFinalExams,
    required this.onIncludeFinalExamsChanged,
    required this.loadingSchedule,
    required this.onLoadSchedule,
  });

  final SessionInfo session;
  final bool includeFinalExams;
  final ValueChanged<bool> onIncludeFinalExamsChanged;
  final bool loadingSchedule;
  final VoidCallback onLoadSchedule;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '拉取课表',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (session.schoolType.supportsFinalExams)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: includeFinalExams,
                onChanged: onIncludeFinalExamsChanged,
                title: const Text('本科课表同时导入期末考试'),
              ),
            FilledButton.icon(
              onPressed: loadingSchedule ? null : onLoadSchedule,
              icon: loadingSchedule
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: const Text('拉取当前学期课表'),
            ),
          ],
        ),
      ),
    );
  }
}
