import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/storage_repository.dart';
import 'notifications/study_reminder.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final reminder = StudyReminderService(
    storageRepository: StorageRepository(),
    // 通知対象は Android のみ。他 OS では初期化失敗で起動を止めないよう何もしない。
    scheduler: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? LocalNotificationReminderScheduler()
        : const NoopReminderScheduler(),
  );
  appStudyReminder = reminder;
  unawaited(reminder.onAppLaunch());
  runApp(App(appState: AppState()));
}
