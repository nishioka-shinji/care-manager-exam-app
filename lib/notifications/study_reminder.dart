import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/study_reminder_schedule.dart';
import '../data/storage_repository.dart';

/// 学習リマインドの OS 予約を扱う抽象。テストではフェイクに差し替える。
abstract interface class ReminderScheduler {
  Future<void> init();

  /// 既存の予約を取り消し、[firstAt] から 24h ごとに繰り返す予約を入れる。
  Future<void> reschedule(DateTime firstAt);
}

/// 通知をサポートしないプラットフォーム用。起動を妨げないため何もしない。
class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();

  @override
  Future<void> init() async {}

  @override
  Future<void> reschedule(DateTime firstAt) async {}
}

/// flutter_local_notifications による Android の予約通知。
class LocalNotificationReminderScheduler implements ReminderScheduler {
  LocalNotificationReminderScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _notificationId = 1;
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'study_reminder',
      '学習リマインド',
      channelDescription: '前回の学習から時間が空いたときのお知らせ',
    ),
  );

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  @override
  Future<void> reschedule(DateTime firstAt) async {
    await _plugin.cancel(id: _notificationId);
    // UTC で時刻一致の日次繰り返しにすると、夏時間に左右されず 24h 間隔になる。
    await _plugin.zonedSchedule(
      id: _notificationId,
      scheduledDate: tz.TZDateTime.from(firstAt, tz.UTC),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: '今日の演習はまだです',
      body: '前回の学習から24時間が経ちました。1問だけでも解いてみましょう',
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}

/// 最終学習時刻の記録と、それに基づく通知の再予約をまとめる。
/// 呼び出しは直列化し、取り消しと予約が交互に崩れないようにする。
class StudyReminderService {
  StudyReminderService({
    required this.storageRepository,
    required this.scheduler,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final StorageRepository storageRepository;
  final ReminderScheduler scheduler;
  final DateTime Function() _clock;
  Future<void> _queue = Future.value();

  /// 起動時に呼ぶ。初回起動時刻を確定させてから予約し直す。
  Future<void> onAppLaunch() => _enqueue(() async {
    await scheduler.init();
    await _ensureStorage();
    await storageRepository.ensureFirstLaunchAt(_clock());
    await _reschedule();
  });

  /// 解答のたびに呼ぶ。最終学習時刻を保存して予約し直す。
  Future<void> recordStudy() => _enqueue(() async {
    await _ensureStorage();
    await storageRepository.saveLastStudyAt(_clock());
    await _reschedule();
  });

  Future<void> _ensureStorage() async {
    if (!storageRepository.isAvailable()) await storageRepository.init();
  }

  Future<void> _reschedule() async {
    final now = _clock();
    final firstLaunchAt = await storageRepository.ensureFirstLaunchAt(now);
    await scheduler.reschedule(
      nextStudyReminderAt(
        lastStudyAt: storageRepository.loadLastStudyAt(),
        firstLaunchAt: firstLaunchAt,
        now: now,
      ),
    );
  }

  // 通知の失敗で演習や起動を止めないため、例外はここで握りつぶす。
  Future<void> _enqueue(Future<void> Function() task) {
    final next = _queue.then((_) => task()).catchError((Object e) {
      debugPrint('StudyReminderService: $e');
    });
    _queue = next;
    return next;
  }
}

/// アプリ全体で共有するリマインドサービス。main で設定し、テストでは null のまま。
StudyReminderService? appStudyReminder;
