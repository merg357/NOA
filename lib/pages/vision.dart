import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noa/models/app_logic_model.dart' as app;
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/vision_model.dart';
import 'package:noa/models/wearable_card.dart';
import 'package:noa/services/vision_service.dart';
import 'package:noa/style.dart';
import 'package:noa/util/show_toast.dart';
import 'package:noa/widgets/bottom_nav_bar.dart';
import 'package:noa/widgets/top_title_bar.dart';

class VisionPage extends ConsumerWidget {
  const VisionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vision = ref.watch(visionProvider);

    return Scaffold(
      backgroundColor: colorDark,
      appBar: topTitleBar(context, 'VISION', false, true),
      body: SafeArea(
        child: Column(
          children: [
            // ── Preview ───────────────────────────────────────────────────
            Expanded(
              child: _PreviewArea(vision: vision),
            ),
            // ── Analysis results ──────────────────────────────────────────
            if (vision.lastCapture != null)
              _ResultsPanel(vision: vision),
            // ── Controls ──────────────────────────────────────────────────
            _ControlBar(vision: vision),
          ],
        ),
      ),
      bottomNavigationBar: bottomNavBar(context, 1, true),
    );
  }
}

// ── Preview Area ───────────────────────────────────────────────────────────

class _PreviewArea extends StatelessWidget {
  final VisionService vision;
  const _PreviewArea({required this.vision});

  @override
  Widget build(BuildContext context) {
    final capture = vision.lastCapture;
    if (vision.state == VisionState.capturing ||
        vision.state == VisionState.analyzing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorLight),
            SizedBox(height: 16),
            Text('Analyzing…', style: textStyleLight),
          ],
        ),
      );
    }

    if (vision.state == VisionState.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: colorRed, size: 48),
            const SizedBox(height: 12),
            Text(
              vision.errorMessage,
              style: textStyleLight,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (capture == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined, color: colorLight, size: 64),
            SizedBox(height: 16),
            Text(
              'Tap camera to capture\nor gallery to pick an image',
              style: textStyleLight,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Show last captured image
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(capture.imagePath),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image, color: colorLight, size: 48),
          ),
        ),
      ),
    );
  }
}

// ── Results Panel ──────────────────────────────────────────────────────────

class _ResultsPanel extends StatelessWidget {
  final VisionService vision;
  const _ResultsPanel({required this.vision});

  @override
  Widget build(BuildContext context) {
    final c = vision.lastCapture!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorLight.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorLight.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.hasQr) _ResultRow(icon: Icons.qr_code, label: 'QR', text: c.qrText),
          if (c.hasOcr) _ResultRow(icon: Icons.text_fields, label: 'OCR', text: c.ocrText),
          if (c.hasScene)
            _ResultRow(icon: Icons.auto_awesome, label: 'Scene', text: c.sceneSummary),
          if (!c.hasQr && !c.hasOcr && !c.hasScene)
            _ResultRow(icon: Icons.info_outline, label: 'Info', text: c.bestText),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  const _ResultRow({required this.icon, required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colorLight, size: 16),
          const SizedBox(width: 6),
          Text('$label: ', style: textStyleLight.copyWith(fontWeight: FontWeight.w700)),
          Expanded(child: Text(text, style: textStyleWhite)),
        ],
      ),
    );
  }
}

// ── Control Bar ────────────────────────────────────────────────────────────

class _ControlBar extends ConsumerWidget {
  final VisionService vision;
  const _ControlBar({required this.vision});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = vision.state == VisionState.capturing ||
        vision.state == VisionState.analyzing;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Camera capture
          _IconButton(
            icon: Icons.camera_alt,
            label: 'CAMERA',
            enabled: !busy,
            onTap: () => ref.read(visionProvider).captureAndAnalyze(),
          ),
          // Gallery pick
          _IconButton(
            icon: Icons.photo_library,
            label: 'GALLERY',
            enabled: !busy,
            onTap: () => ref.read(visionProvider).pickAndAnalyze(),
          ),
          // Send to Frame
          _IconButton(
            icon: Icons.send,
            label: 'SEND',
            enabled: !busy && vision.lastCapture != null,
            onTap: () => _sendToFrame(context, ref),
          ),
          // Reset
          _IconButton(
            icon: Icons.refresh,
            label: 'RESET',
            enabled: !busy,
            onTap: () => ref.read(visionProvider).reset(),
          ),
        ],
      ),
    );
  }

  void _sendToFrame(BuildContext context, WidgetRef ref) {
    final capture = vision.lastCapture;
    if (capture == null) return;

    final card = WearableCard(
      id: 'vision-${capture.capturedAt.millisecondsSinceEpoch}',
      title: 'Vision',
      body: capture.bestText,
      icon: '◎',
      mode: AppMode.vision,
      timestamp: capture.capturedAt,
      cardType: WearableCardType.visionSummary,
    );

    ref.read(app.model).sendWearableCardToFrame(card).then((_) {
      if (context.mounted) showToast('Sent to Frame', context);
    }).catchError((e) {
      if (context.mounted) showToast('Send failed: $e', context);
    });
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const _IconButton({
    required this.icon,
    required this.label,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? colorLight : colorLight.withOpacity(0.3);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(label, style: textStyleLight.copyWith(fontSize: 10, color: color)),
        ],
      ),
    );
  }
}
