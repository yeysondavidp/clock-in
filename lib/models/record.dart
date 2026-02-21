class Record {
  final int? id;
  final String date;
  final String? startTime;
  final String? endTime;
  final double? totalHours;
  final double? otimeHours;
  final String timestamp;

  Record({
    this.id,
    required this.date,
    this.startTime,
    this.endTime,
    this.totalHours,
    this.otimeHours,
    required this.timestamp,
  });

  // Converts object to Map for SQLite (like an associative array in PHP)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'start_time': startTime,
      'end_time': endTime,
      'total_hours': totalHours,
      'otime_hours': otimeHours,
      'timestamp': timestamp,
    };
  }

  // Creates object from Map (like mapping a DB row in PHP)
  factory Record.fromMap(Map<String, dynamic> map) {
    return Record(
      id: map['id'],
      date: map['date'],
      startTime: map['start_time'],
      endTime: map['end_time'],
      totalHours: map['total_hours'],
      otimeHours: map['otime_hours'],
      timestamp: map['timestamp'],
    );
  }
}