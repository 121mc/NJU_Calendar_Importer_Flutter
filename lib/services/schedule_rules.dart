import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/nju_course.dart';
import 'holiday_service.dart';

const sectionStarts = [
  480,
  540,
  610,
  670,
  840,
  900,
  970,
  1030,
  1110,
  1170,
  1230,
  1290,
  1350
];
const sectionEnds = [
  530,
  590,
  660,
  720,
  890,
  950,
  1020,
  1080,
  1160,
  1220,
  1280,
  1340,
  1400
];

NjuCourseEvent reviseEvent(NjuCourseEvent e,
    {DateTime? start,
    DateTime? end,
    String? location,
    String? teacher,
    DateTime? holidayOriginalDate}) {
  start ??= e.start;
  end ??= e.end;
  location ??= e.location;
  final key = sha1
      .convert(utf8
          .encode('${e.courseId}|${e.kind}|${e.title}|$start|$end|$location'))
      .toString();
  var description = e.description.replaceAll(
      RegExp(r'^import_key=.*$', multiLine: true), 'import_key=$key');
  if (holidayOriginalDate != null) {
    description = description.replaceFirst(
      '\n',
      '\n调休：原${holidayOriginalDate.year}年${holidayOriginalDate.month}月${holidayOriginalDate.day}日的课程\n',
    );
  }
  if (teacher != null) description = '$description\n本次授课教师：$teacher';
  return NjuCourseEvent(
      title: e.title,
      start: start,
      end: end,
      location: location,
      description: description,
      importKey: key,
      courseId: e.courseId,
      kind: e.kind);
}

List<NjuScheduleChange> parseScheduleChanges(Iterable<String> texts) {
  final result = <NjuScheduleChange>[];
  final seen = <String>{};
  final slot =
      RegExp(r'第\s*(\d+)\s*周\s*周([一二三四五六日天])\s*(\d+)\s*[-–—~～]\s*(\d+)\s*节');
  for (final text in texts.toSet()) {
    for (final part in text.split(RegExp(r'(?=【(?:停课|加课|调课)】)'))) {
      if (!RegExp(r'^【(?:停课|加课|调课)】').hasMatch(part)) continue;
      if (!seen.add(part.trim().replaceAll(RegExp(r'[,，]+$'), ''))) continue;
      final slots = slot.allMatches(part).toList();
      if (slots.isEmpty) throw FormatException('无法识别调课时间：$part');
      final s = slots.first;
      final week = int.parse(s[1]!);
      final day = '一二三四五六日'.indexOf(s[2]!.replaceAll('天', '日')) + 1;
      final first = int.parse(s[3]!);
      final last = int.parse(s[4]!);
      if (week < 1 || first < 1 || last < first || last > 13) {
        throw FormatException('无效调课节次：$part');
      }
      String? field(String name) =>
          RegExp('$name为[（(]([^）)]*)[）)]').firstMatch(part)?.group(1);
      if (part.startsWith('【停课】')) {
        result.add(NjuCancelledClass(
            rawText: part,
            week: week,
            weekday: day,
            startSection: first,
            endSection: last));
      } else if (part.startsWith('【加课】')) {
        result.add(NjuAddedClass(
            rawText: part,
            week: week,
            weekday: day,
            startSection: first,
            endSection: last,
            location: field('教室'),
            teacher: field('教师')));
      } else {
        final room = field('教室');
        final teacher = field('教师');
        NjuTimeChange? time;
        if (slots.length > 1) {
          final target = slots.last;
          final a = int.parse(target[3]!);
          final b = int.parse(target[4]!);
          if (int.parse(target[1]!) < 1 || a < 1 || b < a || b > 13) {
            throw FormatException('无效调课目标：$part');
          }
          time = NjuTimeChange(
              newWeek: int.parse(target[1]!),
              newWeekday:
                  '一二三四五六日'.indexOf(target[2]!.replaceAll('天', '日')) + 1,
              newStartSection: a,
              newEndSection: b);
        }
        if (time == null && room == null && teacher == null) {
          throw FormatException('无法识别调课信息：$part');
        }
        result.add(NjuRescheduledClass(
            rawText: part,
            week: week,
            weekday: day,
            startSection: first,
            endSection: last,
            timeChange: time,
            roomChange: room == null
                ? null
                : NjuRoomChange(originalRoom: null, newRoom: room),
            teacherChange: teacher == null
                ? null
                : NjuTeacherChange(
                    originalTeacher: null, newTeacher: teacher)));
      }
    }
  }
  return result;
}

