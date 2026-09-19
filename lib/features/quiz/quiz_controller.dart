import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/current_session.dart';
import '../../core/models/exam.dart';
import '../../core/models/question.dart';
import '../../core/models/session.dart';
import '../../core/scoring.dart';
import '../../data/exam_repository.dart';
import '../../data/storage_repository.dart';

/// 2 桁ゼロ埋め。移植元 quiz.js の pad() と同じ。
String _pad(int n) => n.toString().padLeft(2, '0');

/// `s_YYYYMMDD_HHmm` を基本形に、既存 id と衝突すれば秒 → 連番で衝突回避する
/// （移植元 quiz.js:33-44 と同じ規則）。
String generateSessionId(DateTime now, Set<String> existingIds) {
  final base =
      's_${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}';
  if (!existingIds.contains(base)) return base;
  var candidate = '$base${_pad(now.second)}';
  var suffix = 1;
  while (existingIds.contains(candidate)) {
    candidate = '$base${_pad(now.second)}_$suffix';
    suffix += 1;
  }
  return candidate;
}

/// 演習画面の状態と手続きをまとめる。設問の切替（[cursorIndex]）だけを
/// 監視対象にし、選択状態は [selectionOf] が返す設問ごとの [ValueNotifier] に
/// 分離する（不変条件2: 選択トグルで画面全体を作り直さない）。
class QuizController extends ChangeNotifier {
  QuizController({
    required this.examRepository,
    required this.storageRepository,
  });

  final ExamRepository examRepository;
  final StorageRepository storageRepository;

  Exam? _exam;
  CurrentSession? _current;
  int _cursorIndex = 0;
  bool _loading = true;
  bool _brokenCurrent = false;
  bool _loadError = false;
  bool _submitted = false;

  // 設問ごとの選択状態。設問切替時のみ作り直し、選択トグルのハンドラは
  // 該当する ValueNotifier の値だけを更新する。
  final Map<int, ValueNotifier<Set<int>>> _selectionByNo = {};

  Exam? get exam => _exam;
  bool get loading => _loading;

  /// cme:current が無い／壊れている状態。true ならホームへ戻す。
  /// 読み込み失敗時（[loadError]）は自動遷移せず警告表示に譲るため除外する。
  bool get shouldRedirectHome =>
      !_loading && !_loadError && (_current == null || _brokenCurrent);

  /// 問題データの読み込みに失敗した状態。移植元 quiz.js:163-174 と同じく
  /// 自動遷移はせず、画面に警告とホームへ戻る導線を出す。
  bool get loadError => _loadError;

  int get cursorIndex => _cursorIndex;
  List<int> get questionNos => _current?.questionNos ?? const [];
  QuizMode get mode => _current?.mode ?? QuizMode.full;

  int get currentNo => questionNos[_cursorIndex];

  Question? get currentQuestion {
    final e = _exam;
    if (e == null) return null;
    for (final q in e.questions) {
      if (q.no == currentNo) return q;
    }
    return null;
  }

  String sectionNameOf(int no) {
    final e = _exam;
    if (e == null) return '';
    for (final section in e.sections) {
      if (no >= section.from && no <= section.to) return section.name;
    }
    return '';
  }

  bool get canGoPrev => _cursorIndex > 0;
  bool get canGoNext => _cursorIndex < questionNos.length - 1;

  /// 選択済み選択肢番号の集合。設問が切り替わるまで同一インスタンスを保つ。
  ValueNotifier<Set<int>> selectionOf(int no) {
    return _selectionByNo.putIfAbsent(no, () {
      final saved = _current?.answers[no];
      return ValueNotifier<Set<int>>(saved == null ? {} : saved.toSet());
    });
  }

