import 'dart:io';

import 'package:flutter/material.dart';
import 'package:noa/style.dart';
import 'package:noa/pages/noa.dart';
import 'package:noa/pages/vision.dart';
import 'package:noa/pages/productivity.dart';
import 'package:noa/pages/tune.dart';
import 'package:noa/pages/hack.dart';
import 'package:noa/util/switch_page.dart';

// Nav indices:
//   0 = CHAT   (NoaPage)
//   1 = VISION (VisionPage)
//   2 = TASKS  (ProductivityPage)
//   3 = TUNE   (TunePage / AriaSettingsPage)
//   4 = LOG    (HackPage)

Color getButtonColor(bool selected, bool darkMode) {
  return selected
      ? (darkMode ? colorWhite : colorDark)
      : (darkMode ? colorLight : colorLight);
}

/// Returns the page widget for the given nav [index].
Widget _pageForIndex(int index) {
  switch (index) {
    case 0:
      return const NoaPage();
    case 1:
      return const VisionPage();
    case 2:
      return const ProductivityPage();
    case 3:
      return const TunePage();
    case 4:
      return const HackPage();
    default:
      return const NoaPage();
  }
}

/// Returns the previous page index for left-swipe navigation.
int? _prevIndex(int current) => current > 0 ? current - 1 : null;

/// Returns the next page index for right-swipe navigation.
int? _nextIndex(int current) => current < 4 ? current + 1 : null;

Widget bottomNavBar(BuildContext context, int selected, bool darkMode) {
  const labels = ['CHAT', 'LENS', 'TASKS', 'TUNE', 'LOG'];
  // On mobile, leave 50 px below the nav pill for the home indicator.
  // On desktop (Windows/macOS/Linux) the safe-area padding is zero.
  final bottomPad = (Platform.isAndroid || Platform.isIOS) ? 50.0 : 8.0;

  return Container(
    height: 50,
    margin: EdgeInsets.only(left: 20, right: 20, bottom: bottomPad),
    decoration: BoxDecoration(
      color: darkMode ? colorLight : colorLight,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
    ),
    child: Row(
      children: List.generate(labels.length, (i) {
        final isSelected = selected == i;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              if (!isSelected) switchPage(context, _pageForIndex(i));
            },
            onHorizontalDragUpdate: (details) {
              if (details.delta.dx > 8) {
                final prev = _prevIndex(selected);
                if (prev != null) switchPage(context, _pageForIndex(prev));
              } else if (details.delta.dx < -8) {
                final next = _nextIndex(selected);
                if (next != null) switchPage(context, _pageForIndex(next));
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: getButtonColor(isSelected, darkMode),
                borderRadius: const BorderRadius.all(Radius.circular(20)),
              ),
              child: Center(
                child: Text(
                  labels[i],
                  style: darkMode
                      ? textStyleDarkWidget.copyWith(fontSize: 11)
                      : textStyleWhiteWidget.copyWith(fontSize: 11),
                ),
              ),
            ),
          ),
        );
      }),
    ),
  );
}