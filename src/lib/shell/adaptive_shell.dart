import 'package:flutter/material.dart';

import 'desktop_shell.dart';
import 'mobile_shell.dart';

// Below this width the app uses the mobile bottom-nav layout.
// At or above it the desktop persistent-sidebar layout is used.
const double kDesktopBreakpoint = 600;

class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= kDesktopBreakpoint
        ? DesktopShell(child: child)
        : MobileShell(child: child);
  }
}
