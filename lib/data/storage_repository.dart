import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/current_session.dart';
import '../core/models/question_stat.dart';
import '../core/models/session.dart';

/// [StorageRepository.applyResults] に渡す採点結果1件。
/// `scoring.GradeResult.results`（`List<QuestionResult>`）から
/// `(no: r.no, correct: r.correct)` へ写して渡す。`correct` は未回答を含む
/// 不正解を false とする T3 の定義に一致する。
typedef QuestionOutcome = ({int no, bool correct});

/// 永続化キーの一覧。requirements.md §5 で確定（CLAUDE.md 不変条件 3）。
class StorageKeys {
  static const version = 'cme:v';
  static const sessions = 'cme:sessions';
  static const stats = 'cme:stats';
  static const current = 'cme:current';
}

/// stats の要約集計。履歴画面で使う3指標。
class StatsSummary {
  const StatsSummary({
    required this.tracked,
    required this.everWrong,
    required this.streak2plus,
  });

  final int tracked;
  final int everWrong;
  final int streak2plus;
}

/// shared_preferences への読み書きを担う永続化層。
/// 移植元 `public/js/storage.js` の Dart 版（DOM 前提の localStorage 特有の
/// メモリフォールバックは持たず、shared_preferences の初期化結果のみを見る）。
class StorageRepository {
  static const schemaVersion = 2;
  static const maxSessions = 50;

  /// 旧形式（v1）データを移行する先の年度。第28回のみを解いていた既存
  /// ユーザー向け（移植元 storage.js の LEGACY_STATS_EXAM_ID と同じ）。
  static const _legacyStatsExamId = '28';

  SharedPreferences? _prefs;

