enum NjuCourseEventKind {
  session,
  midtermExam,
  finalExam,
}

class NjuCourseDetails {
  const NjuCourseDetails({
    required this.studentId,
    required this.courseName,
    required this.courseCode,
    required this.credits,
    required this.teacher,
    required this.className,
    required this.studentClasses,
  });

  static const empty = NjuCourseDetails(
    studentId: '',
    courseName: '',
    courseCode: null,
    credits: null,
    teacher: null,
    className: null,
    studentClasses: null,
  );

  final String studentId;
  final String courseName;
  final String? courseCode;
  final String? credits;
  final String? teacher;
  final String? className;
  final String? studentClasses;
}

class NjuCourseEvent {
  NjuCourseEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.location,
    required this.description,
    required this.importKey,
    this.courseId = '',
    this.kind = NjuCourseEventKind.session,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String? location;
  final String description;
  final String importKey;
  final String courseId;
  final NjuCourseEventKind kind;
}

sealed class NjuScheduleChange {
  const NjuScheduleChange({
    required this.rawText,
    this.week,
    this.weekday,
    this.startSection,
    this.endSection,
  });

  final int? week;
  final int? weekday;
  final int? startSection;
  final int? endSection;
  final String rawText;
}

final class NjuCancelledClass extends NjuScheduleChange {
  const NjuCancelledClass({
    required super.rawText,
    super.week,
    super.weekday,
    super.startSection,
    super.endSection,
  });
}

final class NjuAddedClass extends NjuScheduleChange {
  const NjuAddedClass({
    required super.rawText,
    super.week,
    super.weekday,
    super.startSection,
    super.endSection,
    this.location,
    this.teacher,
  });

  final String? location;
  final String? teacher;
}

class NjuTimeChange {
  const NjuTimeChange({
    this.newWeek,
    this.newWeekday,
    this.newStartSection,
    this.newEndSection,
  });

  final int? newWeek;
  final int? newWeekday;
  final int? newStartSection;
  final int? newEndSection;
}

class NjuRoomChange {
  const NjuRoomChange({
    required this.originalRoom,
    required this.newRoom,
  });

  final String? originalRoom;
  final String? newRoom;
}

class NjuTeacherChange {
  const NjuTeacherChange({
    required this.originalTeacher,
    required this.newTeacher,
  });

  final String? originalTeacher;
  final String? newTeacher;
}

final class NjuRescheduledClass extends NjuScheduleChange {
  const NjuRescheduledClass({
    required super.rawText,
    super.week,
    super.weekday,
    super.startSection,
    super.endSection,
    this.timeChange,
    this.roomChange,
    this.teacherChange,
  });

  final NjuTimeChange? timeChange;
  final NjuRoomChange? roomChange;
  final NjuTeacherChange? teacherChange;
}

class NjuCourse {
  NjuCourse({
    required this.id,
    required this.details,
    this.sessions = const [],
    this.midtermExams = const [],
    this.finalExams = const [],
    this.addedClasses = const [],
    this.rescheduledClasses = const [],
    this.cancelledClasses = const [],
  });

  final String id;
  final NjuCourseDetails details;
  final List<NjuCourseEvent> sessions;
  final List<NjuCourseEvent> midtermExams;
  final List<NjuCourseEvent> finalExams;

  // Reserved for parsing and applying “后续调课信息”.
  final List<NjuAddedClass> addedClasses;
  final List<NjuRescheduledClass> rescheduledClasses;
  final List<NjuCancelledClass> cancelledClasses;

  List<NjuCourseEvent> get events => [
        ...sessions,
        ...midtermExams,
        ...finalExams,
      ]..sort((a, b) => a.start.compareTo(b.start));
}

class ScheduleBundle {
  ScheduleBundle({
    required this.semesterId,
    required this.semesterName,
    required this.semesterStart,
    required this.semesterEnd,
    this.courses = const [],
    List<NjuCourseEvent> events = const [],
    int? courseCount,
    int? examCount,
  })  : _standaloneEvents = events,
        courseCount = courseCount ?? courses.length,
        examCount = examCount ??
            courses.fold(
              0,
              (count, course) =>
                  count + course.midtermExams.length + course.finalExams.length,
            );

  final String semesterId;
  final String semesterName;
  final DateTime semesterStart;
  final DateTime semesterEnd;
  final List<NjuCourse> courses;
  final List<NjuCourseEvent> _standaloneEvents;
  final int courseCount;
  final int examCount;

  /// Flattened compatibility view consumed by calendar synchronization.
  List<NjuCourseEvent> get events => [
        for (final course in courses) ...course.events,
        ..._standaloneEvents,
      ]..sort((a, b) => a.start.compareTo(b.start));

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