List<NjuCourseEvent> applyScheduleRules(
    List<NjuCourseEvent> sessions,
    DateTime anchor,
    List<NjuScheduleChange> changes,
    List<HolidayRule> holidays,
    {NjuCourseEvent? addedClassTemplate}) {
  DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
  DateTime date(int week, int weekday) =>
      anchor.add(Duration(days: (week - 1) * 7 + weekday - 1));
  DateTime at(DateTime d, int minutes) =>
      DateTime(d.year, d.month, d.day, minutes ~/ 60, minutes % 60);
  bool matches(NjuCourseEvent e, NjuScheduleChange c) =>
      day(e.start) == day(date(c.week!, c.weekday!)) &&
      e.start == at(e.start, sectionStarts[c.startSection! - 1]) &&
      e.end == at(e.end, sectionEnds[c.endSection! - 1]);
  for (final c in changes.where((c) => c is! NjuAddedClass)) {
    final d = date(c.week!, c.weekday!);
    final start = at(d, sectionStarts[c.startSection! - 1]);
    final end = at(d, sectionEnds[c.endSection! - 1]);
    for (final e in sessions) {
      if (e.start.isBefore(end) && e.end.isAfter(start) && !matches(e, c)) {
        throw FormatException('暂不支持部分节次调课，请核对：${c.rawText}');
      }
    }
  }
  final protected = <NjuCourseEvent>{};
  var events = [...sessions];
  // Match against original occurrences so room/teacher edits cannot hide a time edit.
  for (final original in sessions) {
    var event = original;
    var cancelled = false;
    var timeChanged = false;
    for (final c in changes.where((c) => matches(original, c))) {
      if (c is NjuCancelledClass) cancelled = true;
      if (c is NjuRescheduledClass) {
        final t = c.timeChange;
        final d = t == null
            ? null
            : date(t.newWeek ?? c.week!, t.newWeekday ?? c.weekday!);
        event = reviseEvent(event,
            start: d == null
                ? null
                : at(d,
                    sectionStarts[(t!.newStartSection ?? c.startSection!) - 1]),
            end: d == null
                ? null
                : at(d, sectionEnds[(t!.newEndSection ?? c.endSection!) - 1]),
            location: c.roomChange?.newRoom,
            teacher: c.teacherChange?.newTeacher);
        timeChanged |= t != null;
      }
    }
    events.remove(original);
    if (!cancelled) {
      events.add(event);
      if (timeChanged) protected.add(event);
    }
  }
  for (final c in changes.whereType<NjuAddedClass>()) {
    final template =
        addedClassTemplate ?? (sessions.isEmpty ? null : sessions.first);
    if (template == null) throw const FormatException('加课缺少课程模板');
    final d = date(c.week!, c.weekday!);
    final event = reviseEvent(template,
        start: at(d, sectionStarts[c.startSection! - 1]),
        end: at(d, sectionEnds[c.endSection! - 1]),
        location: c.location,
        teacher: c.teacher);
    events.add(event);
    protected.add(event);
  }
  final result = <NjuCourseEvent>[];
  for (final e in events) {
    if (protected.contains(e)) {
      result.add(e);
      continue;
    }
    final rules = holidays.where((h) => h.holiday == day(e.start));
    if (rules.isNotEmpty) {
      final target = rules.single.makeup;
      if (target != null) {
        final moved = reviseEvent(e,
            start: at(target, e.start.hour * 60 + e.start.minute),
            end: at(target, e.end.hour * 60 + e.end.minute),
            holidayOriginalDate: day(e.start));
        // A cancellation explicitly scheduled on the makeup date also wins.
        if (!changes
            .whereType<NjuCancelledClass>()
            .any((c) => matches(moved, c))) {
          result.add(moved);
        }
      }
    } else if (!holidays.any((h) => h.makeup == day(e.start))) {
      result.add(e);
    }
  }
  return {
    for (final e in result) '${e.courseId}|${e.start}|${e.end}|${e.location}': e
  }.values.toList()
    ..sort((a, b) => a.start.compareTo(b.start));
}
