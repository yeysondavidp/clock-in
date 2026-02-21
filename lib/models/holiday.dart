class Holiday {
  final int? id;
  final String name;
  final String date;
  final String timestamp;

  Holiday({
    this.id,
    required this.name,
    required this.date,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'date': date,
      'timestamp': timestamp,
    };
  }

  factory Holiday.fromMap(Map<String, dynamic> map) {
    return Holiday(
      id: map['id'],
      name: map['name'],
      date: map['date'],
      timestamp: map['timestamp'],
    );
  }
}