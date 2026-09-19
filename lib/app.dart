import 'package:flutter/material.dart';

import 'features/home/home_screen.dart';
import 'features/quiz/quiz_screen.dart';
import 'routes.dart';
import 'theme/app_theme.dart';
import 'widgets/centered_body.dart';
import 'widgets/footer_credit.dart';

/// アプリ全体の状態を持つ入れ物。exam / stats / sessions / current の保持は
/// 後続タスクが埋める。このタスクでは ChangeNotifier の器だけ用意する。
class AppState extends ChangeNotifier {}

/// 素の Navigator + onGenerateRoute によるルーティング。
/// go_router 等の外部パッケージは使わない方針（CLAUDE.md 依存方針）。
class App extends StatelessWidget {
  const App({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return MaterialApp(
          title: 'ケアマネ過去問',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.system,
          onGenerateRoute: _onGenerateRoute,
          builder: (context, child) =>
              AppShell(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }

  static Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case Routes.quiz:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const QuizScreen(),
        );
      case Routes.result:
        final sessionId = settings.arguments as String?;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ResultPlaceholderScreen(sessionId: sessionId),
        );
      case Routes.history:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const HistoryPlaceholderScreen(),
        );
      case Routes.home:
      default:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const HomeScreen(),
        );
    }
  }
}

/// 画面本体を中央寄せするだけのシェル。フッタは常時固定のオーバーレイにせず
/// [FooterCredit] として各画面がスクロール末尾に置く（移植元は</main>の後ろの
/// 通常フロー要素であり、下部固定バーとは padding/margin で縦に逃げる関係）。
///
/// Navigator（= child）を Column 等で圧縮すると、配下の Scaffold/MediaQuery.size が
/// 画面全体より縮んでしまい、Navigator が持つ Overlay（ConfirmSheet/AppToast の
/// 表示先）も画面下端まで届かなくなる。そのため child をそのまま画面全体に渡す。
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CenteredBody(child: child);
  }
}

class ResultPlaceholderScreen extends StatelessWidget {
  const ResultPlaceholderScreen({super.key, this.sessionId});

  final String? sessionId;

  @override
  Widget build(BuildContext context) {
    return _PlaceholderScreen(
      title: '結果',
      route: Routes.result,
      subtitle: sessionId == null ? null : 'sessionId: $sessionId',
    );
  }
}

class HistoryPlaceholderScreen extends StatelessWidget {
  const HistoryPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderScreen(title: '履歴', route: Routes.history);
  }
}

/// 各画面の中身は後続タスクが作る。ここでは遷移が通ることだけを確認できればよい。
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({
    required this.title,
    required this.route,
    this.subtitle,
  });

  final String title;
  final String route;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      // 出典クレジットは各画面がスクロール末尾に置く通常フロー要素（F4）。
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('$title 画面（プレースホルダ）'),
          if (subtitle != null) Text(subtitle!),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('戻る'),
          ),
          const FooterCredit(),
        ],
      ),
    );
  }
}
