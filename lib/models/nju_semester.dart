class NjuSemester {
  const NjuSemester({
    required this.id,
    required this.name,
    required this.year,
    required this.term,
    required this.start,
    required this.end,
    required this.isCurrent,
  });

  final String id;
  final String name;
  final String year;
  final String term;
  final DateTime start;
  final DateTime end;
  final bool isCurrent;

  factory NjuSemester.fromUndergradRow(
    Map<String, dynamic> row, {
    required String? currentSemesterId,
  }) {
    final year = '${row['XN'] ?? ''}'.trim();
    final term = '${row['XQ'] ?? ''}'.trim();
    final id = '$year-$term';
    final start = _parseDateOnly('${row['XQKSRQ'] ?? ''}');
    final weekCount = int.tryParse('${row['ZZC'] ?? ''}') ?? 0;
    final safeWeekCount = weekCount <= 0 ? 1 : weekCount;

    return NjuSemester(
      id: id,
      name: '$year瀛﹀勾 ${_termDisplayName(term)}',
      year: year,
      term: term,
      start: start,
      end: start
          .add(Duration(days: safeWeekCount * DateTime.daysPerWeek))
          .subtract(const Duration(milliseconds: 1)),
      isCurrent: id == currentSemesterId,
    );
  }

  static (String, String) currentUndergradIdAndName(Map<String, dynamic> row) {
    final id = '${row['DM'] ?? ''}'.trim();
    final name = '${row['MC'] ?? id}'.trim();
    return (id, name.isEmpty ? id : name);
  }

  static String _termDisplayName(String term) {
    switch (term) {
      case '1':
        return '绗?瀛︽湡';
      case '2':
        return '绗?瀛︽湡';
      case '3':
        return '鏆戞湡';
      default:
        return '绗?term瀛︽湡';
    }
  }

  static DateTime _parseDateOnly(String text) {
    final clean = text.trim();
    if (clean.length < 10) {
      throw FormatException('Invalid semester start date: $text');
    }
    return DateTime.parse(clean.substring(0, 10));
  }
}
