import 'package:flutter/material.dart';

import 'app_diagnostics.dart';

enum AppNoticeKind { info, success, warning, error }

class AppSnackBar extends SnackBar {
  factory AppSnackBar({
    Key? key,
    required Widget content,
    AppNoticeKind kind = AppNoticeKind.info,
  }) {
    if (kind == AppNoticeKind.error) {
      AppDiagnostics.recordError(
        content is Text
            ? content.data ?? 'An error occurred'
            : 'An error occurred',
      );
    }
    return AppSnackBar._(key: key, content: content, kind: kind);
  }

  AppSnackBar._({
    super.key,
    required Widget content,
    required AppNoticeKind kind,
  }) : super(
         behavior: SnackBarBehavior.floating,
         backgroundColor: switch (kind) {
           AppNoticeKind.info => const Color(0xFF155A96),
           AppNoticeKind.success => const Color(0xFF226B35),
           AppNoticeKind.warning => const Color(0xFF805500),
           AppNoticeKind.error => const Color(0xFFAE2424),
         },
         content: DefaultTextStyle.merge(
           style: const TextStyle(color: Colors.white),
           child: Row(
             children: [
               ExcludeSemantics(
                 child: Builder(
                   builder: (context) => Icon(switch (kind) {
                     AppNoticeKind.info => Icons.info_outline,
                     AppNoticeKind.success => Icons.check_circle_outline,
                     AppNoticeKind.warning => Icons.warning_amber_rounded,
                     AppNoticeKind.error => Icons.error_outline,
                   }, color: Colors.white),
                 ),
               ),
               const SizedBox(width: 12),
               Expanded(child: content),
             ],
           ),
         ),
       );
}
