import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 出典の媒体名。フッタと年度カードの出典表示（home_screen.dart）で共有する。
const kExamSourceMediaName = 'ケアマネージャー試験過去問題集';

/// 移植元 .footer-credit 相当。`</main>` の後ろに続く通常フロー要素であり、
/// 常時固定のオーバーレイではない。各画面がスクロール末尾に自分で置く。
/// 下部固定バーを持つ画面では [hasBottomBar] を true にして、
/// 移植元 body:has(.bottom-bar) .footer-credit の margin-bottom を再現する。
class FooterCredit extends StatelessWidget {
  const FooterCredit({super.key, this.hasBottomBar = false});

  final bool hasBottomBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.appTokens;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        24,
        16,
        24 +
            safeAreaBottom +
            (hasBottomBar ? tokens.barHeight + safeAreaBottom : 0),
      ),
      child: Center(
        child: Text(
          '出典: $kExamSourceMediaName ／ 解答・解説: 学校法人 藤仁館学園',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall,
        ),
      ),
    );
  }
}
