import 'package:flutter/material.dart';

/// 移植元 body { max-width: 640px; margin-inline: auto; } 相当。
/// macOS デスクトップの広い画面でも本文が 640px で中央に来るようにする。
class CenteredBody extends StatelessWidget {
  const CenteredBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: child,
      ),
    );
  }
}
