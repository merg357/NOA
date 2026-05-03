import 'dart:convert';

class NoteModel {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  const NoteModel({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  NoteModel copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? createdAt,
  }) {
    return NoteModel(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
      };

  factory NoteModel.fromJson(Map<String, dynamic> j) => NoteModel(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  static String encodeList(List<NoteModel> list) =>
      jsonEncode(list.map((n) => n.toJson()).toList());

  static List<NoteModel> decodeList(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => NoteModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
