import 'package:flutter/widgets.dart';

/// Losing focus is not the same as becoming invisible (notably on web,
/// desktop and split-screen Android). Keep decorative motion while visible.
bool flowMotionIsVisible(AppLifecycleState? state) =>
    state == null ||
    state == AppLifecycleState.resumed ||
    state == AppLifecycleState.inactive;
