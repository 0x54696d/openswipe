import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:photo_manager/photo_manager.dart';

enum PermissionStatus {
  unknown,
  granted,
  limited,
  denied,
  permanentlyDenied,
  restricted,
}

class PermissionService {
  Future<PermissionStatus> check() async {
    final result = await PhotoManager.requestPermissionExtend();
    return _map(result);
  }

  Future<PermissionStatus> request() async {
    final result = await PhotoManager.requestPermissionExtend();
    return _map(result);
  }

  Future<void> openSettings() async {
    await PhotoManager.openSetting();
  }

  PermissionStatus _map(PermissionState result) {
    return switch (result) {
      PermissionState.authorized => PermissionStatus.granted,
      PermissionState.limited => PermissionStatus.limited,
      PermissionState.denied => PermissionStatus.denied,
      PermissionState.restricted => PermissionStatus.restricted,
      _ => PermissionStatus.permanentlyDenied,
    };
  }
}

class PermissionGate extends StatefulWidget {
  final Widget child;
  const PermissionGate({required this.child, super.key});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  final _service = PermissionService();
  PermissionStatus _status = PermissionStatus.unknown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final status = await _service.check();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _request() async {
    final status = await _service.request();
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_status) {
      PermissionStatus.unknown => const _LoadingScreen(),
      PermissionStatus.granted => widget.child,
      PermissionStatus.limited => widget.child,
      PermissionStatus.denied => _DeniedScreen(onRequest: _request),
      PermissionStatus.permanentlyDenied => _PermanentlyDeniedScreen(
        onOpenSettings: _service.openSettings,
      ),
      PermissionStatus.restricted => const _RestrictedScreen(),
    };
  }
}

// ── Screens ───────────────────────────────────────────────────────────────────

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _DeniedScreen extends StatelessWidget {
  final VoidCallback onRequest;
  const _DeniedScreen({required this.onRequest});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.image, size: 64),
              const SizedBox(height: 24),
              Text(
                'Photo access required',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'OpenSwipe needs access to your photo library to help you clean it up. Your photos never leave your device.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: onRequest,
                child: const Text('Grant access'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermanentlyDeniedScreen extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _PermanentlyDeniedScreen({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.lock, size: 64),
              const SizedBox(height: 24),
              Text(
                'Permission blocked',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Photo access has been denied. To use OpenSwipe, enable photo access in your device settings.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: onOpenSettings,
                child: const Text('Open settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestrictedScreen extends StatelessWidget {
  const _RestrictedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.ban, size: 64),
              const SizedBox(height: 24),
              Text(
                'Access restricted',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Photo library access is restricted on this device, likely due to parental controls. OpenSwipe cannot be used.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
