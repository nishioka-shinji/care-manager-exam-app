import 'package:care_manager_exam_app/core/models/current_session.dart';
import 'package:care_manager_exam_app/core/models/session.dart';
import 'package:care_manager_exam_app/core/study_reminder_schedule.dart';
import 'package:care_manager_exam_app/data/exam_repository.dart';
import 'package:care_manager_exam_app/data/storage_repository.dart';
import 'package:care_manager_exam_app/features/quiz/quiz_controller.dart';
import 'package:care_manager_exam_app/notifications/study_reminder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeScheduler implements ReminderScheduler {
  int initCount = 0;
  final List<DateTime> scheduled = [];

  @override
  Future<void> init() async => initCount++;

  @override
  Future<void> reschedule(DateTime firstAt) async => scheduled.add(firstAt);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nextStudyReminderAt', () {
    final firstLaunch = DateTime(2026, 9, 1, 8);

    test('学習履歴があれば最終学習時刻 + 24h', () {
      expect(
        nextStudyReminderAt(
          lastStudyAt: DateTime(2026, 9, 10, 21, 30),
          firstLaunchAt: firstLaunch,
          now: DateTime(2026, 9, 10, 22),
        ),
        DateTime(2026, 9, 11, 21, 30),
      );
    });

    test('学習履歴がなければ初回起動時刻 + 24h', () {
      expect(
        nextStudyReminderAt(
          lastStudyAt: null,
          firstLaunchAt: firstLaunch,
          now: DateTime(2026, 9, 1, 9),
        ),
        DateTime(2026, 9, 2, 8),
      );
    });

    test('基準 + 24h が過去なら次に来る「基準 + 24h*n」', () {
      final last = DateTime(2026, 9, 10, 21, 30);
      expect(
        nextStudyReminderAt(
          lastStudyAt: last,
          firstLaunchAt: firstLaunch,
          now: DateTime(2026, 9, 13, 12),
        ),
        DateTime(2026, 9, 13, 21, 30),
      );
      // ちょうど通知時刻なら、その回は出たものとして次の回を返す。
      expect(
        nextStudyReminderAt(
          lastStudyAt: last,
          firstLaunchAt: firstLaunch,
          now: DateTime(2026, 9, 11, 21, 30),
        ),
        DateTime(2026, 9, 12, 21, 30),
      );
    });
  });

  group('StudyReminderService', () {
    test('起動時に初回起動時刻を一度だけ保存し、+24h で予約する', () async {
      SharedPreferences.setMockInitialValues({});
      final scheduler = _FakeScheduler();
      var now = DateTime(2026, 9, 1, 8);
      final service = StudyReminderService(
        storageRepository: StorageRepository(),
        scheduler: scheduler,
        clock: () => now,
      );

      await service.onAppLaunch();
      now = DateTime(2026, 9, 1, 10);
      await service.onAppLaunch();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(StorageKeys.firstLaunchAt),
        DateTime(2026, 9, 1, 8).toIso8601String(),
      );
      expect(scheduler.initCount, 2);
      expect(scheduler.scheduled, [
        DateTime(2026, 9, 2, 8),
        DateTime(2026, 9, 2, 8),
      ]);
    });
  });

  testWidgets('選択肢の解答で最終学習時刻が保存され再予約される', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final scheduler = _FakeScheduler();
    final studyAt = DateTime(2026, 9, 20, 7, 15);
    final storage = StorageRepository();
    final controller = QuizController(
      examRepository: ExamRepository(),
      storageRepository: storage,
      studyReminder: StudyReminderService(
        storageRepository: StorageRepository(),
        scheduler: scheduler,
        clock: () => studyAt,
      ),
    );
    await tester.runAsync(() async {
      await storage.init();
      await storage.saveCurrent(
        CurrentSession(
          examId: '28',
          mode: QuizMode.full,
          startedAt: '2026-09-19T00:00:00.000Z',
          questionNos: const [1],
          cursor: 0,
          answers: const {},
        ),
      );
      await controller.load();
    });

    var notified = 0;
    controller.addListener(() => notified++);
    expect(controller.toggleChoice(1, 1, 1), isTrue);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StorageKeys.lastStudyAt), studyAt.toIso8601String());
    expect(scheduler.scheduled, [DateTime(2026, 9, 21, 7, 15)]);
    // 記録・再予約で画面の作り直しを誘発しない（不変条件2）。
    expect(notified, 0);
    controller.dispose();
  });
}
