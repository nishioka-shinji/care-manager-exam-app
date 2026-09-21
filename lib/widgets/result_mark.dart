import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 移植元 .quiz-mark--answer / --selected 相当。結果画面と演習画面（drill）
/// の答え合わせ後で見た目を共有する。WCAG AA を満たすため塗りつぶし背景 +
/// on* トークンの濃色文字にする（style.css の badge と同型）。
class ResultMark extends StatelessWidget {
  const ResultMark({super.key, required this.label, required this.isAnswer});

  final String label;
  final bool isAnswer;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);
    final background = isAnswer ? tokens.ok : theme.colorScheme.primary;
    final foreground = isAnswer ? tokens.onOk : theme.colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
