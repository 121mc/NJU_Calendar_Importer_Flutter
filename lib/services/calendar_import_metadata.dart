class CalendarImportMetadata {
  const CalendarImportMetadata({
    required this.isGeneratedByApp,
    required this.isLegacy,
    required this.semesterId,
  });

  static const currentMarker = '[NJU_CALENDAR_IMPORTER]';
  static const legacyMarker = '[NJU_SCHEDULE_IMPORT]';
  static const legacyGroupLabel = '旧版本导入（未记录学期）';

  final bool isGeneratedByApp;
  final bool isLegacy;
  final String? semesterId;

  static String buildDescription({
    required String semesterId,
    required String importKey,
    required Iterable<String> detailLines,
  }) {
    final details =
        detailLines.where((line) => line.trim().isNotEmpty).toList();
    return [
      ...details,
      if (details.isNotEmpty) '',
      currentMarker,
      'semester_id=$semesterId',
      'import_key=$importKey',
    ].join('\n');
  }

  static CalendarImportMetadata parse(String? description) {
    final text = description ?? '';
    final hasCurrentMarker = text.contains(currentMarker);
    final hasLegacyMarker = text.contains(legacyMarker);
    final semesterId = RegExp(r'^semester_id=(.+)$', multiLine: true)
        .firstMatch(text)
        ?.group(1)
        ?.trim();

    return CalendarImportMetadata(
      isGeneratedByApp: hasCurrentMarker || hasLegacyMarker,
      isLegacy: hasLegacyMarker && !hasCurrentMarker,
      semesterId: semesterId == null || semesterId.isEmpty ? null : semesterId,
    );
  }

  static bool shouldDeleteForSemesterOverwrite({
    required String? description,
    required String selectedSemesterId,
  }) {
    final metadata = parse(description);
    if (!metadata.isGeneratedByApp) {
      return false;
    }
    if (metadata.semesterId == null) {
      return true;
    }
    return metadata.semesterId == selectedSemesterId;
  }

  static List<GeneratedEventsGroup> groupGeneratedEvents(
    Iterable<ImportedCalendarEvent> events,
  ) {
    final grouped = <String, List<ImportedCalendarEvent>>{};
    for (final event in events) {
      final metadata = parse(event.description);
      if (!metadata.isGeneratedByApp) {
        continue;
      }
      final key = metadata.semesterId ?? '';
      grouped.putIfAbsent(key, () => []).add(event);
    }

    final groups = grouped.entries.map((entry) {
      final semesterId = entry.key.isEmpty ? null : entry.key;
      return GeneratedEventsGroup(
        semesterId: semesterId,
        label: semesterId ?? legacyGroupLabel,
        events: List.unmodifiable(entry.value),
      );
    }).toList();

    groups.sort((a, b) {
      if (a.semesterId == null && b.semesterId != null) return 1;
      if (a.semesterId != null && b.semesterId == null) return -1;
      return b.label.compareTo(a.label);
    });
    return groups;
  }
}

class ImportedCalendarEvent {
  const ImportedCalendarEvent({
    required this.deleteId,
    required this.calendarId,
    required this.calendarName,
    required this.description,
  });

  final String deleteId;
  final String calendarId;
  final String calendarName;
  final String? description;
}

class GeneratedEventsGroup {
  const GeneratedEventsGroup({
    required this.semesterId,
    required this.label,
    required this.events,
  });

  final String? semesterId;
  final String label;
  final List<ImportedCalendarEvent> events;

  int get count => events.length;
}
