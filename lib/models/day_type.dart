enum DayType {
  workday,
  weekend,
  holiday;

  bool get isWorkday => this == DayType.workday;

  String get label => switch (this) {
        DayType.workday => 'Workday',
        DayType.weekend => 'Weekend',
        DayType.holiday => 'Holiday',
      };

  // Holidays win over weekends: a holiday on a Saturday is still a holiday
  static DayType resolve(
      DateTime date, Set<int> workDays, Set<String> holidayDates) {
    final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if (holidayDates.contains(key)) return DayType.holiday;
    if (!workDays.contains(date.weekday)) return DayType.weekend;
    return DayType.workday;
  }
}
