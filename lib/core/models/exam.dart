import 'question.dart';
import 'section.dart';

/// 1回の試験（過去問1年度分）。[id] は index.json とのキー突き合わせに使うため
/// 常に文字列（実データは "28" のような数値に見える文字列）。
class Exam {
  const Exam({
    required this.id,
    required this.title,
    required this.source,
    required this.credit,
    required this.fetchedAt,
    required this.sections,
    required this.questions,
  });

  final String id;
  final String title;
  final String source;
  final String credit;
  final String fetchedAt;
  final List<Section> sections;
  final List<Question> questions;

  factory Exam.fromJson(Map<String, dynamic> json) {
    return Exam(
      id: json['id'] as String,
      title: json['title'] as String,
      source: json['source'] as String,
      credit: json['credit'] as String,
      fetchedAt: json['fetchedAt'] as String,
      sections: (json['sections'] as List<dynamic>)
          .map((e) => Section.fromJson(e as Map<String, dynamic>))
          .toList(),
      questions: (json['questions'] as List<dynamic>)
          .map((e) => Question.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'source': source,
      'credit': credit,
      'fetchedAt': fetchedAt,
      'sections': sections.map((s) => s.toJson()).toList(),
      'questions': questions.map((q) => q.toJson()).toList(),
    };
  }
}
