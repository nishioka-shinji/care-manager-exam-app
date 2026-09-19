import 'package:flutter_test/flutter_test.dart';
import 'package:care_manager_exam_app/core/models/current_session.dart';
import 'package:care_manager_exam_app/core/models/session.dart';
import 'package:care_manager_exam_app/data/exam_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExamRepository + Exam の実アセット検証', () {
    test('exam.id は文字列 "28"', () async {
      final exam = await ExamRepository().loadExam('28');
      expect(exam.id, '28');
    });

    test('問題が60件ちょうど', () async {
      final exam = await ExamRepository().loadExam('28');
      expect(exam.questions.length, 60);
    });

    test('全問 choices が5件', () async {
      final exam = await ExamRepository().loadExam('28');
      for (final question in exam.questions) {
        expect(
          question.choices.length,
          5,
          reason: 'question no=${question.no}',
        );
      }
    });

    test('全問 answers.length == selectCount', () async {
      final exam = await ExamRepository().loadExam('28');
      for (final question in exam.questions) {
        expect(
          question.answers.length,
          question.selectCount,
          reason: 'question no=${question.no}',
        );
      }
    });

    test('全問の sectionId が sections の from/to 範囲と整合', () async {
      final exam = await ExamRepository().loadExam('28');
      final sectionById = {
        for (final section in exam.sections) section.id: section,
      };
      for (final question in exam.questions) {
        final section = sectionById[question.sectionId];
        expect(section, isNotNull, reason: 'question no=${question.no}');
        expect(
          question.no >= section!.from && question.no <= section.to,
          isTrue,
          reason: 'question no=${question.no} section=${section.id}',
        );
      }
    });
  });

  group('モデルの toJson/fromJson 往復', () {
    test('Session: answers の int キーが保たれる', () {
      final session = Session(
        id: 's1',
        examId: '28',
        mode: QuizMode.full,
        startedAt: '2026-09-19T00:00:00.000Z',
        finishedAt: '2026-09-19T00:30:00.000Z',
        answers: {
          1: [3, 4],
          2: [],
        },
        score: const Score(
          total: 1,
          max: 2,
          bySection: {'care': SectionScore(correct: 1, count: 2)},
        ),
      );

      final restored = Session.fromJson(session.toJson());

      expect(restored.id, session.id);
      expect(restored.examId, session.examId);
      expect(restored.mode, session.mode);
      expect(restored.startedAt, session.startedAt);
      expect(restored.finishedAt, session.finishedAt);
      expect(restored.answers, session.answers);
      expect(restored.answers.keys, isA<Iterable<int>>());
      expect(restored.score.total, session.score.total);
      expect(restored.score.max, session.score.max);
      expect(restored.score.bySection['care']!.correct, 1);
      expect(restored.score.bySection['care']!.count, 2);
    });

    test('CurrentSession: answers の int キーが保たれる', () {
      final current = CurrentSession(
        examId: '28',
        mode: QuizMode.review,
        startedAt: '2026-09-19T00:00:00.000Z',
        questionNos: [1, 2, 3],
        cursor: 1,
        answers: {
          1: [3, 4],
        },
      );

      final restored = CurrentSession.fromJson(current.toJson());

      expect(restored.examId, current.examId);
      expect(restored.mode, current.mode);
      expect(restored.startedAt, current.startedAt);
      expect(restored.questionNos, current.questionNos);
      expect(restored.cursor, current.cursor);
      expect(restored.answers, current.answers);
    });
  });
}