  /// 起動時に一度だけ呼び、shared_preferences を初期化してスキーマバージョンを検査する。
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await ensureSchemaVersion();
  }

  /// ネイティブでは shared_preferences が使えない状況は実質起きないため、
  /// 初期化に成功していれば true を返す（Web 版の localStorage 不可対応とは異なる判断）。
  bool isAvailable() => _prefs != null;

  SharedPreferences get _p {
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError('StorageRepository.init() が呼ばれていない');
    }
    return prefs;
  }

  bool _isPlainMap(dynamic value) => value is Map<String, dynamic>;

  /// [QuestionStat] の許容的な読み取り。フィールドが欠落・型違いでも例外を
  /// 投げず、移植元 storage.js の `Number.isFinite` ガードと同じ規則
  /// （数値系は既定値 0、真偽は既定値 false）でフォールバックする。
  QuestionStat _questionStatFromJsonLoose(Map<String, dynamic> json) {
    final attempts = json['attempts'];
    final correct = json['correct'];
    final lastCorrect = json['lastCorrect'];
    final lastAt = json['lastAt'];
    final streak = json['streak'];
    return QuestionStat(
      attempts: attempts is int ? attempts : 0,
      correct: correct is int ? correct : 0,
      lastCorrect: lastCorrect is bool ? lastCorrect : false,
      lastAt: lastAt is String ? lastAt : null,
      streak: streak is int ? streak : 0,
    );
  }

  /// 配列として保存されているキーを読む。JSON が壊れている／配列でない場合は
  /// そのキーだけを空配列で初期化し、[] を返す（他のキーには波及させない）。
  List<dynamic> _readJsonList(String key) {
    final raw = _p.getString(key);
    if (raw == null) return [];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is List) return parsed;
    } catch (_) {
      // 壊れた JSON。下の初期化処理へ。
    }
    _writeJson(key, <dynamic>[]);
    return [];
  }

  /// オブジェクトとして保存されているキーを読む。JSON が壊れている／
  /// プレーンオブジェクトでない場合はそのキーだけを {} で初期化し、{} を返す。
  Map<String, dynamic> _readJsonObject(String key) {
    final raw = _p.getString(key);
    if (raw == null) return {};
    try {
      final parsed = jsonDecode(raw);
      if (_isPlainMap(parsed)) return parsed as Map<String, dynamic>;
    } catch (_) {
      // 壊れた JSON。下の初期化処理へ。
    }
    _writeJson(key, <String, dynamic>{});
    return {};
  }

  Future<bool> _writeJson(String key, dynamic value) {
    return _p.setString(key, jsonEncode(value));
  }

  /// 問番号（1..60 の整数文字列）として妥当なキーか。
  bool _isQuestionNoKey(String key) {
    final n = int.tryParse(key);
    return n != null && n >= 1 && n <= 60 && n.toString() == key;
  }

  /// stats エントリ（{attempts,correct,lastCorrect,...}）の形をしているか。
  /// 移植元 storage.js は `typeof === 'number'` で数値全般（2.0 等）を許すが、
  /// Dart 側は自身が int しか書かないため int 限定にしている。
  bool _isStatsEntry(dynamic value) {
    if (!_isPlainMap(value)) return false;
    final map = value as Map<String, dynamic>;
    return map['attempts'] is int &&
        map['correct'] is int &&
        map['lastCorrect'] is bool;
  }

  /// cme:stats を v1（フラット）から v2（examId スコープ）へ移行する。
  ///
  /// 判定はバージョン番号ではなく cme:stats の中身の形で行う（トップレベル
  /// キーが問番号として妥当かつ値が stats エントリの形であれば旧形式と
  /// 判断）。v2 の値は examId をキーに持つネストしたオブジェクトのため、
  /// この形にはならず誤検知しない。判定できた旧形式キーだけ '28' バケットへ
  /// 退避し、判定できない・壊れたキーはそのキーごと捨てる（既存の破損値
  /// ハンドリング方針を踏襲）。旧形式が無ければ何もしない（冪等）。
  /// 例外は外へ投げない（移行失敗でアプリが起動不能になるのを防ぐ）。
  void _migrateStatsToExamScope() {
    try {
      final stats = _readJsonObject(StorageKeys.stats);
      final hasLegacyEntry = stats.entries.any(
        (e) => _isQuestionNoKey(e.key) && _isStatsEntry(e.value),
      );
      if (!hasLegacyEntry) return;

      final legacyBucket = <String, dynamic>{};
      for (final entry in stats.entries) {
        if (_isQuestionNoKey(entry.key) && _isStatsEntry(entry.value)) {
          legacyBucket[entry.key] = entry.value;
        }
        // 判定できない/壊れたキーはそのキーだけ捨てる。
      }
      _writeJson(StorageKeys.stats, {_legacyStatsExamId: legacyBucket});
    } catch (_) {
      // 移行に失敗しても致命的ではない（既存データが読めないだけ）。何もしない。
    }
  }

  /// cme:v を検査し、schemaVersion と異なれば（未設定・破損・旧バージョン含む）
  /// 移行処理を走らせたうえで書き直す。
  ///
  /// v1 → v2: cme:stats のスキーマ変更（年度スコープ化）に伴い
  /// [_migrateStatsToExamScope] を呼ぶ。旧バージョン番号に関わらず cme:stats
  /// の実際の中身の形で判定するため、version が読めない場合でも移行できる。
  ///
  /// ここが将来のマイグレーション挿入点: 次のスキーマ変更が必要になったら、
  /// バージョン番号を書き直す前にこの関数内で変換処理を挟む。
  Future<void> ensureSchemaVersion() async {
    final raw = _p.getString(StorageKeys.version);
    int? version;
    if (raw != null) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is int) version = parsed;
      } catch (_) {
        version = null;
      }
    }
    if (version != schemaVersion) {
      _migrateStatsToExamScope();
      await _writeJson(StorageKeys.version, schemaVersion);
    }
  }

  /// finishedAt 降順で比較する（不正な日時は末尾へ）。
  int _compareFinishedAtDesc(Session a, Session b) {
    final ta = DateTime.tryParse(a.finishedAt);
    final tb = DateTime.tryParse(b.finishedAt);
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return tb.compareTo(ta);
  }

  /// finishedAt 降順の Session 一覧。コンテナごと壊れていたら [] を返し
  /// キーを初期化する。要素単位でフィールド欠落・型違いがある場合は、
  /// その要素だけを読み飛ばし他の正常な要素は生かす。
  List<Session> loadSessions() {
    final list = <Session>[];
    for (final item in _readJsonList(StorageKeys.sessions)) {
      if (item is! Map<String, dynamic>) continue;
      try {
        list.add(Session.fromJson(item));
      } catch (_) {
        // 要素が壊れている（フィールド欠落・型違い）。この要素だけ捨てる。
      }
    }
    list.sort(_compareFinishedAtDesc);
    return list;
  }

  Session? getSessionById(String id) {
    for (final session in loadSessions()) {
      if (session.id == id) return session;
    }
    return null;
  }

  /// セッションを先頭に追加し、maxSessions（50）件を超えたら古いものから削除する。
  Future<bool> saveSession(Session session) async {
    final list = _readJsonList(StorageKeys.sessions);
    final next = [session.toJson(), ...list];
    final trimmed = next.length > maxSessions
        ? next.sublist(0, maxSessions)
        : next;
    return _writeJson(StorageKeys.sessions, trimmed);
  }

  /// 指定年度 [examId] バケット内の問題ごとの正誤履歴。エントリ単位で
  /// 壊れている（Map でない）ものは読み飛ばし、フィールド欠落・型違いの
  /// エントリは [_questionStatFromJsonLoose] で補完して生かす。
  Map<String, QuestionStat> loadStats(String examId) {
    final stats = <String, QuestionStat>{};
    final stored = _readJsonObject(StorageKeys.stats)[examId];
    if (!_isPlainMap(stored)) return stats;
    for (final entry in (stored as Map<String, dynamic>).entries) {
      if (!_isPlainMap(entry.value)) continue;
      stats[entry.key] = _questionStatFromJsonLoose(
        entry.value as Map<String, dynamic>,
      );
    }
    return stats;
  }

  /// 採点結果を受け、[examId] でスコープした問題ごとの正誤履歴を更新する。
  ///   - attempts: 呼ばれるたびに +1
  ///   - correct: 正解なら +1
  ///   - lastCorrect / lastAt: 今回の値で上書き
  ///   - streak: 正解なら +1、不正解（未回答含む）なら 0 にリセット
  /// 同じ問番号でも examId が異なれば別レコードとして扱う（年度スコープ化）。
  /// [examId] が空文字なら何も書かず false を返す。
  Future<bool> applyResults(
    String examId,
    List<QuestionOutcome> results,
  ) async {
    if (examId.isEmpty) return false;
    final stats = _readJsonObject(StorageKeys.stats);
    final bucketRaw = stats[examId];
    final bucket = _isPlainMap(bucketRaw)
        ? bucketRaw as Map<String, dynamic>
        : <String, dynamic>{};
    final now = DateTime.now().toIso8601String();
    for (final r in results) {
      final key = r.no.toString();
      final prevRaw = bucket[key];
      final prev = _isPlainMap(prevRaw)
          ? _questionStatFromJsonLoose(prevRaw as Map<String, dynamic>)
          : const QuestionStat(
              attempts: 0,
              correct: 0,
              lastCorrect: false,
              lastAt: null,
              streak: 0,
            );
      final isCorrect = r.correct;
      final updated = QuestionStat(
        attempts: prev.attempts + 1,
        correct: prev.correct + (isCorrect ? 1 : 0),
        lastCorrect: isCorrect,
        lastAt: now,
        streak: isCorrect ? prev.streak + 1 : 0,
      );
      bucket[key] = updated.toJson();
    }
    stats[examId] = bucket;
    return _writeJson(StorageKeys.stats, stats);
  }

  /// 復習モードの出題対象。指定年度 [examId] のうち、直近の解答が不正解
  /// だった（未回答も不正解扱い）問番号を昇順で返す。移植元 storage.js の
  /// `stats[key].lastCorrect === false` と同じ厳密比較にするため、
  /// [loadStats] の既定値フォールバックではなく生の値を見る。
  /// [examId] が空文字なら空配列を返す（誤って全年度を混ぜないため）。
  List<int> getWrongQuestionNos(String examId) {
    if (examId.isEmpty) return [];
    final nos = <int>[];
    final bucketRaw = _readJsonObject(StorageKeys.stats)[examId];
    if (!_isPlainMap(bucketRaw)) return nos;
    for (final entry in (bucketRaw as Map<String, dynamic>).entries) {
      if (!_isPlainMap(entry.value)) continue;
      final map = entry.value as Map<String, dynamic>;
      if (map['lastCorrect'] != false) continue;
      final no = int.tryParse(entry.key);
      if (no != null) nos.add(no);
    }
    nos.sort();
    return nos;
  }

  /// 履歴画面のサマリ用集計。[examId] を省略した場合は全年度を合算した
  /// 値を返す。指定した場合はその年度の記録のみに絞った集計を返す。
  ///   - tracked: 記録のある問題数
  ///   - everWrong: attempts - correct > 0 の件数（一度でも間違えた問題）
  ///   - streak2plus: streak >= 2 の件数（連続正解2回以上）
  StatsSummary summarizeStats({String? examId}) {
    final stats = _readJsonObject(StorageKeys.stats);
    final buckets = examId != null && examId.isNotEmpty
        ? [
            if (_isPlainMap(stats[examId]))
              stats[examId] as Map<String, dynamic>,
          ]
        : stats.values.whereType<Map<String, dynamic>>().toList();
    final entries = <QuestionStat>[];
    for (final bucket in buckets) {
      for (final value in bucket.values) {
        if (!_isPlainMap(value)) continue;
        entries.add(_questionStatFromJsonLoose(value as Map<String, dynamic>));
      }
    }
    final tracked = entries.length;
    final everWrong = entries.where((s) => s.attempts - s.correct > 0).length;
    final streak2plus = entries.where((s) => s.streak >= 2).length;
    return StatsSummary(
      tracked: tracked,
      everWrong: everWrong,
      streak2plus: streak2plus,
    );
  }

  /// cme:current が期待する最低限の形か検査する。
  bool _isValidCurrent(dynamic value) {
    if (!_isPlainMap(value)) return false;
    final map = value as Map<String, dynamic>;
    return map['examId'] is String &&
        QuizMode.values.any((mode) => mode.name == map['mode']) &&
        map['startedAt'] is String &&
        map['questionNos'] is List &&
        map['cursor'] is int &&
        _isPlainMap(map['answers']) &&
        // revealed は一問一答モードだけが使う任意フィールド。full/review の
        // current には存在しないため、未設定も妥当な形として許す。要素型の
        // 検査は fromJson 側（非整数要素の除去）に寄せる。
        (map['revealed'] == null || map['revealed'] is List);
  }

  /// 中断中セッション。無ければ null。破損していればキーを削除して null を返す。
  Future<CurrentSession?> loadCurrent() async {
    final raw = _p.getString(StorageKeys.current);
    if (raw == null) return null;
    dynamic parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      await _p.remove(StorageKeys.current);
      return null;
    }
    if (!_isValidCurrent(parsed)) {
      await _p.remove(StorageKeys.current);
      return null;
    }
    // _isValidCurrent は最低限の形しか見ないため、fromJson がさらに厳格な
    // キャストで失敗する余地がある。その場合も他の不正系と同様に扱う。
    try {
      return CurrentSession.fromJson(parsed as Map<String, dynamic>);
    } catch (_) {
      await _p.remove(StorageKeys.current);
      return null;
    }
  }

  Future<bool> saveCurrent(CurrentSession current) {
    return _writeJson(StorageKeys.current, current.toJson());
  }

  Future<bool> clearCurrent() {
    return _p.remove(StorageKeys.current);
  }

  /// cme: 系キーを全削除し、スキーマバージョンを書き直す。
  Future<bool> clearAll() async {
    final results = await Future.wait([
      _p.remove(StorageKeys.version),
      _p.remove(StorageKeys.sessions),
      _p.remove(StorageKeys.stats),
      _p.remove(StorageKeys.current),
    ]);
    await ensureSchemaVersion();
    return results.every((ok) => ok);
  }
}
