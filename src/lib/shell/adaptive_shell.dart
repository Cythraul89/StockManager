import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/settings/nextcloud_sync_provider.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

// Below this width the app uses the mobile bottom-nav layout.
// At or above it the desktop persistent-sidebar layout is used.
const double kDesktopBreakpoint = 600;

class AdaptiveShell extends ConsumerStatefulWidget {
  const AdaptiveShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends ConsumerState<AdaptiveShell> {
  @override
  Widget build(BuildContext context) {
    ref.listen<NextcloudSyncState>(nextcloudSyncProvider, (prev, next) {
      if (prev?.pendingRestore == null && next.pendingRestore != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Re-read current state — may have been cleared already by the
          // inline dialog inside NextcloudSettingsScreen._save().
          final current = ref.read(nextcloudSyncProvider);
          if (current.pendingRestore == null) return;
          // Don't overlap with the inline dialog/banner on the Nextcloud
          // settings screen — it handles the decision flow there.
          final location = GoRouterState.of(context).uri.path;
          if (!location.startsWith('/settings/nextcloud')) {
            _showRestoreDialog(current.pendingRestore!);
          }
        });
      }
    });

    final width = MediaQuery.sizeOf(context).width;
    return width >= kDesktopBreakpoint
        ? DesktopShell(child: widget.child)
        : MobileShell(child: widget.child);
  }

  Future<void> _showRestoreDialog(RemoteBackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Server backup found'),
        content: Text(
          'A backup from '
          '${backup.backupDate.toIso8601String().substring(0, 10)} '
          'was found on your Nextcloud server.\n\n'
          'Restore from server now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore from server'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      await ref.read(nextcloudSyncProvider.notifier).restoreFromRemote();
    } else {
      ref.read(nextcloudSyncProvider.notifier).dismissRestore();
    }
  }
}
