/// index.json の1エントリ。実データ本体を読まずに一覧表示するための軽量情報。
class ExamMeta {
  const ExamMeta({required this.id, required this.title, required this.file});

  final String id;
  final String title;
  final String file;

  factory ExamMeta.fromJson(Map<String, dynamic> json) {
    return ExamMeta(
      id: json['id'] as String,
      title: json['title'] as String,
      file: json['file'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'title': title, 'file': file};
  }
}
