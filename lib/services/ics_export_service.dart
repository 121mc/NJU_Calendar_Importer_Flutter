import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'calendar_import_metadata.dart';
import '../models/nju_course.dart';

class IcsExportService {
  /// Generates an iCalendar (RFC 5545) content string from [bundle].
  String generateIcsContent(ScheduleBundle bundle) {
    final builder = _IcsBuilder(
      prodId: '-//NJU Calendar Importer//NJU Schedule//ZH',
      calendarName: bundle.semesterName,
    );

    for (final event in bundle.events) {
      if (event.title.trim().isEmpty) continue;
      builder.addEvent(
        uid: '${event.importKey}@nju-calendar-importer',
        start: event.start,
        end: event.end,
        summary: event.title,
        location: event.location,
        description: _stripMetadataForIcs(event.description),
      );
    }

    return builder.build();
  }

  /// Writes the .ics file to a temporary directory and invokes the system
  /// share sheet. Returns the file path that was shared.
  Future<String> exportAndShare(ScheduleBundle bundle) async {
    final content = generateIcsContent(bundle);
    final dir = await getTemporaryDirectory();
    final filename = _sanitizeFilename('NJU_课表_${bundle.semesterName}.ics');
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content, encoding: utf8);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/calendar')],
      subject: 'NJU 课表 ${bundle.semesterName}',
    );

    return file.path;
  }

  /// Strips app-internal metadata markers from [description], keeping only
  /// the human-readable detail lines. Returns null if nothing remains.
  static String? _stripMetadataForIcs(String description) {
    final lines = description.split('\n');
    final humanLines = lines.where((line) {
      if (line == CalendarImportMetadata.currentMarker) return false;
      if (line == CalendarImportMetadata.legacyMarker) return false;
      if (line.startsWith('semester_id=')) return false;
      if (line.startsWith('import_key=')) return false;
      return line.trim().isNotEmpty;
    }).toList();
    if (humanLines.isEmpty) return null;
    return humanLines.join('\\n');
  }

  /// Replaces filesystem-unsafe characters in [name] with underscores.
  static String _sanitizeFilename(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

/// Internal helper that builds an iCalendar (RFC 5545) string.
class _IcsBuilder {
  _IcsBuilder({
    required this.prodId,
    required this.calendarName,
  });

  final String prodId;
  final String calendarName;

  final List<String> _events = [];

  void addEvent({
    required String uid,
    required DateTime start,
    required DateTime end,
    required String summary,
    String? location,
    String? description,
  }) {
    final lines = <String>[
      'BEGIN:VEVENT',
      'UID:$uid',
      'DTSTART;TZID=Asia/Shanghai:${_formatDateTime(start)}',
      'DTEND;TZID=Asia/Shanghai:${_formatDateTime(end)}',
      'SUMMARY:${_escapeText(summary)}',
    ];

    if (location != null && location.trim().isNotEmpty) {
      lines.add('LOCATION:${_escapeText(location)}');
    }

    if (description != null && description.trim().isNotEmpty) {
      lines.add('DESCRIPTION:${_escapeText(description)}');
    }

    lines.addAll([
      'STATUS:CONFIRMED',
      'END:VEVENT',
    ]);

    _events.add(lines.map(_foldLine).join('\r\n'));
  }

  String build() {
    final allLines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:$prodId',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${_escapeText(calendarName)}',
      'X-WR-TIMEZONE:Asia/Shanghai',
      // VTIMEZONE lines (all short, no folding needed)
      'BEGIN:VTIMEZONE',
      'TZID:Asia/Shanghai',
      'BEGIN:STANDARD',
      'DTSTART:19700101T000000',
      'TZOFFSETFROM:+0800',
      'TZOFFSETTO:+0800',
      'TZNAME:CST',
      'END:STANDARD',
      'END:VTIMEZONE',
    ];

    final header = allLines.map(_foldLine).join('\r\n');

    final body = _events.join('\r\n');

    return '$header\r\n$body\r\nEND:VCALENDAR\r\n';
  }

  /// Formats a [DateTime] as `YYYYMMDDTHHMMSS` per RFC 5545.
  static String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '${y}${m}${d}T${h}${min}${s}';
  }

  /// Escapes special characters in iCalendar text values per RFC 5545 §3.3.11.
  static String _escapeText(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll(',', '\\,')
        .replaceAll(';', '\\;')
        .replaceAll('\n', '\\n');
  }

  /// Folds a line at 75 octets per RFC 5545 §3.1.
  static String _foldLine(String line) {
    final bytes = utf8.encode(line);
    if (bytes.length <= 75) return line;

    final buffer = StringBuffer();
    var offset = 0;
    var first = true;

    while (offset < bytes.length) {
      final limit = first ? 75 : 74;
      var end = offset + limit;
      if (end > bytes.length) end = bytes.length;

      // Don't split a multi-byte UTF-8 character.
      while (end > offset && end < bytes.length && (bytes[end] & 0xC0) == 0x80) {
        end--;
      }

      buffer.write(utf8.decode(bytes.sublist(offset, end)));
      offset = end;

      if (offset < bytes.length) {
        buffer.write('\r\n ');
        first = false;
      }
    }

    return buffer.toString();
  }
}
