// 採点ロジック。Flutter / shared_preferences / UI に一切触れない純粋 Dart のみで構成する。
// import してよいのは core/models のみ。移植元 public/js/scoring.js の移植。
// 採点方式は「完全一致のみ正解（部分点なし）」。

import 'models/exam.dart';
import 'models/session.dart';

/// 選択結果が正解かどうかを判定する。
/// 順不同・重複を無視した集合として比較する完全一致方式。部分点はない。
/// 空リスト（未回答）は常に不正解として扱う。
bool isCorrect(List<int> selected, List<int> answers) {
  if (selected.isEmpty) {
    return false;
  }
  final selectedSet = selected.toSet();
  final answerSet = answers.toSet();
  if (selectedSet.length != answerSet.length) {
    return false;
  }
  return selectedSet.every(answerSet.contains);
}

/// 問番号がどの分野（section）に属するかを exam.sections の from/to から判定する。
/// 該当する section が無ければ null。
String? sectionIdOf(Exam exam, int no) {
  for (final section in exam.sections) {
    if (no >= section.from && no <= section.to) {
      return section.id;
    }
  }
  return null;
}

/// 設問1問分の採点結果。
class QuestionResult {
  const QuestionResult({
    required this.no,
    required this.sectionId,
    required this.selected,
    required this.answers,
    required this.correct,
    required this.answered,
  });

  final int no;
  final String? sectionId;
  final List<int> selected;
  final List<int> answers;
  final bool correct;
  final bool answered;
}

/// セッション（1回の受験）の採点結果。[score] は Session に保存する形、
/// [results] は結果画面が問ごとの内訳を描くための一覧。
class GradeResult {
  const GradeResult({required this.score, required this.results});

  final Score score;
  final List<QuestionResult> results;
}

/// セッション（1回の受験）を採点する。
/// [questionNos] は出題した問番号（本番通しなら 1..60、復習ならその一部）。
/// [answers] は問番号 -> 選んだ選択肢番号のリスト（未回答は空リスト or キー無し）。
GradeResult gradeSession(
  Exam exam, {
  required List<int> questionNos,
  required Map<int, List<int>> answers,
}) {
  final questionByNo = {for (final q in exam.questions) q.no: q};

  final results = questionNos.map((no) {
    final question = questionByNo[no];
    final sectionId = sectionIdOf(exam, no);
    final selected = answers[no] ?? const <int>[];
    final correctAnswers = question?.answers ?? const <int>[];
    final correct = isCorrect(selected, correctAnswers);

    return QuestionResult(
      no: no,
      sectionId: sectionId,
      selected: selected,
      answers: correctAnswers,
      correct: correct,
      answered: selected.isNotEmpty,
    );
  }).toList();

  final total = results.where((r) => r.correct).length;
  final max = results.length;

  // exam.sections を全件ループし、出題0件の分野もキーを残す（復習モードで
  // 片方の分野しか出題されなくても、もう片方のキーが消えないようにするため）。
  final bySection = <String, SectionScore>{};
  for (final section in exam.sections) {
    final inSection = results.where((r) => r.sectionId == section.id);
    final sectionCorrect = inSection.where((r) => r.correct).length;
    bySection[section.id] = SectionScore(
      correct: sectionCorrect,
      count: inSection.length,
    );
  }

  return GradeResult(
    score: Score(total: total, max: max, bySection: bySection),
    results: results,
  );
}

/// 正答率を表示用の文字列に整形する。
/// 例: formatRate(18, 25) -> '72.0%'。count が 0 のときは '-'。
String formatRate(int correct, int count) {
  if (count == 0) {
    return '-';
  }
  return '${(correct / count * 100).toStringAsFixed(1)}%';
}
