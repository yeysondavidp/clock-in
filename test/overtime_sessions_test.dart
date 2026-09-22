import 'package:clock_in/models/day_summary.dart';
import 'package:clock_in/models/day_type.dart';
import 'package:clock_in/models/record.dart';
import 'package:clock_in/utils/time_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

Record _session(String type, double regular, double overtime) => Record(
      date: '2026-09-22',
      startTime: '09:00',
      endTime: '10:00',
      totalHours: regular,
      otimeHours: overtime,
      type: type,
      timestamp: '',
    );

void main() {
  group('TimeCalculator.minutesBetween', () {
    test('handles same-day sessions', () {
      expect(TimeCalculator.minutesBetween('09:00', '17:40'), 520);
    });

    test('rolls over midnight', () {
      expect(TimeCalculator.minutesBetween('23:00', '01:00'), 120);
    });
  });

  group('TimeCalculator.calculateSessionHours', () {
    test('regular session keeps lunch deduction and standard hours', () {
      final h = TimeCalculator.calculateSessionHours('09:00', '17:40',
          allOvertime: false, standardHours: 8, lunchBreakMinutes: 30);
      expect(h.overtime, closeTo(40 / 60, 1e-9));
      expect(h.regular, closeTo(8 - 30 / 60, 1e-9));
    });

    test('overtime session counts every minute, no lunch deduction', () {
      final h = TimeCalculator.calculateSessionHours('08:00', '16:00',
          allOvertime: true, standardHours: 8, lunchBreakMinutes: 30);
      expect(h.regular, 0);
      expect(h.overtime, 8);
    });

    test('overtime session across midnight', () {
      final h = TimeCalculator.calculateSessionHours('23:00', '01:00',
          allOvertime: true, standardHours: 8, lunchBreakMinutes: 30);
      expect(h.overtime, 2);
    });
  });

  group('DayType.resolve', () {
    const workDays = {1, 2, 3, 4, 5};

    test('weekday is a workday', () {
      expect(DayType.resolve(DateTime(2026, 9, 22), workDays, {}), DayType.workday);
    });

    test('Saturday outside work_days is a weekend', () {
      expect(DayType.resolve(DateTime(2026, 9, 26), workDays, {}), DayType.weekend);
    });

    test('holiday wins over weekend', () {
      expect(DayType.resolve(DateTime(2026, 4, 25), workDays, {'2026-04-25'}),
          DayType.holiday);
    });
  });

  group('DaySummary.fromSessions', () {
    test('workday adds extra sessions to overtime', () {
      final s = DaySummary.fromSessions(DayType.workday, [
        _session(Record.typeRegular, 7.5, 0.5),
        _session(Record.typeExtra, 0, 1),
      ]);
      expect(s.regular, 7.5);
      expect(s.overtime, 1.5);
      expect(s.specialOvertime, 0);
      expect(s.total, 9);
    });

    test('weekend and holiday overtime is tracked separately', () {
      final s = DaySummary.fromSessions(DayType.holiday, [
        _session(Record.typeExtra, 0, 4),
        _session(Record.typeExtra, 0, 1),
      ]);
      expect(s.specialOvertime, 5);
      expect(s.overtime, 0);
      expect(s.total, 5);
    });
  });
}
