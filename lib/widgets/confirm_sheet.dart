import 'dart:async';

import 'package:flutter/material.dart';

import 'app_button.dart';

/// 移植元 .sheet 相当の自前ボトムシート。showDialog やネイティブの確認ダイアログは
/// 使わず、Overlay に自分でバックドロップとパネルを描いてスライドインさせる。
/// ホーム・演習・履歴の 3 画面から呼べる汎用の確認 UI として作る。
class ConfirmSheet {
  ConfirmSheet._();

  /// シートを表示し、確定なら true・キャンセル/バックドロップタップなら false で解決する。
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = '確定',
    String cancelLabel = 'キャンセル',
  }) {
    final completer = Completer<bool>();
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;

    void close(bool result) {
      if (!completer.isCompleted) completer.complete(result);
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (context) => _ConfirmSheetOverlay(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        onConfirm: () => close(true),
        onCancel: () => close(false),
      ),
    );

    overlay.insert(entry);
    return completer.future;
  }
}

class _ConfirmSheetOverlay extends StatefulWidget {
  const _ConfirmSheetOverlay({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  State<_ConfirmSheetOverlay> createState() => _ConfirmSheetOverlayState();
}

class _ConfirmSheetOverlayState extends State<_ConfirmSheetOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onCancel,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.4 * t),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FractionalTranslation(
                translation: Offset(0, 1 - t),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: screenHeight * 0.7),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.message,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: AppButton(
                                  label: widget.cancelLabel,
                                  variant: AppButtonVariant.ghost,
                                  onPressed: widget.onCancel,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppButton(
                                  label: widget.confirmLabel,
                                  variant: AppButtonVariant.primary,
                                  onPressed: widget.onConfirm,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
