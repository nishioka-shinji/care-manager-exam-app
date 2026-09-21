import 'session.dart';

/// 進行中の演習。`cme:current` に保存される単位で、離脱時の再開に使う。
///
/// [answers] は演習中に触れた問だけを持つスパースな Map（未回答の問はキー自体が
/// 無い）。[Session.answers] とは異なり、確定記録ではないためこの差を保つ。
/// キー変換は [Session] と同様にここの fromJson/toJson に閉じる。
///
/// [revealed] は一問一答モードだけが使う任意フィールド（答え合わせ済みの問
/// 番号）。full/review の current にはキー自体が存在しないため、[toJson] は
/// 空なら省く。
class CurrentSession {
  const CurrentSession({
    required this.examId,
    required this.mode,
    required this.startedAt,
    required this.questionNos,
    required this.cursor,
    required this.answers,
    this.revealed = const [],
  });

  final String examId;
  final QuizMode mode;
  final String startedAt;
  final List<int> questionNos;
  final int cursor;
  final Map<int, List<int>> answers;
  final List<int> revealed;

  /// 一部フィールドだけを差し替えた複製を作る。[revealed] は既定値が
  /// `const []` のため、指定し忘れると空で上書きされる（F1参照）。
  /// 呼び出し側はこの copyWith を経由し、フィールドを直接列挙しないこと。
  CurrentSession copyWith({
    int? cursor,
    Map<int, List<int>>? answers,
    List<int>? revealed,
  }) {
    return CurrentSession(
      examId: examId,
      mode: mode,
      startedAt: startedAt,
      questionNos: questionNos,
      cursor: cursor ?? this.cursor,
      answers: answers ?? this.answers,
      revealed: revealed ?? this.revealed,
    );
  }

  factory CurrentSession.fromJson(Map<String, dynamic> json) {
    final rawRevealed = json['revealed'];
    return CurrentSession(
      examId: json['examId'] as String,
      mode: QuizMode.fromJson(json['mode'] as String),
      startedAt: json['startedAt'] as String,
      questionNos: (json['questionNos'] as List<dynamic>)
          .map((e) => e as int)
          .toList(),
      cursor: json['cursor'] as int,
      answers: (json['answers'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          int.parse(key),
          (value as List<dynamic>).map((e) => e as int).toList(),
        ),
      ),
      // 移植元 quiz.js の `filter((no) => Number.isInteger(no))` 相当。
      // 非整数要素は捨て、リストでない／無い場合は空にフォールバックする。
      revealed: rawRevealed is List
          ? rawRevealed.whereType<int>().toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'examId': examId,
      'mode': mode.toJson(),
      'startedAt': startedAt,
      'questionNos': questionNos,
      'cursor': cursor,
      'answers': answers.map((key, value) => MapEntry(key.toString(), value)),
      if (revealed.isNotEmpty) 'revealed': (List.of(revealed)..sort()),
    };
  }
}
