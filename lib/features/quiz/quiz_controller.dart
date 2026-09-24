import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/current_session.dart';
import '../../core/models/exam.dart';
import '../../core/models/question.dart';
import '../../core/models/session.dart';
import '../../core/scoring.dart';
import '../../data/exam_repository.dart';
import '../../data/storage_repository.dart';
import '../../notifications/study_reminder.dart';

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
    this.studyReminder,
  });

  final ExamRepository examRepository;
  final StorageRepository storageRepository;

  /// 解答時に最終学習時刻を記録する先。null なら記録しない（テスト既定）。
  final StudyReminderService? studyReminder;

  Exam? _exam;
  CurrentSession? _current;
  int _cursorIndex = 0;
  bool _loading = true;
  bool _brokenCurrent = false;
  bool _loadError = false;
  bool _submitted = false;

  // 一問一答モードで答え合わせ済みの問番号。full/review では常に空のまま。
  final Set<int> _revealed = {};

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
    // full/review では revealed を持ち越さない（移植元 quiz.js:261-265 と同じ
    // isDrill ガード）。clear() はガード外に置き、前回状態を必ず捨てる。
    _revealed.clear();
    if (current.mode == QuizMode.drill) {
      _revealed.addAll(current.revealed);
    }
    _loading = false;
    notifyListeners();
  }

  /// 設問を移動する。cursor を保存してから作り直す。
  Future<void> goTo(int index) async {
    final current = _current;
    if (current == null) return;
    if (index < 0 || index >= current.questionNos.length) return;
    _cursorIndex = index;
    _current = current.copyWith(cursor: index);
    await storageRepository.saveCurrent(_current!);
    notifyListeners();
  }

  /// 選択トグル。ChoiceTile 内の ValueNotifier だけを更新し、
  /// notifyListeners は呼ばない（画面全体を作り直さないため）。
  /// selectCount 到達時は false を返し、呼び出し側でトーストを出す。
  /// 一問一答モードで答え合わせ済みの問は選択を変更できない
  /// （記録済みの正誤と画面の選択状態がずれるのを防ぐ。移植元 quiz.js:612-614）。
  bool toggleChoice(int no, int choiceNo, int selectCount) {
    if (isRevealed(no)) return false;
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
    _current = current.copyWith(answers: answers);
    // UI をブロックしない fire-and-forget。中断復帰用の即時永続化。
    unawaited(storageRepository.saveCurrent(_current!));
    // notifyListeners を伴わないので設問は作り直さない（不変条件2）。
    unawaited(studyReminder?.recordStudy());
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

  /// 一問一答モードで答え合わせ済みかどうか。full/review では常に false。
  /// 選択状態と分離した独立の購読単位にするため、画面側は選択トグルの
  /// notifyListeners を経由せずこの値だけを見に来られる（不変条件2）。
  bool isRevealed(int no) => _revealed.contains(no);

  bool get isCurrentRevealed => isRevealed(currentNo);

  /// 表示中の問を答え合わせする（一問一答モードのみ）。移植元 quiz.js:349-371。
  /// 正誤の記録はここで1問ずつ行う。途中でやめてもホームの「間違えた問題を
  /// 復習」に反映させるためで、終了時の gradeAndFinish では applyStats: false
  /// を渡し二重計上しない。
  ///
  /// 選択数が selectCount に達していなければ false を返す（toggleChoice と
  /// 同じパターン。トースト文言は画面側の責務）。答え合わせ済みなら何もせず
  /// false を返す。成功したら true を返す。
  Future<bool> revealCurrent(int selectCount) async {
    if (mode != QuizMode.drill || isCurrentRevealed) return false;
    final current = _current;
    final question = currentQuestion;
    if (current == null || question == null) return false;

    final selection = selectionOf(currentNo).value;
    if (selection.length != selectCount) return false;

    final chosen = selection.toList()..sort();
    _revealed.add(currentNo);

    final answers = Map<int, List<int>>.from(current.answers);
    answers[currentNo] = chosen;
    _current = current.copyWith(
      answers: answers,
      revealed: _revealed.toList()..sort(),
    );
    await storageRepository.saveCurrent(_current!);
    // read-modify-write のため await を外すと連続答え合わせで書き込みが
    // 競合する。フェイク化しないと検出できないためテストは見送る（F4）。
    await storageRepository.applyResults(current.examId, [
      (no: currentNo, correct: isCorrect(chosen, question.answers)),
    ]);

    notifyListeners();
    return true;
  }

  /// 採点を確定する。二重採点防止のため既に確定済みなら何もしない。
  /// 戻り値は生成したセッション id。
  ///
  /// [questionNos] は採点対象（省略時は出題全件）。一問一答モードでは
  /// 答え合わせ済みの問だけを渡す（[finishDrill] 参照）。[applyStats] は
  /// 正誤を cme:stats に記録するか（既定 true）。一問一答モードは答え合わせの
  /// たびに記録済みなので false を渡して二重計上を防ぐ（移植元 quiz.js:519-521）。
  Future<String?> gradeAndFinish({
    List<int>? questionNos,
    bool applyStats = true,
  }) async {
    if (_submitted) return null;
    _submitted = true;

    final exam = _exam;
    final current = _current;
    if (exam == null || current == null) return null;
    final targetNos = questionNos ?? current.questionNos;

    // session.answers は questionNos 全件分のキーを持つ確定記録にする
    // （current.answers は触れた問だけのスパースな Map のため正規化する）。
    final fullAnswers = <int, List<int>>{
      for (final no in targetNos) no: current.answers[no] ?? const [],
    };

    final result = gradeSession(
      exam,
      questionNos: targetNos,
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
    if (applyStats) {
      await storageRepository.applyResults(current.examId, [
        for (final r in result.results) (no: r.no, correct: r.correct),
      ]);
    }
    await storageRepository.clearCurrent();

    return id;
  }

  /// 一問一答モードを終了して結果画面へ進む（最後の問の「結果を見る」と、
  /// 回答状況シートの「ここまでの結果を見る」の共通処理。移植元
  /// quiz.js:563-575）。採点対象は答え合わせ済みの問だけ。
  ///
  /// [noRevealed] が true のときは「1問も答え合わせしていない」ため何もせず
  /// [id] は null。呼び出し側はこれを「まず1問以上、答え合わせをしてください」
  /// のトーストの合図にする。二重送信で [gradeAndFinish] が null を返した
  /// 場合は [noRevealed] は false のまま [id] だけが null になり、
  /// この2つを取り違えない（F5）。
  Future<({String? id, bool noRevealed})> finishDrill() async {
    final current = _current;
    if (current == null) return (id: null, noRevealed: true);
    final nos = current.questionNos.where(isRevealed).toList();
    if (nos.isEmpty) return (id: null, noRevealed: true);
    final id = await gradeAndFinish(questionNos: nos, applyStats: false);
    return (id: id, noRevealed: false);
  }

  @override
  void dispose() {
    for (final notifier in _selectionByNo.values) {
      notifier.dispose();
    }
    super.dispose();
  }
}
