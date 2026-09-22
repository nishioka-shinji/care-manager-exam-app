import 'dart:convert';

import 'package:care_manager_exam_app/core/models/exam.dart';
import 'package:care_manager_exam_app/core/models/exam_meta.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _questionNumbers(int from, int to) => [
  for (var no = from; no <= to; no++) no,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const expectedIds = [
    '28',
    '27',
    '26',
    '25',
    '24',
    '23',
    '2202',
    '2201',
    '21',
    '20',
    '19',
    '18',
    '17',
    '16',
    '15',
    '14',
  ];

  late List<Map<String, dynamic>> indexEntries;
  late List<ExamMeta> metas;
  late Map<String, Exam> exams;

  setUpAll(() async {
    final indexRaw = await rootBundle.loadString('assets/data/index.json');
    final index = jsonDecode(indexRaw) as Map<String, dynamic>;
    indexEntries = (index['exams'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    metas = indexEntries.map(ExamMeta.fromJson).toList();

    exams = {};
    for (final meta in metas) {
      final examRaw = await rootBundle.loadString('assets/data/${meta.file}');
      exams[meta.id] = Exam.fromJson(
        jsonDecode(examRaw) as Map<String, dynamic>,
      );
    }
  });

  test('index に全16試験が所定の順序と固有ID・ファイル名で収録されている', () {
    expect(metas.map((meta) => meta.id), expectedIds);
    expect(metas.map((meta) => meta.id).toSet(), hasLength(16));
    expect(metas.map((meta) => meta.file).toSet(), hasLength(16));

    for (final meta in metas) {
      expect(meta.file, 'exam-${meta.id}.json');
    }
    expect(metas.map((meta) => meta.id), containsAll(['2201', '2202']));
  });

  test('index の件数・出典・分野メタデータが全試験で完全である', () {
    for (final entry in indexEntries) {
      final id = entry['id'] as String;
      expect(entry['questionCount'], 60, reason: 'exam=$id');
      expect(
        entry['source'],
        'https://www.care-news.jp/kakomon/$id/all_test.html',
        reason: 'exam=$id',
      );
      expect(entry['sections'], [
        {'id': 'care', 'name': '介護支援分野', 'from': 1, 'to': 25},
        {'id': 'health_welfare', 'name': '保健医療福祉サービス分野', 'from': 26, 'to': 60},
      ], reason: 'exam=$id');
    }
  });

  test('全16試験を本番モデルで読み込み、index と本体のメタデータが一致する', () {
    expect(exams, hasLength(16));

    for (var i = 0; i < metas.length; i++) {
      final meta = metas[i];
      final entry = indexEntries[i];
      final exam = exams[meta.id]!;

      expect(exam.id, meta.id);
      expect(exam.title, meta.title, reason: 'exam=${meta.id}');
      expect(exam.source, entry['source'], reason: 'exam=${meta.id}');
      expect(exam.credit, '解答・解説: 学校法人 藤仁館学園');
      expect(exam.questions, hasLength(entry['questionCount'] as int));
    }
  });

  test('全960問の番号・選択肢・正答が一貫している', () {
    expect(
      exams.values.fold<int>(0, (sum, exam) => sum + exam.questions.length),
      960,
    );

    for (final exam in exams.values) {
      expect(
        exam.questions.map((question) => question.no),
        _questionNumbers(1, 60),
      );

      for (final question in exam.questions) {
        final context = 'exam=${exam.id} question=${question.no}';
        final choiceNos = question.choices.map((choice) => choice.no).toSet();
        expect(question.choices, hasLength(5), reason: context);
        expect(choiceNos, {1, 2, 3, 4, 5}, reason: context);
        expect(
          question.answers,
          hasLength(question.selectCount),
          reason: context,
        );
        expect(
          question.answers.toSet(),
          hasLength(question.answers.length),
          reason: context,
        );
        expect(choiceNos, containsAll(question.answers), reason: context);
      }
    }
  });

  test('全試験の分野範囲が60問を重複なく覆い、各設問の分野と一致する', () {
    for (final exam in exams.values) {
      expect(exam.sections, hasLength(2), reason: 'exam=${exam.id}');

      final coveredQuestionNos = <int>{};
      for (final section in exam.sections) {
        coveredQuestionNos.addAll(_questionNumbers(section.from, section.to));
        final questions = exam.questions
            .where((question) => question.sectionId == section.id)
            .toList();
        expect(
          questions.map((question) => question.no),
          _questionNumbers(section.from, section.to),
          reason: 'exam=${exam.id} section=${section.id}',
        );
      }
      expect(
        coveredQuestionNos,
        _questionNumbers(1, 60).toSet(),
        reason: 'exam=${exam.id}',
      );
    }
  });
}
