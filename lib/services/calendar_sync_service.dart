import 'package:device_calendar_plus/device_calendar_plus.dart';

import '../models/nju_course.dart';

class CalendarSyncService {
  static const importMarker = '[NJU_SCHEDULE_IMPORT]';

  Future<CalendarPermissionStatus> _ensurePermissions() async {
    final status = await DeviceCalendar.instance.hasPermissions();

    if (status == CalendarPermissionStatus.notDetermined) {
      final requested = await DeviceCalendar.instance.requestPermissions();
      if (requested != CalendarPermissionStatus.granted &&
          requested != CalendarPermissionStatus.writeOnly) {
        throw Exception('未获得日历权限：$requested');
      }
      return requested;
    }

    if (status != CalendarPermissionStatus.granted &&
        status != CalendarPermissionStatus.writeOnly) {
      throw Exception('当前日历权限状态为：$status');
    }

    return status;
  }

  Future<List<Calendar>> listWritableCalendars() async {
    await _ensurePermissions();
    final calendars = await DeviceCalendar.instance.listCalendars();
    return calendars.where((calendar) => !calendar.readOnly).toList();
  }

  Future<CalendarSyncResult> syncEvents({
    required String calendarId,
    required ScheduleBundle bundle,
    required bool overwritePreviousImports,
  }) async {
    final permission = await _ensurePermissions();

    var deleted = 0;
    var skipped = 0;
    String? warning;

    final rangeStart = (bundle.earliestStart ?? DateTime.now())
        .subtract(const Duration(days: 7));
    final rangeEnd =
        (bundle.latestEnd ?? DateTime.now()).add(const Duration(days: 7));

    if (overwritePreviousImports &&
        permission == CalendarPermissionStatus.granted) {
      final oldEvents = await DeviceCalendar.instance.listEvents(
        rangeStart,
        rangeEnd,
        calendarIds: [calendarId],
      );

      for (final event in oldEvents) {
        final description = event.description ?? '';
        if (description.contains(importMarker)) {
          String? targetId = event.eventId;
          if (targetId == null || targetId.isEmpty) {
            targetId = event.instanceId;
          }

          if (targetId != null && targetId.isNotEmpty) {
            try {
              await DeviceCalendar.instance.deleteEvent(eventId: targetId);
              deleted += 1;
            } catch (_) {
              // 静默忽略单个日程删除失败的情况
            }
          }
        }
      }
    } else if (overwritePreviousImports &&
        permission == CalendarPermissionStatus.writeOnly) {
      warning = '当前只有写入级权限，无法读取旧事件，因此本次未执行覆盖删除，可能会产生重复。';
    }

    var created = 0;
    for (final item in bundle.events) {
      final title = item.title.trim();
      if (title.isEmpty) {
        skipped += 1;
        continue;
      }

      await DeviceCalendar.instance.createEvent(
        calendarId: calendarId,
        title: title,
        startDate: item.start,
        endDate: item.end,
        description: item.description,
        location: item.location,
        timeZone: 'Asia/Shanghai',
        availability: EventAvailability.busy,
      );
      created += 1;
    }

    return CalendarSyncResult(
      created: created,
      deleted: deleted,
      skipped: skipped,
      warning: warning,
    );
  }

  Future<int> deleteImportedEvents({
    required String calendarId,
  }) async {
    final permission = await _ensurePermissions();

    if (permission != CalendarPermissionStatus.granted) {
      throw Exception('当前权限只能写入，无法读取已有事件；请在系统设置中授予完整日历权限后再试。');
    }

    final now = DateTime.now();
    var deleted = 0;

    for (int i = -2; i <= 2; i++) {
      final year = now.year + i;
      final rangeStart = DateTime(year, 1, 1);
      final rangeEnd = DateTime(year, 12, 31, 23, 59, 59);

      try {
        final events = await DeviceCalendar.instance.listEvents(
          rangeStart,
          rangeEnd,
          calendarIds: [calendarId],
        );

        for (final event in events) {
          final description = event.description ?? '';
          if (!description.contains(importMarker)) continue;

          String? targetId = event.eventId;
          if (targetId == null || targetId.isEmpty) {
            targetId = event.instanceId;
          }

          if (targetId == null || targetId.isEmpty) {
            continue;
          }

          try {
            await DeviceCalendar.instance.deleteEvent(eventId: targetId);
            deleted += 1;
          } catch (_) {
            // 静默忽略单个日程删除失败的情况
          }
        }
      } catch (_) {
        // 静默忽略某一年份查询失败的情况
      }
    }

    return deleted;
  }
}