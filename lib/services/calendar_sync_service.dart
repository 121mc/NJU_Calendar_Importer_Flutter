import 'package:device_calendar_plus/device_calendar_plus.dart';

import '../models/nju_course.dart';
import 'calendar_import_metadata.dart';

class CalendarOverwriteRange {
  const CalendarOverwriteRange({
    required this.start,
    required this.end,
  });

  final DateTime start;
  final DateTime end;
}

class CalendarSyncService {
  static CalendarOverwriteRange overwriteRangeFor(ScheduleBundle bundle) {
    if (bundle.semesterEnd.isAfter(bundle.semesterStart)) {
      return CalendarOverwriteRange(
        start: bundle.semesterStart,
        end: bundle.semesterEnd,
      );
    }

    final earliest = bundle.earliestStart;
    final latest = bundle.latestEnd;
    if (earliest == null || latest == null) {
      throw StateError(
        'Cannot calculate overwrite range for an empty schedule.',
      );
    }

    final firstDay = DateTime(earliest.year, earliest.month, earliest.day);
    final lastDay = DateTime(latest.year, latest.month, latest.day);
    final monday = firstDay.subtract(
      Duration(days: firstDay.weekday - DateTime.monday),
    );
    final nextMonday = lastDay.add(
      Duration(days: DateTime.daysPerWeek - lastDay.weekday + 1),
    );
    final sundayEnd = nextMonday.subtract(const Duration(milliseconds: 1));

    return CalendarOverwriteRange(start: monday, end: sundayEnd);
  }

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

    if (overwritePreviousImports &&
        permission == CalendarPermissionStatus.granted) {
      deleted = await _deleteGeneratedEventsInRangeForSemester(
        calendarId: calendarId,
        range: overwriteRangeFor(bundle),
        semesterId: bundle.semesterId,
      );
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

  Future<int> deleteGeneratedEventsForBundle({
    required String calendarId,
    required ScheduleBundle bundle,
  }) async {
    final permission = await _ensurePermissions();

    if (permission != CalendarPermissionStatus.granted) {
      throw Exception('当前权限只能写入，无法读取已有事件；请在系统设置中授予完整日历权限后再试。');
    }

    return _deleteGeneratedEventsInRangeForSemester(
      calendarId: calendarId,
      range: overwriteRangeFor(bundle),
      semesterId: bundle.semesterId,
    );
  }

  Future<int> _deleteGeneratedEventsInRangeForSemester({
    required String calendarId,
    required CalendarOverwriteRange range,
    required String semesterId,
  }) async {
    final oldEvents = await DeviceCalendar.instance.listEvents(
      range.start,
      range.end,
      calendarIds: [calendarId],
    );
    var deleted = 0;
    for (final event in oldEvents) {
      if (CalendarImportMetadata.shouldDeleteForSemesterOverwrite(
        description: event.description,
        selectedSemesterId: semesterId,
      )) {
        var targetId = event.eventId;
        if (targetId.isEmpty) {
          targetId = event.instanceId;
        }
        if (targetId.isNotEmpty) {
          try {
            await DeviceCalendar.instance.deleteEvent(eventId: targetId);
            deleted += 1;
          } catch (_) {
            // 静默忽略单个日程删除失败的情况
          }
        }
      }
    }
    return deleted;
  }
}
