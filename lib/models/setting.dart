class Setting {
  final int? id;
  final String key;
  final String value;
  final String timestamp;

  Setting({
    this.id,
    required this.key,
    required this.value,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'key': key,
      'value': value,
      'timestamp': timestamp,
    };
  }

  factory Setting.fromMap(Map<String, dynamic> map) {
    return Setting(
      id: map['id'],
      key: map['key'],
      value: map['value'],
      timestamp: map['timestamp'],
    );
  }
}