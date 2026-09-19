import 'package:flutter/foundation.dart';

import '../../core/models/exam.dart';
import '../../core/models/session.dart';
import '../../data/exam_repository.dart';
import '../../data/storage_repository.dart';

/// 履歴画面の状態と手続きをまとめる。移植元 history.js の renderHistory の
/// データ取得部分（storage/exam_repository 呼び出し）をここに集める。
///
/// 分野名解決は各 [Session.examId] で個別に引く（[HomeController.load] と
/// 同じ全件ロード方式）。読み込みに失敗しても履歴一覧自体は表示する
/// （該当 examId が map にないままとし、表示側は sectionId にフォールバックする）。
class HistoryController extends ChangeNotifier {
  HistoryController({
    required this.examRepository,
    required this.storageRepository,
  });

  final ExamRepository examRepository;
  final StorageRepository storageRepository;

  bool _loading = true;
  bool _storageAvailable = true;
  Map<String, Exam> _examsById = const {};
  List<Session> _sessions = const [];
  StatsSummary _stats = const StatsSummary(
    tracked: 0,
    everWrong: 0,
    streak2plus: 0,
  );

  bool get loading => _loading;
  bool get storageAvailable => _storageAvailable;
  Exam? examFor(String examId) => _examsById[examId];
  List<Session> get sessions => _sessions;
  StatsSummary get stats => _stats;

  Future<void> load() async {
    if (!storageRepository.isAvailable()) {
      await storageRepository.init();
    }
    _storageAvailable = storageRepository.isAvailable();

    try {
      final metas = await examRepository.loadIndex();
      final entries = <String, Exam>{};
      for (final meta in metas) {
        entries[meta.id] = await examRepository.loadExam(meta.id);
      }
      _examsById = entries;
    } catch (_) {
      _examsById = const {};
    }

    _sessions = storageRepository.loadSessions();
    _stats = storageRepository.summarizeStats();
    _loading = false;
    notifyListeners();
  }

  /// 受験履歴・問題ごとの記録をすべて削除し、状態を作り直す。
  /// 移植元は同一ルートへの再遷移がガードされるため render を直接呼び直す
  /// 回避策を取るが、Flutter では setState 相当の再読み込みで足りる。
  Future<void> clearAllAndReload() async {
    await storageRepository.clearAll();
    await load();
  }
}
