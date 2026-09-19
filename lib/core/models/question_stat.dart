/// `cme:stats` の1エントリ（問番号ごとの正誤履歴）。
///
/// [streak] は連続正解数。正解するたびに +1、不正解（未回答含む）で 0 に
/// リセットする。履歴画面の「連続正解2回以上」集計に使う。
class QuestionStat {
  const QuestionStat({
    required this.attempts,
    required this.correct,
    required this.lastCorrect,
    required this.lastAt,
    required this.streak,
  });

  final int attempts;
  final int correct;
  final bool lastCorrect;
  final String? lastAt;
  final int streak;

  factory QuestionStat.fromJson(Map<String, dynamic> json) {
    return QuestionStat(
      attempts: json['attempts'] as int,
      correct: json['correct'] as int,
      lastCorrect: json['lastCorrect'] as bool,
      lastAt: json['lastAt'] as String?,
      streak: json['streak'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'attempts': attempts,
      'correct': correct,
      'lastCorrect': lastCorrect,
      'lastAt': lastAt,
      'streak': streak,
    };
  }
}
