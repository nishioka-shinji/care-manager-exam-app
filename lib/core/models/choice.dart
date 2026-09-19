/// 設問の選択肢1件。[no] は設問内での選択肢番号（1始まり）。
class Choice {
  const Choice({
    required this.no,
    required this.text,
    required this.explanation,
  });

  final int no;
  final String text;
  final String explanation;

  factory Choice.fromJson(Map<String, dynamic> json) {
    return Choice(
      no: json['no'] as int,
      text: json['text'] as String,
      explanation: json['explanation'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'no': no, 'text': text, 'explanation': explanation};
  }
}
