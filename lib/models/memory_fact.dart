import 'dart:convert';

/// A persistent fact the assistant remembers about the user or their world.
class MemoryFact {
  final String id;
  final String key;
  final String value;
  final DateTime savedAt;

  const MemoryFact({
    required this.id,
    required this.key,
    required this.value,
    required this.savedAt,
  });

  MemoryFact copyWith({
    String? id,
    String? key,
    String? value,
    DateTime? savedAt,
  }) {
    return MemoryFact(
      id: id ?? this.id,
      key: key ?? this.key,
      value: value ?? this.value,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'value': value,
        'savedAt': savedAt.toIso8601String(),
      };

  factory MemoryFact.fromJson(Map<String, dynamic> j) => MemoryFact(
        id: j['id'] as String,
        key: j['key'] as String,
        value: j['value'] as String,
        savedAt: DateTime.parse(j['savedAt'] as String),
      );

  static String encodeList(List<MemoryFact> list) =>
      jsonEncode(list.map((f) => f.toJson()).toList());

  static List<MemoryFact> decodeList(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => MemoryFact.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
