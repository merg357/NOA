import 'package:logging/logging.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/wearable_card.dart';
import 'package:noa/util/tx_rich_text.dart';

final _log = Logger("FrameOutputService");

/// Sends [WearableCard]s and status banners to the Frame display over BLE.
///
/// Pass the connected [BrilliantDevice] (or equivalent) via [sendCard].
/// If no device is connected, calls are silently ignored.
class FrameOutputService {
  static const int _messageResponseFlag = 0x20;

  /// Sends [card] to Frame. The [sendMessage] callback must be wired to
  /// the connected device's sendMessage method.
  static Future<void> sendCard(
    WearableCard card,
    Future<void> Function(int flag, List<int> data) sendMessage,
  ) async {
    try {
      final text = card.toFrameString();
      await sendMessage(
        _messageResponseFlag,
        TxRichText(text: text, emoji: _cardEmoji(card)).pack(),
      );
      _log.info("Card sent to Frame: ${card.title}");
    } catch (e) {
      _log.warning("Failed to send card to Frame: $e");
    }
  }

  /// Sends a short status banner — e.g. "Reminder saved ✓".
  static Future<void> sendBanner(
    String message,
    Future<void> Function(int flag, List<int> data) sendMessage,
  ) async {
    try {
      final short = message.length > 80 ? message.substring(0, 77) + '...' : message;
      await sendMessage(
        _messageResponseFlag,
        TxRichText(text: short, emoji: "\u{F0003}").pack(),
      );
    } catch (e) {
      _log.warning("Failed to send banner to Frame: $e");
    }
  }

  /// Sends a "Listening…" status banner to Frame.
  static Future<void> sendListeningStatus(
    Future<void> Function(int flag, List<int> data) sendMessage,
  ) =>
      sendBanner('Listening\u2026', sendMessage);

  /// Sends a "Thinking…" status banner to Frame.
  static Future<void> sendThinkingStatus(
    Future<void> Function(int flag, List<int> data) sendMessage,
  ) =>
      sendBanner('Thinking\u2026', sendMessage);

  /// Sends a "Speaking…" status banner to Frame.
  static Future<void> sendSpeakingStatus(
    Future<void> Function(int flag, List<int> data) sendMessage,
  ) =>
      sendBanner('Speaking\u2026', sendMessage);

  /// Sends a "Connecting…" status banner to Frame.
  static Future<void> sendConnectingStatus(
    Future<void> Function(int flag, List<int> data) sendMessage,
  ) =>
      sendBanner('Connecting\u2026', sendMessage);

  /// Sends an "Interrupted" status banner to Frame.
  static Future<void> sendInterruptedStatus(
    Future<void> Function(int flag, List<int> data) sendMessage,
  ) =>
      sendBanner('Interrupted', sendMessage);

  /// Sends a reminder-confirmed card to Frame.
  static Future<void> sendReminderCard(
    String reminderText,
    Future<void> Function(int flag, List<int> data) sendMessage,
  ) async {
    final body =
        reminderText.length > 140 ? '${reminderText.substring(0, 137)}\u2026' : reminderText;
    final card = WearableCard(
      id: 'reminder-${DateTime.now().millisecondsSinceEpoch}',
      title: 'Reminder saved \u2713',
      body: body,
      icon: '\u{F0010}',
      mode: AppMode.productivity,
      timestamp: DateTime.now(),
      cardType: WearableCardType.reminder,
    );
    await sendCard(card, sendMessage);
  }

  /// Sends a Hermes task result card to Frame.
  static Future<void> sendHermesResultCard(
    String task,
    String resultText,
    Future<void> Function(int flag, List<int> data) sendMessage,
  ) async {
    final body =
        resultText.length > 160 ? '${resultText.substring(0, 157)}\u2026' : resultText;
    final card = WearableCard(
      id: 'hermes-${DateTime.now().millisecondsSinceEpoch}',
      title: '\u25c8 $task',
      body: body,
      icon: '\u25c8',
      mode: AppMode.standard,
      timestamp: DateTime.now(),
      cardType: WearableCardType.info,
    );
    await sendCard(card, sendMessage);
  }

  /// Sends a daily brief card to Frame.
  static Future<void> sendDailyBriefCard(
    String briefText,
    Future<void> Function(int flag, List<int> data) sendMessage,
  ) async {
    final body =
        briefText.length > 160 ? '${briefText.substring(0, 157)}\u2026' : briefText;
    final card = WearableCard(
      id: 'brief-${DateTime.now().millisecondsSinceEpoch}',
      title: 'Daily Brief',
      body: body,
      icon: '\u{F0000}',
      mode: AppMode.productivity,
      timestamp: DateTime.now(),
      cardType: WearableCardType.dailyBrief,
    );
    await sendCard(card, sendMessage);
  }

  /// Sends a compact assistant-reply card to Frame.
  ///
  /// [reply] is truncated automatically by [WearableCard.toFrameString].
  static Future<void> sendAssistantReplyCard(
    String reply,
    AppMode mode,
    Future<void> Function(int flag, List<int> data) sendMessage,
  ) async {
    final body = reply.length > 160 ? '${reply.substring(0, 157)}\u2026' : reply;
    final card = WearableCard(
      id: 'reply-${DateTime.now().millisecondsSinceEpoch}',
      title: mode.displayName,
      body: body,
      icon: '\u25c8', // ◈
      mode: mode,
      timestamp: DateTime.now(),
      cardType: WearableCardType.info,
    );
    await sendCard(card, sendMessage);
  }

  static String _cardEmoji(WearableCard card) {
    switch (card.cardType) {
      case WearableCardType.reminder:
        return "\u{F0010}"; // bell-like glyph
      case WearableCardType.alert:
        return "\u{F0013}"; // alert glyph
      case WearableCardType.dailyBrief:
        return "\u{F0000}"; // calendar glyph
      default:
        return "\u{F0003}"; // default info glyph
    }
  }
}
