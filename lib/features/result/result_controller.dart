import 'package:flutter/foundation.dart';

import '../../core/models/current_session.dart';
import '../../core/models/exam.dart';
import '../../core/models/session.dart';
import '../../core/scoring.dart';
import '../../data/exam_repository.dart';
import '../../data/storage_repository.dart';

/// 結果画面の状態と手続きをまとめる。移植元 result.js のとおり、
/// session.score は信用せず session.answers から常に再採点する。
class ResultController extends ChangeNotifier {
  ResultController({
    required this.examRepository,
    required this.storageRepository,
    required this.sessionId,
  });

  final ExamRepository examRepository;
  final StorageRepository storageRepository;
  final String? sessionId;

  Session? _session;
  Exam? _exam;
  GradeResult? _gradeResult;
  bool _loading = true;
  bool _notFound = false;
  bool _loadError = false;

  bool get loading => _loading;

  /// sessionId が無い／該当セッションが見つからない状態。true ならホームへ戻す。
  bool get notFound => _notFound;

  /// 問題データの読み込みに失敗した状態。演習画面と同じく自動遷移はしない。
  bool get loadError => _loadError;

  Session? get session => _session;
  Exam? get exam => _exam;
  GradeResult? get gradeResult => _gradeResult;

  /// session.answers のキーを数値昇順にしたもの（conventions.session_flow）。
  List<int> get questionNos {
    final session = _session;
    if (session == null) return const [];
    return session.answers.keys.toList()..sort();
  }

  Future<void> load() async {
    if (!storageRepository.isAvailable()) {
      await storageRepository.init();
    }
    final id = sessionId;
    final session = id == null ? null : storageRepository.getSessionById(id);
    if (session == null) {
      _notFound = true;
      _loading = false;
      notifyListeners();
      return;
    }
    _session = session;

    try {
      _exam = await examRepository.loadExam(session.examId);
    } catch (_) {
      _loadError = true;
      _loading = false;
      notifyListeners();
      return;
    }

    _gradeResult = gradeSession(
      _exam!,
      questionNos: questionNos,
      answers: session.answers,
    );
    _loading = false;
    notifyListeners();
  }

  /// 間違えた問番号（未回答含む）の昇順。
  List<int> get wrongQuestionNos {
    final result = _gradeResult;
    if (result == null) return const [];
    final nos = result.results
        .where((r) => !r.correct)
        .map((r) => r.no)
        .toList();
    nos.sort();
    return nos;
  }

  /// 復習セッションを作って cme:current に保存する。
  /// [CurrentSession] の形は QuizController.load() が読む形と一致させる。
  Future<void> startReview() async {
    final session = _session;
    final wrongNos = wrongQuestionNos;
    if (session == null || wrongNos.isEmpty) return;
    await storageRepository.saveCurrent(
      CurrentSession(
        examId: session.examId,
        mode: QuizMode.review,
        startedAt: DateTime.now().toIso8601String(),
        questionNos: wrongNos,
        cursor: 0,
        answers: const {},
      ),
    );
  }
}
