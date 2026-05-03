import 'package:noa/models/app_mode.dart';

/// A compact card to display on the Frame wearable HUD.
class WearableCard {
  final String id;
  final String title;
  final String body;
  final String icon;
  final int priority; // 0 = normal, 1 = high, 2 = urgent
  final AppMode mode;
  final DateTime timestamp;
  final double? progress; // 0.0 – 1.0, null = no bar
  final int? ttlSeconds; // null = no expiry
  final String? actionLabel;
  final WearableCardType cardType;

  const WearableCard({
    required this.id,
    required this.title,
    required this.body,
    this.icon = '⬡',
    this.priority = 0,
    this.mode = AppMode.standard,
    required this.timestamp,
    this.progress,
    this.ttlSeconds,
    this.actionLabel,
    this.cardType = WearableCardType.info,
  });

  /// Formats the card into a single Frame-safe text string (max 200 chars).
  String toFrameString() {
    final prefix = icon.isNotEmpty ? '$icon ' : '';
    final main = '$prefix$title\n$body';
    if (main.length > 200) {
      return main.substring(0, 197) + '...';
    }
    return main;
  }

  WearableCard copyWith({
    String? id,
    String? title,
    String? body,
    String? icon,
    int? priority,
    AppMode? mode,
    DateTime? timestamp,
    double? progress,
    int? ttlSeconds,
    String? actionLabel,
    WearableCardType? cardType,
  }) {
    return WearableCard(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      icon: icon ?? this.icon,
      priority: priority ?? this.priority,
      mode: mode ?? this.mode,
      timestamp: timestamp ?? this.timestamp,
      progress: progress ?? this.progress,
      ttlSeconds: ttlSeconds ?? this.ttlSeconds,
      actionLabel: actionLabel ?? this.actionLabel,
      cardType: cardType ?? this.cardType,
    );
  }
}

enum WearableCardType {
  info,
  alert,
  reminder,
  note,
  visionSummary,
  timer,
  dailyBrief,
}
