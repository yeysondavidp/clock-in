class TimeCalculator {

  // Receives two strings like '08:05' and '17:30'
  // Returns total hours worked as a double like 9.41
  static double calculateTotalHours(String startTime, String endTime, int lunchBreakMinutes) {
    final rawMinutes = minutesBetween(startTime, endTime);

    // Deduct lunch break only if worked more than 6 hours (360 min)
    final workedMinutes = rawMinutes > 360
        ? rawMinutes - lunchBreakMinutes
        : rawMinutes;

    return workedMinutes / 60.0;
  }

  static double calculateRegularHours(String startTime, String endTime,
      double standardHours, int lunchBreakMinutes) {
    final totalWorked = calculateTotalHours(startTime, endTime, lunchBreakMinutes);
    final overtime = calculateOvertimeHours(startTime, endTime, standardHours);

    // Regular hours = net worked minus overtime
    final regular = totalWorked - overtime;
    return regular > 0 ? regular : totalWorked;
  }

  // Receives total hours worked and the standard hours from settings
  // Returns overtime hours, minimum 0
  static double calculateOvertimeHours(String startTime, String endTime, double standardHours) {
    // Overtime calculated on raw hours before lunch deduction
    final rawHours = minutesBetween(startTime, endTime) / 60.0;
    final overtime = rawHours - standardHours;
    return overtime > 0 ? overtime : 0.0;
  }

  // Hours of a finished session. Extra sessions and any session on a weekend
  // or holiday count entirely as overtime, with no lunch break deduction.
  static ({double regular, double overtime}) calculateSessionHours(
      String startTime, String endTime,
      {required bool allOvertime,
      required double standardHours,
      required int lunchBreakMinutes}) {
    if (allOvertime) {
      return (regular: 0.0, overtime: minutesBetween(startTime, endTime) / 60.0);
    }
    return (
      regular: calculateRegularHours(startTime, endTime, standardHours, lunchBreakMinutes),
      overtime: calculateOvertimeHours(startTime, endTime, standardHours),
    );
  }

  // Minutes from start to end. An end earlier than the start means the
  // session crossed midnight, so it ends on the next day.
  static int minutesBetween(String startTime, String endTime) {
    final minutes = _parseTime(endTime).difference(_parseTime(startTime)).inMinutes;
    return minutes < 0 ? minutes + 24 * 60 : minutes;
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

  static String roundTime(String time, int toleranceMinutes) {
    if (toleranceMinutes == 0) return time;

    final parts = time.split(':');
    int hour = int.parse(parts[0]);
    int minute = int.parse(parts[1]);

    // Always round to nearest multiple of 5
    final lowerMultiple = (minute ~/ 5) * 5;
    final upperMultiple = lowerMultiple + 5;

    final distToLower = minute - lowerMultiple;
    final distToUpper = upperMultiple - minute;

    // Pick nearest multiple of 5
    int roundedMinute;
    if (distToLower <= distToUpper) {
      roundedMinute = lowerMultiple;
    } else {
      roundedMinute = upperMultiple;
    }

    // Only apply if within tolerance
    final diff = (minute - roundedMinute).abs();
    if (diff > toleranceMinutes) return time;

    // Handle overflow
    if (roundedMinute == 60) {
      roundedMinute = 0;
      hour = (hour + 1) % 24;
    }

    return '${hour.toString().padLeft(2, '0')}:${roundedMinute.toString().padLeft(2, '0')}';
  }
}
