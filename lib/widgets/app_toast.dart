import 'package:flutter/material.dart';

/// 移植元 .toast 相当の一時表示トースト。影あり・やや暗い半透明背景は
/// 移植元の rgba(20,20,26,0.9) をそのまま踏襲する（テーマの明暗に関わらず固定）。
class AppToast {
  AppToast._();

  static void show(
    BuildContext context,
    String message, {
    // 移植元 app.js の toast() 既定値（ms = 1600）に合わせる。
    Duration duration = const Duration(milliseconds: 1600),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (context) => _ToastOverlay(message: message));
    overlay.insert(entry);
    Future.delayed(duration, () => entry.remove());
  }
}

class _ToastOverlay extends StatelessWidget {
  const _ToastOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 0,
      right: 0,
      // 移植元の #toast-root: bottom: bar-h + 16px + safe-area-inset-bottom。
      bottom: 64 + 16 + bottomInset,
      child: Center(
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xE6141419),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 14.4),
              softWrap: false,
            ),
          ),
        ),
      ),
    );
  }
}
