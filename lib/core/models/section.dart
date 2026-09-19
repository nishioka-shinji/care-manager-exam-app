/// 試験の分野1件。[from]〜[to] は問番号の範囲（両端含む）。
class Section {
  const Section({
    required this.id,
    required this.name,
    required this.from,
    required this.to,
  });

  final String id;
  final String name;
  final int from;
  final int to;

  factory Section.fromJson(Map<String, dynamic> json) {
    return Section(
      id: json['id'] as String,
      name: json['name'] as String,
      from: json['from'] as int,
      to: json['to'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'from': from, 'to': to};
  }
}
