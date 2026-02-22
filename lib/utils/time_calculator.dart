class TimeCalculator {

  // Receives two strings like '08:05' and '17:30'
  // Returns total hours worked as a double like 9.41
  static double calculateTotalHours(String startTime, String endTime, int lunchBreakMinutes) {
    final start = _parseTime(startTime);
    final end = _parseTime(endTime);

    final rawMinutes = end.difference(start).inMinutes;

    // Deduct lunch break only if worked more than 6 hours (360 min)
    final workedMinutes = rawMinutes > 360
        ? rawMinutes - lunchBreakMinutes
        : rawMinutes;

    return workedMinutes / 60.0;
  }

  // Receives total hours worked and the standard hours from settings
  // Returns overtime hours, minimum 0
  static double calculateOvertimeHours(String startTime, String endTime, double standardHours) {
    final start = _parseTime(startTime);
    final end = _parseTime(endTime);

    // Overtime calculated on raw hours before lunch deduction
    final rawHours = end.difference(start).inMinutes / 60.0;
    final overtime = rawHours - standardHours;
    return overtime > 0 ? overtime : 0.0;
  }

  // Helper: converts '08:05' into a DateTime object so Dart can subtract them
  // We use today's date because we only care about the time difference
  static DateTime _parseTime(String time) {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  // Receives a double like 9.41 and returns a readable string '9h 24m'
  static String formatHours(double hours) {
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;   // ~/ is integer division, like (int) in Java
    final m = totalMinutes % 60;
    return '${h}h ${m}m';
  }
}
