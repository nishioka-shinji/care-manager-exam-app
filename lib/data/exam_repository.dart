import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../core/models/exam.dart';
import '../core/models/exam_meta.dart';

/// `assets/data/` 配下の JSON をロードする層。データは約 1.9MB なので
/// 起動時の一括ロードで足り、都度パースし直さないようインスタンス内にキャッシュする。
class ExamRepository {
  static const _indexPath = 'assets/data/index.json';

  List<ExamMeta>? _indexCache;
  final Map<String, Exam> _examCache = {};

  /// index.json をロードし、試験一覧を返す。以後の呼び出しはキャッシュを返す。
  Future<List<ExamMeta>> loadIndex() async {
    final cached = _indexCache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(_indexPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final exams = (decoded['exams'] as List<dynamic>)
        .map((e) => ExamMeta.fromJson(e as Map<String, dynamic>))
        .toList();
    _indexCache = exams;
    return exams;
  }

  /// [examId] に対応する試験本体をロードする。index.json からファイル名を
  /// 突き合わせるため、必ず [loadIndex] を経由する。以後の呼び出しはキャッシュを返す。
  Future<Exam> loadExam(String examId) async {
    final cached = _examCache[examId];
    if (cached != null) return cached;

    final index = await loadIndex();
    ExamMeta? meta;
    for (final m in index) {
      if (m.id == examId) {
        meta = m;
        break;
      }
    }
    if (meta == null) {
      throw ArgumentError('exam not found in index.json: $examId');
    }

    final raw = await rootBundle.loadString('assets/data/${meta.file}');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final exam = Exam.fromJson(decoded);
    _examCache[examId] = exam;
    return exam;
  }
}
