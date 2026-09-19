import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_manager_exam_app/core/models/current_session.dart';
import 'package:care_manager_exam_app/core/models/session.dart';
import 'package:care_manager_exam_app/data/storage_repository.dart';

Session _buildSession({required String id, required String finishedAt}) {
  return Session(
    id: id,
    examId: '28',
    mode: QuizMode.full,
    startedAt: '2026-09-19T00:00:00.000Z',
    finishedAt: finishedAt,
    answers: {
      1: [3, 4],
    },
    score: const Score(
      total: 1,
      max: 2,
      bySection: {'care': SectionScore(correct: 1, count: 2)},
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StorageRepository の基本の往復', () {
    test('saveSession / loadSessions で内容が保たれる', () async {
      final repo = StorageRepository();
      await repo.init();

      final session = _buildSession(
        id: 's1',
        finishedAt: '2026-09-19T00:30:00.000Z',
      );
      await repo.saveSession(session);

      final loaded = repo.loadSessions();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 's1');
      expect(loaded.first.examId, '28');
      expect(loaded.first.answers, session.answers);
      expect(loaded.first.score.total, 1);
      expect(repo.getSessionById('s1')?.id, 's1');
      expect(repo.getSessionById('nope'), isNull);
    });

    test('isAvailable は init 後 true', () async {
      final repo = StorageRepository();
      expect(repo.isAvailable(), isFalse);
      await repo.init();
      expect(repo.isAvailable(), isTrue);
    });
  });

  group('cme:sessions の50件上限', () {
    test('51件目を保存すると最古（末尾）が捨てられる', () async {
      final repo = StorageRepository();
      await repo.init();

      for (var i = 0; i < 51; i++) {
        final finishedAt =
            '2026-09-19T00:${i.toString().padLeft(2, '0')}:00.000Z';
        await repo.saveSession(
          _buildSession(id: 's$i', finishedAt: finishedAt),
        );
      }

      final loaded = repo.loadSessions();
      expect(loaded, hasLength(50));
      // 最新（s50）が先頭、最古（s0）は上限超過で捨てられている。
      expect(loaded.first.id, 's50');
      expect(loaded.map((s) => s.id), isNot(contains('s0')));
      expect(loaded.map((s) => s.id), contains('s1'));
    });
  });

  group('applyResults の streak / stats 更新', () {
    test('正解で streak が増え、不正解で 0 にリセットされる', () async {
      final repo = StorageRepository();
      await repo.init();

      await repo.applyResults([(no: 1, correct: true)]);
      await repo.applyResults([(no: 1, correct: true)]);
      var stats = repo.loadStats();
      expect(stats['1']!.attempts, 2);
      expect(stats['1']!.correct, 2);
      expect(stats['1']!.streak, 2);
      expect(stats['1']!.lastCorrect, isTrue);

      await repo.applyResults([(no: 1, correct: false)]);
      stats = repo.loadStats();
      expect(stats['1']!.attempts, 3);
      expect(stats['1']!.correct, 2);
      expect(stats['1']!.streak, 0);
      expect(stats['1']!.lastCorrect, isFalse);
    });

    test('getWrongQuestionNos は昇順で lastCorrect=false の問番号を返す', () async {
      final repo = StorageRepository();
      await repo.init();

      await repo.applyResults([
        (no: 5, correct: false),
        (no: 1, correct: false),
        (no: 3, correct: true),
      ]);

      expect(repo.getWrongQuestionNos(), [1, 5]);
    });

    test('summarizeStats の3指標が正しい', () async {
      final repo = StorageRepository();
      await repo.init();

      // 問1: 2回正解のみ -> everWrong 対象外、streak 2 -> streak2plus 対象。
      await repo.applyResults([(no: 1, correct: true)]);
      await repo.applyResults([(no: 1, correct: true)]);
      // 問2: 1回不正解のみ -> everWrong 対象、streak 0。
      await repo.applyResults([(no: 2, correct: false)]);
      // 問3: 正解1回のみ -> everWrong 対象外、streak 1 -> streak2plus 対象外。
      await repo.applyResults([(no: 3, correct: true)]);

      final summary = repo.summarizeStats();
      expect(summary.tracked, 3);
      expect(summary.everWrong, 1);
      expect(summary.streak2plus, 1);
    });
  });

  group('cme:current の型検証', () {
    test('saveCurrent / loadCurrent の往復', () async {
      final repo = StorageRepository();
      await repo.init();

      final current = CurrentSession(
        examId: '28',
        mode: QuizMode.review,
        startedAt: '2026-09-19T00:00:00.000Z',
        questionNos: [1, 2, 3],
        cursor: 1,
        answers: {
          1: [3, 4],
        },
      );
      await repo.saveCurrent(current);

      final loaded = await repo.loadCurrent();
      expect(loaded, isNotNull);
      expect(loaded!.examId, '28');
      expect(loaded.mode, QuizMode.review);
      expect(loaded.questionNos, [1, 2, 3]);
      expect(loaded.cursor, 1);
      expect(loaded.answers, current.answers);
    });

    test('不正な cme:current（型違い）は削除され null が返る', () async {
      SharedPreferences.setMockInitialValues({
        'cme:current': '{"examId": 123, "mode": "full"}',
      });
      final repo = StorageRepository();
      await repo.init();

      final loaded = await repo.loadCurrent();
      expect(loaded, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cme:current'), isNull);
    });

    test('壊れた JSON の cme:current は削除され null が返る', () async {
      SharedPreferences.setMockInitialValues({'cme:current': '{not json'});
      final repo = StorageRepository();
      await repo.init();

      final loaded = await repo.loadCurrent();
      expect(loaded, isNull);
    });

    test('clearCurrent で cme:current が消える', () async {
      final repo = StorageRepository();
      await repo.init();
      await repo.saveCurrent(
        CurrentSession(
          examId: '28',
          mode: QuizMode.full,
          startedAt: '2026-09-19T00:00:00.000Z',
          questionNos: const [1],
          cursor: 0,
          answers: const {},
        ),
      );
      await repo.clearCurrent();
      expect(await repo.loadCurrent(), isNull);
    });
  });

  group('破損データからの復旧（他キーに波及しない）', () {
    test('cme:sessions が壊れていても cme:stats は生き残る', () async {
      SharedPreferences.setMockInitialValues({
        'cme:sessions': '{not json',
        'cme:stats': '{"1": {"attempts": 1, "correct": 1, "lastCorrect": true, "lastAt": null, "streak": 1}}',
      });
      final repo = StorageRepository();
      await repo.init();

      expect(repo.loadSessions(), isEmpty);
      final stats = repo.loadStats();
      expect(stats['1']!.attempts, 1);
      expect(stats['1']!.streak, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cme:sessions'), '[]');
    });

    test('cme:stats が壊れていても cme:sessions は生き残る', () async {
      final validSession = _buildSession(
        id: 's1',
        finishedAt: '2026-09-19T00:00:00.000Z',
      );
      SharedPreferences.setMockInitialValues({
        'cme:sessions': jsonEncode([validSession.toJson()]),
        'cme:stats': '"not an object"',
      });
      final repo = StorageRepository();
      await repo.init();

      final stats = repo.loadStats();
      expect(stats, isEmpty);
      final sessions = repo.loadSessions();
      expect(sessions, hasLength(1));
      expect(sessions.first.id, 's1');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cme:stats'), '{}');
    });

    test('cme:stats の一部エントリが壊れていても正常なエントリは生きる', () async {
      SharedPreferences.setMockInitialValues({
        'cme:stats': '{"1":{"attempts":1,"correct":1,"lastCorrect":true,"lastAt":null,"streak":1},"2":"garbage"}',
      });
      final repo = StorageRepository();
      await repo.init();

      final stats = repo.loadStats();
      expect(stats.containsKey('2'), isFalse);
      expect(stats['1']!.attempts, 1);
      expect(repo.summarizeStats().tracked, 1);
      expect(repo.getWrongQuestionNos(), isEmpty);
    });

    test('cme:stats のエントリでフィールドが欠落していても既定値で補完される', () async {
      SharedPreferences.setMockInitialValues({
        'cme:stats': '{"1":{"attempts":1,"correct":1}}',
      });
      final repo = StorageRepository();
      await repo.init();

      final stats = repo.loadStats();
      expect(stats['1']!.attempts, 1);
      expect(stats['1']!.lastCorrect, isFalse);
      expect(stats['1']!.streak, 0);
      expect(repo.summarizeStats().tracked, 1);
      // lastCorrect は「フィールド欠落」であり、移植元の厳密比較
      // （=== false）では対象外。loadStats の既定値フォールバックとは異なる。
      expect(repo.getWrongQuestionNos(), isEmpty);
    });

    test('applyResults は型違いの既存エントリを初期値扱いで復旧できる', () async {
      SharedPreferences.setMockInitialValues({
        'cme:stats': '{"3":{"attempts":"x"}}',
      });
      final repo = StorageRepository();
      await repo.init();

      await repo.applyResults([(no: 3, correct: true)]);

      final stats = repo.loadStats();
      expect(stats['3']!.attempts, 1);
      expect(stats['3']!.correct, 1);
      expect(stats['3']!.streak, 1);
    });

    test('cme:stats の非数値キーは getWrongQuestionNos で除外される', () async {
      SharedPreferences.setMockInitialValues({
        'cme:stats': '{"abc":{"attempts":1,"correct":0,"lastCorrect":false,"lastAt":null,"streak":0}}',
      });
      final repo = StorageRepository();
      await repo.init();

      expect(repo.getWrongQuestionNos(), isEmpty);
    });

    test('getWrongQuestionNos は lastCorrect が boolean の false のときだけ対象にする（移植元の === false と1:1）', () async {
      final cases = <String, dynamic>{
        '1': <String, dynamic>{'attempts': 1, 'correct': 0}, // フィールド欠落
        '2': <String, dynamic>{
          'attempts': 1,
          'correct': 0,
          'lastCorrect': null,
        },
        '3': <String, dynamic>{
          'attempts': 1,
          'correct': 0,
          'lastCorrect': 'false',
        },
        '4': <String, dynamic>{'attempts': 1, 'correct': 0, 'lastCorrect': 0},
        '5': <String, dynamic>{
          'attempts': 1,
          'correct': 1,
          'lastCorrect': true,
        },
        '6': <String, dynamic>{
          'attempts': 1,
          'correct': 0,
          'lastCorrect': false,
        },
      };
      SharedPreferences.setMockInitialValues({'cme:stats': jsonEncode(cases)});
      final repo = StorageRepository();
      await repo.init();

      expect(repo.getWrongQuestionNos(), [6]);
    });

    test('cme:sessions の要素がフィールド欠落でも他の要素には波及しない', () async {
      final validSession = _buildSession(
        id: 's1',
        finishedAt: '2026-09-19T00:00:00.000Z',
      );
      SharedPreferences.setMockInitialValues({
        'cme:sessions': jsonEncode([
          {'id': 'bad'},
          validSession.toJson(),
        ]),
      });
      final repo = StorageRepository();
      await repo.init();

      final sessions = repo.loadSessions();
      expect(sessions, hasLength(1));
      expect(sessions.first.id, 's1');
    });

    test('cme:current の answers キーが非数値でも例外を投げず削除される', () async {
      SharedPreferences.setMockInitialValues({
        'cme:current': '{"examId":"28","mode":"full","startedAt":"x","questionNos":[1],"cursor":0,"answers":{"a":[1]}}',
      });
      final repo = StorageRepository();
      await repo.init();

      expect(await repo.loadCurrent(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cme:current'), isNull);
    });

    test('cme:current の questionNos の要素型が違っても例外を投げず削除される', () async {
      SharedPreferences.setMockInitialValues({
        'cme:current': '{"examId":"28","mode":"full","startedAt":"x","questionNos":["a"],"cursor":0,"answers":{}}',
      });
      final repo = StorageRepository();
      await repo.init();

      expect(await repo.loadCurrent(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cme:current'), isNull);
    });
  });

  group('clearAll', () {
    test('4キーすべて削除され、スキーマバージョンが再作成される', () async {
      final repo = StorageRepository();
      await repo.init();

      await repo.saveSession(
        _buildSession(id: 's1', finishedAt: '2026-09-19T00:00:00.000Z'),
      );
      await repo.applyResults([(no: 1, correct: true)]);
      await repo.saveCurrent(
        CurrentSession(
          examId: '28',
          mode: QuizMode.full,
          startedAt: '2026-09-19T00:00:00.000Z',
          questionNos: const [1],
          cursor: 0,
          answers: const {},
        ),
      );

      await repo.clearAll();

      expect(repo.loadSessions(), isEmpty);
      expect(repo.loadStats(), isEmpty);
      expect(await repo.loadCurrent(), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cme:v'), '1');
    });
  });

  group('ensureSchemaVersion', () {
    test('未設定の場合に schemaVersion が書き込まれる', () async {
      final repo = StorageRepository();
      await repo.init();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cme:v'), '1');
    });

    test('壊れた cme:v も schemaVersion で書き直される', () async {
      SharedPreferences.setMockInitialValues({'cme:v': '{not json'});
      final repo = StorageRepository();
      await repo.init();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cme:v'), '1');
    });
  });
}
