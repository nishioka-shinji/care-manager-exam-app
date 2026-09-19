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
