// test/scoring_test.dart
// lib/core/scoring.dart の単体テスト。移植元 test/scoring.test.mjs のケースを移植したもの。
// 移植元の「questionNos が文字列でも正しく採点される」ケースは、
// Dart では questionNos が List<int> で型固定されるため対象外。

import 'package:flutter_test/flutter_test.dart';
import 'package:care_manager_exam_app/core/models/exam.dart';
import 'package:care_manager_exam_app/core/models/question.dart';
import 'package:care_manager_exam_app/core/models/section.dart';
import 'package:care_manager_exam_app/core/scoring.dart';

// 分野境界（care: 1-3, health_welfare: 4-6）をまたぐ小さなフィクスチャ。
// 実データ（exam-28.json）は care: 1-25, health_welfare: 26-60 だが、
// 境界判定ロジックのテストにこの規模の差は影響しない。
Exam _buildExam() {
  return Exam(
    id: 'fixture',
    title: 'フィクスチャ試験',
    source: '',
    credit: '',
    fetchedAt: '',
    sections: const [
      Section(id: 'care', name: '介護支援分野', from: 1, to: 3),
      Section(id: 'health_welfare', name: '保健医療福祉サービス分野', from: 4, to: 6),
    ],
    questions: const [
      Question(
        no: 1,
        sectionId: 'care',
        text: 'q1',
        selectCount: 2,
        choices: [],
        answers: [1, 2],
      ),
      Question(
        no: 2,
        sectionId: 'care',
        text: 'q2',
        selectCount: 1,
        choices: [],
        answers: [3],
      ),
      Question(
        no: 3,
        sectionId: 'care',
        text: 'q3',
        selectCount: 2,
        choices: [],
        answers: [1, 3],
      ),
      Question(
        no: 4,
        sectionId: 'health_welfare',
        text: 'q4',
        selectCount: 3,
        choices: [],
        answers: [1, 2, 3],
      ),
      Question(
        no: 5,
        sectionId: 'health_welfare',
        text: 'q5',
        selectCount: 1,
        choices: [],
        answers: [5],
      ),
      Question(
        no: 6,
        sectionId: 'health_welfare',
        text: 'q6',
        selectCount: 2,
        choices: [],
        answers: [2, 4],
      ),
    ],
  );
}

