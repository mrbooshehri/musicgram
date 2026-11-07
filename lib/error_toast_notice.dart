import 'package:flutter/material.dart';

import 'app_snack_bar.dart';

/// Reports an asynchronous page error without occupying content space.
class ErrorToastNotice extends StatefulWidget {
  const ErrorToastNotice({super.key, required this.message});
  final String message;

  @override
  State<ErrorToastNotice> createState() => _ErrorToastNoticeState();
}

class _ErrorToastNoticeState extends State<ErrorToastNotice> {
  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void didUpdateWidget(covariant ErrorToastNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) _show();
  }

  void _show() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        AppSnackBar(kind: AppNoticeKind.error, content: Text(widget.message)),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
