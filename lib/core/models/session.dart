/// 出題モード。JSON 上は 'full'（本番通し） / 'review'（復習） / 'drill'（一問一答）の文字列。
enum QuizMode {
  full,
  review,
  drill;

  String toJson() => name;

  static QuizMode fromJson(String value) {
    return QuizMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => throw FormatException('unknown QuizMode: $value'),
    );
  }
}

/// モードの表示ラベル。移植元 result.js / home.js / history.js の MODE_LABELS と同じ。
String modeLabel(QuizMode mode) => switch (mode) {
  QuizMode.full => '本番通し',
  QuizMode.review => '復習',
  QuizMode.drill => '一問一答',
};

/// 分野別の得点。[correct] / [count] の組。
class SectionScore {
  const SectionScore({required this.correct, required this.count});

  final int correct;
  final int count;

  factory SectionScore.fromJson(List<dynamic> json) {
    return SectionScore(correct: json[0] as int, count: json[1] as int);
  }

  List<int> toJson() => [correct, count];
}

/// 1回の受験の採点結果。[total] / [max] は全体、[bySection] は分野別。
class Score {
  const Score({
    required this.total,
    required this.max,
    required this.bySection,
  });

  final int total;
  final int max;
  final Map<String, SectionScore> bySection;

  factory Score.fromJson(Map<String, dynamic> json) {
    return Score(
      total: json['total'] as int,
      max: json['max'] as int,
      bySection: (json['bySection'] as Map<String, dynamic>).map(
        (key, value) =>
            MapEntry(key, SectionScore.fromJson(value as List<dynamic>)),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'max': max,
      'bySection': bySection.map((key, value) => MapEntry(key, value.toJson())),
    };
  }
}

/// 完了済みの1回の受験記録。`cme:sessions` に保存される単位。
///
/// [answers] の内部表現は `Map<int, List<int>>`。JSON 上のキーは常に文字列に
/// なる（オブジェクトキーの仕様上）ため、変換はここの fromJson/toJson に閉じる。
class Session {
  const Session({
    required this.id,
    required this.examId,
    required this.mode,
    required this.startedAt,
    required this.finishedAt,
    required this.answers,
    required this.score,
  });

  final String id;
  final String examId;
  final QuizMode mode;
  final String startedAt;
  final String finishedAt;
  final Map<int, List<int>> answers;
  final Score score;

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      examId: json['examId'] as String,
      mode: QuizMode.fromJson(json['mode'] as String),
      startedAt: json['startedAt'] as String,
      finishedAt: json['finishedAt'] as String,
      answers: (json['answers'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          int.parse(key),
          (value as List<dynamic>).map((e) => e as int).toList(),
        ),
      ),
      score: Score.fromJson(json['score'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'examId': examId,
      'mode': mode.toJson(),
      'startedAt': startedAt,
      'finishedAt': finishedAt,
      'answers': answers.map((key, value) => MapEntry(key.toString(), value)),
      'score': score.toJson(),
    };
  }
}
