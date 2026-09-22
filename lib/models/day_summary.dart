import 'day_type.dart';
import 'record.dart';

// Hours of one day. Weekday overtime (main session plus extra sessions) is
// kept apart from weekend/holiday work so the latter can be highlighted.
class DaySummary {
  final double regular;          // regular hours of the main session
  final double overtime;         // overtime on a workday, extra sessions included
  final double specialOvertime;  // everything logged on a weekend or holiday

  const DaySummary({
    this.regular = 0,
    this.overtime = 0,
    this.specialOvertime = 0,
  });

  double get totalOvertime => overtime + specialOvertime;
  double get total => regular + totalOvertime;

  factory DaySummary.fromSessions(DayType dayType, List<Record> sessions) {
    double regular = 0, overtime = 0;
    for (final s in sessions) {
      regular += s.totalHours ?? 0;
      overtime += s.otimeHours ?? 0;
    }

    return dayType.isWorkday
        ? DaySummary(regular: regular, overtime: overtime)
        : DaySummary(regular: regular, specialOvertime: overtime);
  }

  DaySummary operator +(DaySummary other) => DaySummary(
        regular: regular + other.regular,
        overtime: overtime + other.overtime,
        specialOvertime: specialOvertime + other.specialOvertime,
      );
}
