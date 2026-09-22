import '../database/database_helper.dart';
import '../models/record.dart';
import '../utils/time_calculator.dart';

class SessionService {
  static final SessionService instance = SessionService._init();
  SessionService._init();

  final db = DatabaseHelper.instance;

  // Returns the session with the given times and its hours recalculated.
  // Hours stay empty until the session has both a start and an end.
  Future<Record> withTimes(Record session,
      {required String? startTime, required String? endTime}) async {
    double? totalHours;
    double? otimeHours;

    if (startTime != null && endTime != null) {
      final standardHours = double.parse(
          await db.getSetting('standard_work_hours') ?? '8');
      final lunchBreak = int.parse(
          await db.getSetting('lunch_break_minutes') ?? '30');
      final dayType = await db.getDayType(session.date);

      final hours = TimeCalculator.calculateSessionHours(
        startTime,
        endTime,
        allOvertime: session.isExtra || !dayType.isWorkday,
        standardHours: standardHours,
        lunchBreakMinutes: lunchBreak,
      );
      totalHours = hours.regular;
      otimeHours = hours.overtime;
    }

    return Record(
      id: session.id,
      date: session.date,
      startTime: startTime,
      endTime: endTime,
      totalHours: totalHours,
      otimeHours: otimeHours,
      type: session.type,
      timestamp: session.timestamp,
    );
  }
}
