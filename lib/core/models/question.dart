import 'choice.dart';

/// 設問1件。[no] は試験全体を通した問番号（1始まり）。
class Question {
  const Question({
    required this.no,
    required this.sectionId,
    required this.text,
    required this.selectCount,
    required this.choices,
    required this.answers,
  });

  final int no;
  final String sectionId;
  final String text;
  final int selectCount;
  final List<Choice> choices;
  final List<int> answers;

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      no: json['no'] as int,
      sectionId: json['sectionId'] as String,
      text: json['text'] as String,
      selectCount: json['selectCount'] as int,
      choices: (json['choices'] as List<dynamic>)
          .map((e) => Choice.fromJson(e as Map<String, dynamic>))
          .toList(),
      answers: (json['answers'] as List<dynamic>).map((e) => e as int).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'no': no,
      'sectionId': sectionId,
      'text': text,
      'selectCount': selectCount,
      'choices': choices.map((c) => c.toJson()).toList(),
      'answers': answers,
    };
  }
}