  /// cme:current をロードし、対応する exam を読み込む。
  /// StorageRepository.init() は複数回呼んでも安全なため、ここで待ってから使う。
  Future<void> load() async {
    if (!storageRepository.isAvailable()) {
      await storageRepository.init();
    }
    final current = await storageRepository.loadCurrent();
    if (current == null) {
      _current = null;
      _loading = false;
      notifyListeners();
      return;
    }
    if (current.questionNos.isEmpty) {
      // 出題対象が空の壊れた current。演習を続行できないためホームへ戻す。
      await storageRepository.clearCurrent();
      _current = null;
      _brokenCurrent = true;
      _loading = false;
      notifyListeners();
      return;
    }

    try {
      _exam = await examRepository.loadExam(current.examId);
    } catch (_) {
      // 移植元 quiz.js:163-174 と同じく通信状態などによる失敗を想定し、
      // 永久スピナーにせず警告表示に落とす（自動でホームへは戻さない）。
      _loadError = true;
      _loading = false;
      notifyListeners();
      return;
    }
    _current = current;
    _cursorIndex = current.cursor.clamp(0, current.questionNos.length - 1);
    _loading = false;
    notifyListeners();
  }

  /// 設問を移動する。cursor を保存してから作り直す。
  Future<void> goTo(int index) async {
    final current = _current;
    if (current == null) return;
    if (index < 0 || index >= current.questionNos.length) return;
    _cursorIndex = index;
    _current = CurrentSession(
      examId: current.examId,
      mode: current.mode,
      startedAt: current.startedAt,
      questionNos: current.questionNos,
      cursor: index,
      answers: current.answers,
    );
    await storageRepository.saveCurrent(_current!);
    notifyListeners();
  }

  /// 選択トグル。ChoiceTile 内の ValueNotifier だけを更新し、
  /// notifyListeners は呼ばない（画面全体を作り直さないため）。
  /// selectCount 到達時は false を返し、呼び出し側でトーストを出す。
  bool toggleChoice(int no, int choiceNo, int selectCount) {
    final selection = selectionOf(no);
    final next = Set<int>.from(selection.value);
    if (next.contains(choiceNo)) {
      next.remove(choiceNo);
    } else {
      if (next.length >= selectCount) return false;
      next.add(choiceNo);
    }
    selection.value = next;
    _persistAnswer(no, next);
    return true;
  }

  void _persistAnswer(int no, Set<int> selected) {
    final current = _current;
    if (current == null) return;
    final answers = Map<int, List<int>>.from(current.answers);
    answers[no] = selected.toList()..sort();
    _current = CurrentSession(
      examId: current.examId,
      mode: current.mode,
      startedAt: current.startedAt,
      questionNos: current.questionNos,
      cursor: current.cursor,
      answers: answers,
    );
    // UI をブロックしない fire-and-forget。中断復帰用の即時永続化。
    unawaited(storageRepository.saveCurrent(_current!));
  }

  int get unansweredCount {
    final current = _current;
    if (current == null) return 0;
    return current.questionNos.where((no) {
      final ans = current.answers[no];
      return ans == null || ans.isEmpty;
    }).length;
  }

  bool isAnswered(int no) {
    final ans = _current?.answers[no];
    return ans != null && ans.isNotEmpty;
  }

  /// 採点を確定する。二重採点防止のため既に確定済みなら何もしない。
  /// 戻り値は生成したセッション id。
  Future<String?> gradeAndFinish() async {
    if (_submitted) return null;
    _submitted = true;

    final exam = _exam;
    final current = _current;
    if (exam == null || current == null) return null;

    // session.answers は questionNos 全件分のキーを持つ確定記録にする
    // （current.answers は触れた問だけのスパースな Map のため正規化する）。
    final fullAnswers = <int, List<int>>{
      for (final no in current.questionNos) no: current.answers[no] ?? const [],
    };

    final result = gradeSession(
      exam,
      questionNos: current.questionNos,
      answers: fullAnswers,
    );

    final existingIds = storageRepository
        .loadSessions()
        .map((s) => s.id)
        .toSet();
    final id = generateSessionId(DateTime.now(), existingIds);
    final session = Session(
      id: id,
      examId: current.examId,
      mode: current.mode,
      startedAt: current.startedAt,
      finishedAt: DateTime.now().toIso8601String(),
      answers: fullAnswers,
      score: result.score,
    );

    await storageRepository.saveSession(session);
    await storageRepository.applyResults([
      for (final r in result.results) (no: r.no, correct: r.correct),
    ]);
    await storageRepository.clearCurrent();

    return id;
  }

  @override
  void dispose() {
    for (final notifier in _selectionByNo.values) {
      notifier.dispose();
    }
    super.dispose();
  }
}
