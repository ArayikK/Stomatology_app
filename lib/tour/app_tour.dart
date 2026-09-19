import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'spotlight_tour.dart';

/// The tour is split per screen: each screen explains itself the first time
/// the user reaches it, as long as they opted into the tour. Skipping any
/// part turns the rest off; "App tour" in the home menu turns it back on.
enum TourScreen { home, chart, tooth, appointments }

class AppTour {
  AppTour._();

  static const String _introSeenKey = 'stom_intro_seen';
  static const String _enabledKey = 'stom_tour_enabled';
  static String _doneKey(TourScreen screen) => 'stom_tour_done_${screen.name}';

  /// Whether the first-launch intro screen has already been shown. Reads
  /// that fail (no storage available) count as "seen" so the intro never
  /// traps anyone.
  static Future<bool> introSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_introSeenKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> completeIntro({required bool takeTour}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_introSeenKey, true);
      await prefs.setBool(_enabledKey, takeTour);
    } catch (_) {}
  }

  /// Re-enables every screen's tour, e.g. from the "App tour" menu item.
  static Future<void> restart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, true);
      for (final screen in TourScreen.values) {
        await prefs.remove(_doneKey(screen));
      }
    } catch (_) {}
  }

  static Future<bool> _shouldShow(TourScreen screen) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getBool(_enabledKey) ?? false) &&
          !(prefs.getBool(_doneKey(screen)) ?? false);
    } catch (_) {
      return false;
    }
  }

  static Future<void> _record(TourScreen screen, TourOutcome outcome) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (outcome == TourOutcome.finished) {
        await prefs.setBool(_doneKey(screen), true);
      } else {
        await prefs.setBool(_enabledKey, false);
      }
    } catch (_) {}
  }

  /// Shows [screen]'s part of the tour if the user hasn't seen it yet. Call
  /// once the screen's content has loaded, so every target is on screen.
  static Future<void> maybeShow(
    BuildContext context,
    TourScreen screen,
    List<TourStep> steps,
  ) async {
    if (!await _shouldShow(screen)) return;
    if (!context.mounted) return;
    await show(context, screen, steps);
  }

  /// Shows [screen]'s part of the tour unconditionally.
  static Future<void> show(
    BuildContext context,
    TourScreen screen,
    List<TourStep> steps,
  ) async {
    await _waitUntilSettled(context);
    if (!context.mounted) return;
    final outcome = await showSpotlightTour(context, steps);
    await _record(screen, outcome);
  }

  /// Waits for the screen's own entrance transition and a laid-out frame, so
  /// the spotlight isn't measured against a page that is still sliding in.
  static Future<void> _waitUntilSettled(BuildContext context) async {
    final animation = ModalRoute.of(context)?.animation;
    if (animation != null && animation.status != AnimationStatus.completed) {
      final done = Completer<void>();
      void listener(AnimationStatus status) {
        final settled =
            status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed;
        if (settled && !done.isCompleted) done.complete();
      }

      animation.addStatusListener(listener);
      await done.future;
      animation.removeStatusListener(listener);
    }
    await WidgetsBinding.instance.endOfFrame;
  }
}
