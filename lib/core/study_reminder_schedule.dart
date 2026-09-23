/// 学習リマインドの間隔。学習しない限りこの間隔で繰り返し通知する。
const studyReminderInterval = Duration(hours: 24);

/// 次に学習リマインドを出す時刻。基準（最終学習時刻、無ければ初回起動時刻）
/// + 24h を起点に、[now] より後に来る最初の「起点 + 24h*n」を返す。
DateTime nextStudyReminderAt({
  required DateTime? lastStudyAt,
  required DateTime firstLaunchAt,
  required DateTime now,
}) {
  final first = (lastStudyAt ?? firstLaunchAt).add(studyReminderInterval);
  if (first.isAfter(now)) return first;
  final elapsed = now.difference(first).inMicroseconds;
  final steps = elapsed ~/ studyReminderInterval.inMicroseconds + 1;
  return first.add(studyReminderInterval * steps);
}