void main() {
  final exam = _buildExam();

  group('isCorrect', () {
    test('完全一致（同じ集合・同じ順序）は正解', () {
      expect(isCorrect([1, 2], [1, 2]), true);
    });

    test('順序が違うだけで中身が同じなら正解', () {
      expect(isCorrect([4, 3], [3, 4]), true);
    });

    test('選択数が足りない（部分一致）は不正解', () {
      expect(isCorrect([3], [3, 4]), false);
    });

    test('余分に選んでいる（過剰選択）は不正解', () {
      expect(isCorrect([1, 2, 3], [1, 2]), false);
    });

    test('未回答（空配列）は常に不正解', () {
      expect(isCorrect([], [1, 2]), false);
    });

    test('正解が空配列でも未回答（空配列）は不正解', () {
      expect(isCorrect([], []), false);
    });

    test('重複選択は正規化されて正しく判定される', () {
      expect(isCorrect([1, 1, 2], [1, 2]), true);
      expect(isCorrect([1, 1], [1, 2]), false);
    });

    test('完全に異なる選択は不正解', () {
      expect(isCorrect([4, 5], [1, 2]), false);
    });
  });

  group('sectionIdOf', () {
    test('from/to の範囲から分野を判定する', () {
      expect(sectionIdOf(exam, 1), 'care');
      expect(sectionIdOf(exam, 3), 'care');
      expect(sectionIdOf(exam, 4), 'health_welfare');
      expect(sectionIdOf(exam, 6), 'health_welfare');
    });

    test('どの分野にも属さない問番号は null', () {
      expect(sectionIdOf(exam, 99), null);
      expect(sectionIdOf(exam, 0), null);
    });
  });

  group('gradeSession', () {
    test('分野境界（問3/4）をまたいで total/max/bySection が正しく仕分けられる', () {
      final answers = {
        1: [2, 1], // 順序違いだが正解
        2: [3, 3], // 重複選択だが正解
        3: [1], // 部分一致（不足）で不正解
        4: [1, 2, 3, 4], // 過剰選択で不正解
        5: <int>[], // 未回答で不正解
        6: [4, 2], // 順序違いだが正解
      };

      final result = gradeSession(
        exam,
        questionNos: [1, 2, 3, 4, 5, 6],
        answers: answers,
      );
      final score = result.score;
      final results = result.results;

      expect(score.total, 3);
      expect(score.max, 6);
      expect(score.bySection['care']!.correct, 2);
      expect(score.bySection['care']!.count, 3);
      expect(score.bySection['health_welfare']!.correct, 1);
      expect(score.bySection['health_welfare']!.count, 3);

      expect(results.length, 6);
      expect(results.map((r) => r.correct).toList(), [
        true,
        true,
        false,
        false,
        false,
        true,
      ]);
      expect(results.map((r) => r.answered).toList(), [
        true,
        true,
        true,
        true,
        false,
        true,
      ]);
      expect(results.map((r) => r.sectionId).toList(), [
        'care',
        'care',
        'care',
        'health_welfare',
        'health_welfare',
        'health_welfare',
      ]);
      // 正解配列（question.answers）が results に転記されている
      expect(results[0].answers, [1, 2]);
      expect(results[0].selected, [2, 1]);
    });

    test('復習モード（questionNos が一部だけ）では max と bySection の count が絞られる', () {
      final answers = {
        1: [1, 2], // care, 正解
        4: [1, 2, 3], // health_welfare, 正解
      };

      final result = gradeSession(exam, questionNos: [1, 4], answers: answers);
      final score = result.score;
      final results = result.results;

      expect(score.max, 2);
      expect(score.total, 2);
      expect(score.bySection['care']!.correct, 1);
      expect(score.bySection['care']!.count, 1);
      expect(score.bySection['health_welfare']!.correct, 1);
      expect(score.bySection['health_welfare']!.count, 1);
      expect(results.length, 2);
    });

    test('answers にキーが無い問は未回答として扱われる', () {
      final result = gradeSession(exam, questionNos: [5], answers: const {});
      final results = result.results;

      expect(results[0].answered, false);
      expect(results[0].correct, false);
      expect(results[0].selected, <int>[]);
    });

    test('復習モードで片方の分野しか出題されない場合、出題0件の分野は [0,0] で保持される', () {
      // 実運用の復習モードでは不正解の問が片方の分野に偏ることが普通にある。
      // bySection はその分野のキー自体は落とさず count=0 を保持する設計
      // （後続の画面タスクが null チェックなしで formatRate(c, n) に渡せるようにするため）。
      final result = gradeSession(
        exam,
        questionNos: [1],
        answers: {
          1: [1, 2],
        }, // care のみ、正解
      );
      final score = result.score;

      expect(score.bySection['care']!.correct, 1);
      expect(score.bySection['care']!.count, 1);
      expect(score.bySection['health_welfare']!.correct, 0);
      expect(score.bySection['health_welfare']!.count, 0);
      expect(
        formatRate(
          score.bySection['health_welfare']!.correct,
          score.bySection['health_welfare']!.count,
        ),
        '-',
      );
    });
  });

  group('formatRate', () {
    test('正答率を小数第1位までの %表記にする', () {
      expect(formatRate(18, 25), '72.0%');
    });

    test('割り切れない場合も小数第1位に丸められる', () {
      expect(formatRate(1, 3), '33.3%');
    });

    test('count が 0 のときは "-" を返す', () {
      expect(formatRate(0, 0), '-');
      expect(formatRate(5, 0), '-');
    });

    test('満点は 100.0% になる', () {
      expect(formatRate(6, 6), '100.0%');
    });
  });
}
