import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart';

class CalendarCard extends StatelessWidget {
  const CalendarCard({
    super.key,
    required this.calendars,
    required this.selectedCalendarId,
    required this.loadingCalendars,
    required this.onLoadCalendars,
    required this.onCalendarChanged,
    required this.overwritePreviousImports,
    required this.onOverwritePreviousImportsChanged,
    required this.syncingCalendar,
    required this.onSyncToCalendar,
    required this.deletingImportedEvents,
    required this.onDeleteImportedEvents,
  });

  final List<Calendar> calendars;
  final String? selectedCalendarId;
  final bool loadingCalendars;
  final VoidCallback onLoadCalendars;
  final ValueChanged<String?> onCalendarChanged;
  final bool overwritePreviousImports;
  final ValueChanged<bool> onOverwritePreviousImportsChanged;
  final bool syncingCalendar;
  final VoidCallback onSyncToCalendar;
  final bool deletingImportedEvents;
  final VoidCallback onDeleteImportedEvents;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '系统日历同步',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: loadingCalendars ? null : onLoadCalendars,
                    icon: loadingCalendars
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.calendar_month),
                    label: const Text('加载手机日历'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedCalendarId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '选择写入目标日历',
                border: OutlineInputBorder(),
              ),
              items: calendars
                  .map(
                    (calendar) => DropdownMenuItem(
                      value: calendar.id,
                      child: Text(calendar.name),
                    ),
                  )
                  .toList(),
              onChanged: calendars.isEmpty ? null : onCalendarChanged,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: overwritePreviousImports,
              onChanged: onOverwritePreviousImportsChanged,
              title: const Text('覆盖删除本应用此前导入的旧事件'),
              subtitle: const Text('依赖读取权限；若只有写入权限则无法删除旧数据。'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: syncingCalendar ? null : onSyncToCalendar,
                    icon: syncingCalendar
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.event_available),
                    label: const Text('写入系统日历'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        (deletingImportedEvents || selectedCalendarId == null)
                            ? null
                            : onDeleteImportedEvents,
                    icon: deletingImportedEvents
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_sweep),
                    label: const Text('一键清空本应用导入事件'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
