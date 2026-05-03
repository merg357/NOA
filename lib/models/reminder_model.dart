import 'dart:convert';

class ReminderModel {
  final String id;
  final String text;
  final DateTime? dueAt;
  final bool isDone;
  final DateTime createdAt;

  const ReminderModel({
    required this.id,
    required this.text,
    this.dueAt,
    this.isDone = false,
    required this.createdAt,
  });

  ReminderModel copyWith({
    String? id,
    String? text,
    DateTime? dueAt,
    bool? isDone,
    DateTime? createdAt,
  }) {
    return ReminderModel(
      id: id ?? this.id,
      text: text ?? this.text,
      dueAt: dueAt ?? this.dueAt,
      isDone: isDone ?? this.isDone,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'dueAt': dueAt?.toIso8601String(),
        'isDone': isDone,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ReminderModel.fromJson(Map<String, dynamic> j) => ReminderModel(
        id: j['id'] as String,
        text: j['text'] as String,
        dueAt: j['dueAt'] != null ? DateTime.parse(j['dueAt'] as String) : null,
        isDone: j['isDone'] as bool? ?? false,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  static String encodeList(List<ReminderModel> list) =>
      jsonEncode(list.map((r) => r.toJson()).toList());

  static List<ReminderModel> decodeList(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => ReminderModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
