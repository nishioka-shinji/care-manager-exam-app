import 'package:flutter/widgets.dart';

/// 画面名の定義。各画面とルーティングの両方がここを一方向に参照する。
/// 画面が App を import し返すと依存が循環し、画面単体テストが
/// 他の画面まで引き込むため、定数だけを切り出している。
class Routes {
  const Routes._();

  static const home = '/';
  static const quiz = '/quiz';
  static const result = '/result';
  static const history = '/history';
}

/// 画面が RouteAware で「上に被せた画面から戻ってきた」を検知するための
/// 共有 RouteObserver。App の MaterialApp.navigatorObservers に登録する。
/// routes.dart に置くことで画面側は app.dart を import せずに済む。
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();
