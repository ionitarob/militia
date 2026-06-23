import 'package:flutter/cupertino.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import '../widgets/liti_chat_overlay.dart';
import 'login_screen.dart';
import '../main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  String _status = '';
  double? _downloadProgress; // null = hidden, 0–1 = visible

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Cubic(0.23, 1.0, 0.32, 1.0),
      ),
    );

    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward().then((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    _setStatus('Buscando actualizaciones...');

    UpdateInfo? info;
    try {
      info = await UpdateService().checkForUpdate();
    } catch (_) {
      info = null;
    }

    if (!mounted) return;

    if (info != null) {
      final doUpdate = await _showUpdateDialog(info);
      if (!mounted) return;
      if (doUpdate == true) {
        await _runUpdate(info);
        return; // exit(0) is called inside — we never reach here
      }
    }

    _setStatus('');
    await _proceed();
  }

  Future<bool?> _showUpdateDialog(UpdateInfo info) {
    return showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Nueva versión disponible (${info.version})'),
        content: info.notes.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(info.notes),
              )
            : null,
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Más tarde'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Actualizar ahora'),
          ),
        ],
      ),
    );
  }

  Future<void> _runUpdate(UpdateInfo info) async {
    _setStatus('Descargando actualización ${info.version}...');
    if (mounted) setState(() => _downloadProgress = 0.0);

    await UpdateService().downloadAndApply(
      info,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _downloadProgress = p;
            if (p >= 0.95) _status = 'Instalando...';
          });
        }
      },
    );
    // If we reach here (shouldn't normally), fall through to _proceed.
    if (mounted) {
      setState(() => _downloadProgress = null);
      _setStatus('');
    }
    await _proceed();
  }

  Future<void> _proceed() async {
    final restored = await Future.wait([
      AuthService().tryRestoreSession(),
      Future.delayed(const Duration(milliseconds: 400)),
    ]);
    if (!mounted) return;

    await _ctrl.reverse();
    if (!mounted) return;

    final isLoggedIn = restored[0] as bool;
    Navigator.of(context).pushReplacement(
      _fadeRoute(isLoggedIn ? const AppShell() : const LoginScreen()),
    );
    if (isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        litiChat.authChanged();
        litiChat.restoreSession();
      });
    }
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      child: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) => Opacity(
            opacity: _opacity.value,
            child: Transform.scale(
              scale: _scale.value,
              child: child,
            ),
          ),
          child: SizedBox(
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _AppLogo(),
                const SizedBox(height: 32),

                // Status line
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _status.isNotEmpty ? 1.0 : 0.0,
                  child: Text(
                    _status,
                    style: const TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.secondaryLabel,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Download progress bar
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _downloadProgress != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _ProgressBar(value: _downloadProgress!),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Progress bar ──────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final double value; // 0–1
  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 4,
        child: LayoutBuilder(
          builder: (ctx, constraints) => Stack(
            children: [
              Container(color: const Color(0xFFE2E8F0)),
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: constraints.maxWidth * value.clamp(0.0, 1.0),
                color: const Color(0xFF2563EB),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── App logo (unchanged) ──────────────────────────────────────────────────────

class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1C3461), Color(0xFF0F1F3D)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F1F3D).withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  height: 36,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x18FFFFFF), Color(0x00FFFFFF)],
                    ),
                  ),
                ),
              ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'IM',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFFFFFF),
                        letterSpacing: -1.2,
                        height: 1.0,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 3),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'IMLiti',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F1F3D),
            letterSpacing: -1.0,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Inteligencia de Licitaciones TIC',
          style: TextStyle(
            fontSize: 13,
            color: CupertinoColors.secondaryLabel,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

PageRouteBuilder _fadeRoute(Widget page) => PageRouteBuilder(
      pageBuilder: (ctx, anim1, anim2) => page,
      transitionDuration: const Duration(milliseconds: 400),
      transitionsBuilder: (ctx, anim, secAnim, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
    );
