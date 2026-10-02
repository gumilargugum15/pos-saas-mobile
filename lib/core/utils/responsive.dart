import 'package:flutter/widgets.dart';

/// Material 3 window size classes.
enum WindowSize {
  /// Phones in portrait (< 600dp): single pane.
  compact,

  /// Large phones / small tablets (600–839dp).
  medium,

  /// Tablets (>= 840dp): two-pane POS (catalog | cart).
  expanded;

  static WindowSize of(BuildContext context) => fromWidth(MediaQuery.sizeOf(context).width);

  static WindowSize fromWidth(double width) {
    if (width >= 840) return WindowSize.expanded;
    if (width >= 600) return WindowSize.medium;
    return WindowSize.compact;
  }

  bool get isCompact => this == WindowSize.compact;
  bool get isExpanded => this == WindowSize.expanded;
}
