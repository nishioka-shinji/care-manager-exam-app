import 'package:flutter/foundation.dart';

import '../../core/models/current_session.dart';
import '../../core/models/exam.dart';
import '../../core/models/exam_meta.dart';
import '../../core/models/session.dart';
import '../../data/exam_repository.dart';
import '../../data/storage_repository.dart';

/// index.json の1エントリと、その本体をロード済みの [Exam] の組。
typedef ExamEntry = ({ExamMeta meta, Exam exam});

/// ホーム画面の状態と手続きをまとめる。移植元 home.js の renderHome の
/// データ取得部分（storage/exam_repository 呼び出し）をここに集める。
class HomeController extends ChangeNotifier {
  HomeController({
    required this.examRepository,
    required this.storageRepository,
  });

  final ExamRepository examRepository;
  final StorageRepository storageRepository;

  bool _loading = true;
  bool _storageAvailable = true;
  bool _loadError = false;
  CurrentSession? _current;
  List<ExamEntry> _examEntries = const [];
  String? _selectedExamId;
  Map<String, List<int>> _wrongNosByExamId = const {};
  List<Session> _sessions = const [];

  bool get loading => _loading;
  bool get storageAvailable => _storageAvailable;

  /// 年度データの読み込み失敗。移植元 home.js:70-77 と同じく、失敗時は
  /// 開始ボタン・分野名を作れないため examEntries は空のまま扱う。
  bool get loadError => _loadError;

  CurrentSession? get current => _current;
  List<ExamEntry> get examEntries => _examEntries;

  /// 開始ボタンが作用する年度（index.json の先頭）。無ければ null。
  ///
  /// 旧テストと呼び出し側の互換用に残す。実際の開始対象は
  /// [selectedExam] であり、初期選択だけが先頭（最新）年度になる。
  Exam? get primaryExam =>
      _examEntries.isEmpty ? null : _examEntries.first.exam;

  String? get selectedExamId => _selectedExamId;

  Exam? get selectedExam {
    final selectedId = _selectedExamId;
    if (selectedId == null) return null;
    return examById(selectedId);
  }

  List<int> get wrongNos => _wrongNosByExamId[_selectedExamId] ?? const [];

  List<Session> get sessions => _sessions;

  Exam? examById(String examId) {
    for (final entry in _examEntries) {
      if (entry.exam.id == examId) return entry.exam;
    }
    return null;
  }

  String examTitleOf(String examId) => examById(examId)?.title ?? '第$examId回';

  Future<void> load() async {
    if (!storageRepository.isAvailable()) {
      await storageRepository.init();
    }
    _storageAvailable = storageRepository.isAvailable();
    _current = await storageRepository.loadCurrent();

    try {
      final metas = await examRepository.loadIndex();
      final entries = <ExamEntry>[];
      for (final meta in metas) {
        entries.add((meta: meta, exam: await examRepository.loadExam(meta.id)));
      }
      _examEntries = entries;
      _loadError = false;
    } catch (_) {
      _loadError = true;
      _examEntries = const [];
    }

    // didPopNext による再ロードでも選択中の年度を保つ。削除された
    // 年度だけは index 先頭（最新）へ安全にフォールバックする。
    if (!_examEntries.any((entry) => entry.exam.id == _selectedExamId)) {
      _selectedExamId = primaryExam?.id;
    }

    _wrongNosByExamId = {
      for (final entry in _examEntries)
        entry.exam.id: storageRepository.getWrongQuestionNos(entry.exam.id),
    };
    _sessions = storageRepository.loadSessions();

    _loading = false;
    notifyListeners();
  }

  /// 開始・復習の対象年度を切り替える。
  void selectExam(String examId) {
    if (examId == _selectedExamId || examById(examId) == null) return;
    _selectedExamId = examId;
    notifyListeners();
  }

  /// 中断中セッションを破棄する。
  Future<void> discardCurrent() async {
    await storageRepository.clearCurrent();
    _current = null;
    notifyListeners();
  }

  /// 全問番号（本番通し）または[nos]（復習）で新しい中断セッションを作る。
  /// 呼び出し前の上書き確認は画面側（[ConfirmSheet]）の責務とする。
  Future<void> startSession(QuizMode mode, List<int> questionNos) async {
    final exam = selectedExam;
    if (exam == null) return;
    final next = CurrentSession(
      examId: exam.id,
      mode: mode,
      startedAt: DateTime.now().toIso8601String(),
      questionNos: questionNos,
      cursor: 0,
      answers: const {},
    );
    await storageRepository.saveCurrent(next);
    _current = next;
    notifyListeners();
  }
}
