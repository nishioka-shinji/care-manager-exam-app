import 'package:care_manager_exam_app/core/models/current_session.dart';
import 'package:care_manager_exam_app/core/models/question.dart';
import 'package:care_manager_exam_app/core/models/session.dart';
import 'package:care_manager_exam_app/data/exam_repository.dart';
import 'package:care_manager_exam_app/data/storage_repository.dart';
import 'package:care_manager_exam_app/features/quiz/quiz_controller.dart';
import 'package:care_manager_exam_app/features/result/result_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [question] と同じ選択数を保ったまま、不正解になる選択肢を作る。
/// 正誤判定そのものは本番の QuizController / ResultController に委ねる。
List<int> _incorrectSelection(Question question) {
  final correct = question.answers.toSet();
  final choiceNos = question.choices.map((choice) => choice.no).toList();
  final selected = choiceNos.take(question.selectCount).toList();

  if (selected.toSet().difference(correct).isNotEmpty ||
      correct.difference(selected.toSet()).isNotEmpty) {
    return selected;
  }

  final replacement = choiceNos.firstWhere(
    (choiceNo) => !correct.contains(choiceNo),
  );
  selected[selected.length - 1] = replacement;
  return selected;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('実アセット全16試験を full・drill・結果再読込・年度別統計まで一気通貫で処理する', () async {
    final examRepository = ExamRepository();
    final storageRepository = StorageRepository();
    await storageRepository.init();

    final index = await examRepository.loadIndex();
    final examIds = index.map((meta) => meta.id).toList();

    expect(index, hasLength(16));
    expect(examIds.toSet(), hasLength(16));
    expect(examIds, containsAll(<String>['2201', '2202']));

    final firstQuestionNoByExam = <String, int>{};
    final drillCorrectByExam = <String, bool>{};
    final fullSessionIds = <String, String>{};
    final drillSessionIds = <String, String>{};

    for (final meta in index) {
      final exam = await examRepository.loadExam(meta.id);
      final questionNos = exam.questions
          .map((question) => question.no)
          .toList();
      final fullAnswers = <int, List<int>>{
        for (final question in exam.questions)
          question.no: List<int>.of(question.answers),
      };

      expect(exam.id, meta.id, reason: meta.file);
      expect(exam.title, meta.title, reason: meta.id);
      expect(exam.questions, hasLength(60), reason: meta.id);
      expect(
        questionNos,
        List<int>.generate(60, (index) => index + 1),
        reason: meta.id,
      );

      // 全問正解の本番通し current を永続化してから、本番 QuizController で
      // 読み込み・採点・履歴保存・年度別 stats 更新まで通す。
      await storageRepository.saveCurrent(
        CurrentSession(
          examId: exam.id,
          mode: QuizMode.full,
          startedAt: '2026-09-23T00:00:00.000Z',
          questionNos: questionNos,
          cursor: 0,
          answers: fullAnswers,
        ),
      );
      final fullQuiz = QuizController(
        examRepository: examRepository,
        storageRepository: storageRepository,
      );
      await fullQuiz.load();
      expect(fullQuiz.loadError, isFalse, reason: exam.id);
      expect(fullQuiz.exam?.id, exam.id, reason: exam.id);
      expect(fullQuiz.unansweredCount, 0, reason: exam.id);

      final fullSessionId = await fullQuiz.gradeAndFinish();
      expect(fullSessionId, isNotNull, reason: exam.id);
      fullSessionIds[exam.id] = fullSessionId!;
      fullQuiz.dispose();
      expect(await storageRepository.loadCurrent(), isNull, reason: exam.id);

      final savedFull = storageRepository.getSessionById(fullSessionId);
      expect(savedFull?.examId, exam.id, reason: exam.id);
      expect(savedFull?.mode, QuizMode.full, reason: exam.id);
      expect(savedFull?.answers, fullAnswers, reason: exam.id);
      expect(savedFull?.score.total, 60, reason: exam.id);
      expect(savedFull?.score.max, 60, reason: exam.id);

      // ResultController も新しい repository インスタンスで永続化済み session
      // と実アセットを読み直す。年度を取り違えると id/title/設問/採点がずれる。
      final fullResult = ResultController(
        examRepository: ExamRepository(),
        storageRepository: StorageRepository(),
        sessionId: fullSessionId,
      );
      await fullResult.load();
      expect(fullResult.notFound, isFalse, reason: exam.id);
      expect(fullResult.loadError, isFalse, reason: exam.id);
      expect(fullResult.exam?.id, exam.id, reason: exam.id);
      expect(fullResult.exam?.title, exam.title, reason: exam.id);
      expect(fullResult.questionNos, questionNos, reason: exam.id);
      expect(fullResult.gradeResult?.score.total, 60, reason: exam.id);
      expect(fullResult.gradeResult?.score.max, 60, reason: exam.id);
      expect(
        fullResult.gradeResult?.results.first.answers,
        exam.questions.first.answers,
        reason: exam.id,
      );
      fullResult.dispose();

      // 同じ年度の先頭問を一問一答で答え合わせして終了する。2202 だけを
      // 正解、2201 を含む他年度を不正解にし、同じ問番号の年度間混線を可視化する。
      final firstQuestion = exam.questions.first;
      final drillCorrect = exam.id == '2202';
      final drillSelection = drillCorrect
          ? List<int>.of(firstQuestion.answers)
          : _incorrectSelection(firstQuestion);
      firstQuestionNoByExam[exam.id] = firstQuestion.no;
      drillCorrectByExam[exam.id] = drillCorrect;

      await storageRepository.saveCurrent(
        CurrentSession(
          examId: exam.id,
          mode: QuizMode.drill,
          startedAt: '2026-09-23T01:00:00.000Z',
          questionNos: <int>[firstQuestion.no],
          cursor: 0,
          answers: const <int, List<int>>{},
        ),
      );
      final drillQuiz = QuizController(
        examRepository: examRepository,
        storageRepository: storageRepository,
      );
      await drillQuiz.load();
      expect(drillQuiz.exam?.id, exam.id, reason: exam.id);
      for (final choiceNo in drillSelection) {
        expect(
          drillQuiz.toggleChoice(
            firstQuestion.no,
            choiceNo,
            firstQuestion.selectCount,
          ),
          isTrue,
          reason: exam.id,
        );
      }
      expect(
        await drillQuiz.revealCurrent(firstQuestion.selectCount),
        isTrue,
        reason: exam.id,
      );
      expect(drillQuiz.isCurrentRevealed, isTrue, reason: exam.id);

      final revealedCurrent = await storageRepository.loadCurrent();
      expect(revealedCurrent?.examId, exam.id, reason: exam.id);
      expect(revealedCurrent?.revealed, <int>[
        firstQuestion.no,
      ], reason: exam.id);
      expect(
        revealedCurrent?.answers[firstQuestion.no],
        drillSelection,
        reason: exam.id,
      );

      final drillFinish = await drillQuiz.finishDrill();
      expect(drillFinish.noRevealed, isFalse, reason: exam.id);
      expect(drillFinish.id, isNotNull, reason: exam.id);
      drillSessionIds[exam.id] = drillFinish.id!;
      drillQuiz.dispose();
      expect(await storageRepository.loadCurrent(), isNull, reason: exam.id);

      final drillResult = ResultController(
        examRepository: ExamRepository(),
        storageRepository: StorageRepository(),
        sessionId: drillFinish.id,
      );
      await drillResult.load();
      expect(drillResult.exam?.id, exam.id, reason: exam.id);
      expect(drillResult.exam?.title, exam.title, reason: exam.id);
      expect(drillResult.session?.mode, QuizMode.drill, reason: exam.id);
      expect(drillResult.questionNos, <int>[firstQuestion.no], reason: exam.id);
      expect(
        drillResult.gradeResult?.score.total,
        drillCorrect ? 1 : 0,
        reason: exam.id,
      );
      expect(drillResult.gradeResult?.score.max, 1, reason: exam.id);
      expect(
        drillResult.gradeResult?.results.single.answers,
        firstQuestion.answers,
        reason: exam.id,
      );
      drillResult.dispose();
    }

    // 新しい StorageRepository から履歴を読み直し、全年度の full/drill が
    // それぞれ独立した session として残っていることを確認する。
    final reloadedStorage = StorageRepository();
    await reloadedStorage.init();
    final sessions = reloadedStorage.loadSessions();
    expect(sessions, hasLength(32));
    expect(sessions.map((session) => session.id).toSet(), hasLength(32));
    expect(fullSessionIds.keys.toSet(), examIds.toSet());
    expect(drillSessionIds.keys.toSet(), examIds.toSet());
    for (final examId in examIds) {
      final examSessions = sessions
          .where((session) => session.examId == examId)
          .toList();
      expect(examSessions, hasLength(2), reason: examId);
      expect(examSessions.map((session) => session.mode).toSet(), <QuizMode>{
        QuizMode.full,
        QuizMode.drill,
      }, reason: examId);
      expect(
        reloadedStorage.getSessionById(fullSessionIds[examId]!)?.examId,
        examId,
      );
      expect(
        reloadedStorage.getSessionById(drillSessionIds[examId]!)?.examId,
        examId,
      );

      final stats = reloadedStorage.loadStats(examId);
      final firstNo = firstQuestionNoByExam[examId]!;
      final firstKey = firstNo.toString();
      final drillCorrect = drillCorrectByExam[examId]!;
      expect(stats, hasLength(60), reason: examId);
      expect(stats[firstKey]?.attempts, 2, reason: examId);
      expect(stats[firstKey]?.correct, drillCorrect ? 2 : 1, reason: examId);
      expect(stats[firstKey]?.lastCorrect, drillCorrect, reason: examId);
      expect(stats[firstKey]?.streak, drillCorrect ? 2 : 0, reason: examId);

      for (final entry in stats.entries) {
        if (entry.key == firstKey) continue;
        expect(entry.value.attempts, 1, reason: '$examId:${entry.key}');
        expect(entry.value.correct, 1, reason: '$examId:${entry.key}');
        expect(entry.value.lastCorrect, isTrue, reason: '$examId:${entry.key}');
        expect(entry.value.streak, 1, reason: '$examId:${entry.key}');
      }

      final summary = reloadedStorage.summarizeStats(examId: examId);
      expect(summary.tracked, 60, reason: examId);
      expect(summary.everWrong, drillCorrect ? 0 : 1, reason: examId);
      expect(summary.streak2plus, drillCorrect ? 1 : 0, reason: examId);
    }

    // 2201 と 2202 は同じ先頭問番号でも異なる履歴を持つ。stats の examId
    // スコープを外す／固定年度に書く変異なら、この対照で必ず失敗する。
    final no2201 = firstQuestionNoByExam['2201']!;
    final no2202 = firstQuestionNoByExam['2202']!;
    final stat2201 = reloadedStorage.loadStats('2201')[no2201.toString()]!;
    final stat2202 = reloadedStorage.loadStats('2202')[no2202.toString()]!;
    expect(stat2201.lastCorrect, isFalse);
    expect(stat2201.correct, 1);
    expect(stat2202.lastCorrect, isTrue);
    expect(stat2202.correct, 2);

    final allStats = reloadedStorage.summarizeStats();
    expect(allStats.tracked, 16 * 60);
    expect(allStats.everWrong, 15);
    expect(allStats.streak2plus, 1);
  });
}
