class NjuCourseEvent {
  NjuCourseEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.location,
    required this.description,
    required this.importKey,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String? location;
  final String description;
  final String importKey;
}

class ScheduleBundle {
  ScheduleBundle({
    required this.semesterName,
    required this.events,
    required this.courseCount,
    required this.examCount,
  });

  final String semesterName;
  final List<NjuCourseEvent> events;
  final int courseCount;
  final int examCount;

  DateTime? get earliestStart {
    if (events.isEmpty) return null;
    return events.map((e) => e.start).reduce((a, b) => a.isBefore(b) ? a : b);
  }

  DateTime? get latestEnd {
    if (events.isEmpty) return null;
    return events.map((e) => e.end).reduce((a, b) => a.isAfter(b) ? a : b);
  }
}

class CalendarSyncResult {
  CalendarSyncResult({
    required this.created,
    required this.deleted,
    required this.skipped,
    required this.warning,
  });

  final int created;
  final int deleted;
  final int skipped;
  final String? warning;
}
