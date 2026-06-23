import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../widgets/liti_chat_overlay.dart';
import '../main.dart';
import 'register_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _navy      = Color(0xFF0F1F3D); // deep navy — logo fill, primary text
const _navyGrad  = Color(0xFF1C3461); // gradient stop for logo mark
const _blue      = Color(0xFF2563EB); // action blue — button, focus ring
const _blueDark  = Color(0xFF1E40AF); // button gradient bottom
const _gold      = Color(0xFFF59E0B); // amber accent — single strategic dot
const _ink       = Color(0xFF111827); // body text
const _muted     = Color(0xFF6B7280); // secondary text, placeholders
const _bgPage    = Color(0xFFF1F4F9); // page background (subtle cool-blue tint)
const _bgCard    = Color(0xFFFFFFFF); // card surface
const _bgInput   = Color(0xFFF9FAFB); // input fill
const _border    = Color(0xFFE5E7EB); // input default border
const _errorRed  = Color(0xFFDC2626); // error text

// ── Screen ────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _emailCtrl     = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  final _emailFocus    = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _rememberMe      = true;
  bool _loading         = false;
  String? _error;

  // Card entrance: slides up + fades
  late final AnimationController _cardCtrl;
  late final Animation<double>  _cardOpacity;
  late final Animation<Offset>  _cardSlide;

  // Logo spring pop (starts after card)
  late final AnimationController _logoCtrl;
  late final Animation<double>  _logoScale;

  // Form element stagger (email, password, remember+button)
  late final AnimationController _staggerCtrl;
  late final List<Animation<double>> _sFade;
  late final List<Animation<Offset>> _sSlide;

  // Error shake
  late final AnimationController _shakeCtrl;
  late final Animation<double>   _shake;

  @override
  void initState() {
    super.initState();

    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
    _cardOpacity = CurvedAnimation(
      parent: _cardCtrl,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    );
    _cardSlide = Tween<Offset>(begin: const Offset(0, 0.055), end: Offset.zero).animate(
      CurvedAnimation(parent: _cardCtrl, curve: const Cubic(0.23, 1.0, 0.32, 1.0)),
    );

    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    _logoScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      // slight overshoot spring
      CurvedAnimation(parent: _logoCtrl, curve: const Cubic(0.34, 1.56, 0.64, 1.0)),
    );

    const n = 3;
    _staggerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
    _sFade  = List.generate(n, (i) => Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _staggerCtrl,
        curve: Interval(i * 0.14, i * 0.14 + 0.52, curve: Curves.easeOut),
      ),
    ));
    _sSlide = List.generate(n, (i) => Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _staggerCtrl,
        curve: Interval(i * 0.14, i * 0.14 + 0.52, curve: Curves.easeOut),
      ),
    ));

    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0,  end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10,  end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8,  end:  8), weight: 2),
      TweenSequenceItem(tween: Tween(begin:  8,  end:  0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));

    AuthService().savedEmail.then((email) {
      if (mounted && email != null) _emailCtrl.text = email;
    });

    // Sequence: card → logo (80ms gap) → stagger (120ms gap)
    _cardCtrl.forward().then((_) {
      if (!mounted) return;
      _logoCtrl.forward();
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _staggerCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _cardCtrl.dispose();
    _logoCtrl.dispose();
    _staggerCtrl.dispose();
    _shakeCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() { _loading = true; _error = null; });

    try {
      await AuthService().login(email: email, password: password, rememberMe: _rememberMe);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder:      (ctx, a1, a2) => const AppShell(),
        transitionDuration: const Duration(milliseconds: 380),
        transitionsBuilder: (ctx, anim, secAnim, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        litiChat.authChanged();
        litiChat.restoreSession();
      });
    } catch (e) {
      HapticFeedback.heavyImpact();
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      _shakeCtrl.forward(from: 0);
    }
  }

  Widget _s(int i, Widget child) => FadeTransition(
    opacity: _sFade[i],
    child: SlideTransition(position: _sSlide[i], child: child),
  );

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: _bgPage,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle dot-grid pattern on the page background
          RepaintBoundary(child: CustomPaint(painter: _DotGridPainter())),

          SafeArea(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: FadeTransition(
                    opacity: _cardOpacity,
                    child: SlideTransition(
                      position: _cardSlide,
                      child: _LoginCard(
                        logoCtrl:      _logoCtrl,
                        logoScale:     _logoScale,
                        shake:         _shake,
                        error:         _error,
                        loading:       _loading,
                        obscure:       _obscurePassword,
                        rememberMe:    _rememberMe,
                        emailCtrl:     _emailCtrl,
                        passwordCtrl:  _passwordCtrl,
                        emailFocus:    _emailFocus,
                        passwordFocus: _passwordFocus,
                        onToggleObscure: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                        onToggleRemember: (v) =>
                            setState(() => _rememberMe = v),
                        onSubmit: _submit,
                        staggered: _s,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _LoginCard extends StatelessWidget {
  final AnimationController logoCtrl;
  final Animation<double>   logoScale;
  final Animation<double>   shake;
  final String?             error;
  final bool                loading;
  final bool                obscure;
  final bool                rememberMe;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final FocusNode           emailFocus;
  final FocusNode           passwordFocus;
  final VoidCallback        onToggleObscure;
  final ValueChanged<bool>  onToggleRemember;
  final VoidCallback        onSubmit;
  final Widget Function(int, Widget) staggered;

  const _LoginCard({
    required this.logoCtrl,
    required this.logoScale,
    required this.shake,
    required this.error,
    required this.loading,
    required this.obscure,
    required this.rememberMe,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.emailFocus,
    required this.passwordFocus,
    required this.onToggleObscure,
    required this.onToggleRemember,
    required this.onSubmit,
    required this.staggered,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F1F3D).withValues(alpha: 0.09),
            blurRadius: 48,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF0F1F3D).withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo
            Center(
              child: AnimatedBuilder(
                animation: logoCtrl,
                builder: (_, child) => Transform.scale(
                  scale: logoScale.value,
                  child: child,
                ),
                child: const _LogoSection(),
              ),
            ),

            const SizedBox(height: 40),

            // Email
            staggered(0, _InputField(
              controller: emailCtrl,
              focusNode:  emailFocus,
              placeholder: 'Correo electrónico',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => passwordFocus.requestFocus(),
              prefixIcon: CupertinoIcons.mail,
            )),

            const SizedBox(height: 10),

            // Password (with shake)
            staggered(1, AnimatedBuilder(
              animation: shake,
              builder: (_, child) => Transform.translate(
                offset: Offset(shake.value, 0),
                child: child,
              ),
              child: _InputField(
                controller: passwordCtrl,
                focusNode:  passwordFocus,
                placeholder: 'Contraseña',
                obscureText: obscure,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmit(),
                prefixIcon: CupertinoIcons.lock,
                suffix: CupertinoButton(
                  padding: const EdgeInsets.only(right: 6),
                  minimumSize: Size.zero,
                  onPressed: onToggleObscure,
                  child: Icon(
                    obscure ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                    size: 17,
                    color: _muted,
                  ),
                ),
              ),
            )),

            // Error banner
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: error != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              CupertinoIcons.exclamationmark_circle_fill,
                              size: 13,
                              color: _errorRed,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              error!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: _errorRed,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            const SizedBox(height: 22),

            // Remember me + button
            staggered(2, Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      'Mantener sesión iniciada',
                      style: TextStyle(fontSize: 14, color: _muted),
                    ),
                    const Spacer(),
                    CupertinoSwitch(
                      value: rememberMe,
                      activeTrackColor: _blue,
                      onChanged: onToggleRemember,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                _LoginButton(loading: loading, onTap: onSubmit),
              ],
            )),

            const SizedBox(height: 24),

            // Register link
            Center(
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () => Navigator.of(context, rootNavigator: true).push(
                  CupertinoPageRoute(builder: (_) => const RegisterScreen()),
                ),
                child: const Text(
                  '¿No tienes cuenta? Crear cuenta',
                  style: TextStyle(fontSize: 13, color: _blue),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Footer
            const Center(
              child: Text(
                'Ingram Micro · Inteligencia de Licitaciones',
                style: TextStyle(
                  fontSize: 11,
                  color: _muted,
                  letterSpacing: 0.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Logo section ──────────────────────────────────────────────────────────────

class _LogoSection extends StatelessWidget {
  const _LogoSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LogoMark(),
        const SizedBox(height: 18),
        const Text(
          'IMLiti',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: _navy,
            letterSpacing: -1.0,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Inteligencia de Licitaciones TIC',
          style: TextStyle(
            fontSize: 12.5,
            color: _muted,
            letterSpacing: 0.1,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _LogoMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navyGrad, _navy],
        ),
        borderRadius: BorderRadius.circular(17),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Top-gloss sheen
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0x18FFFFFF),
                    const Color(0x00FFFFFF),
                  ],
                ),
              ),
            ),
          ),
          // Lettermark + gold period dot
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'IM',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFFFFFF),
                    letterSpacing: -1.2,
                    height: 1.0,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 3),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _gold,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Input field ───────────────────────────────────────────────────────────────

class _InputField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffix;

  const _InputField({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    this.keyboardType = TextInputType.text,
    required this.textInputAction,
    this.onSubmitted,
    this.obscureText = false,
    this.prefixIcon,
    this.suffix,
  });

  @override
  State<_InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<_InputField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _bgInput,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: _focused ? _blue : _border,
          width: _focused ? 1.5 : 1.0,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: _blue.withValues(alpha: 0.11),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Row(
        children: [
          if (widget.prefixIcon != null) ...[
            const SizedBox(width: 13),
            Icon(
              widget.prefixIcon,
              size: 16,
              color: _focused ? _blue : _muted,
            ),
            const SizedBox(width: 10),
          ] else
            const SizedBox(width: 14),
          Expanded(
            child: CupertinoTextField(
              controller:      widget.controller,
              focusNode:       widget.focusNode,
              placeholder:     widget.placeholder,
              keyboardType:    widget.keyboardType,
              textInputAction: widget.textInputAction,
              onSubmitted:     widget.onSubmitted,
              obscureText:     widget.obscureText,
              autocorrect:     false,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: const BoxDecoration(),
              style: const TextStyle(
                fontSize: 15,
                color: _ink,
                fontWeight: FontWeight.w400,
              ),
              placeholderStyle: const TextStyle(
                fontSize: 15,
                color: _muted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          if (widget.suffix != null)
            widget.suffix!
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }
}

// ── Login button ──────────────────────────────────────────────────────────────

class _LoginButton extends StatefulWidget {
  final bool loading;
  final VoidCallback onTap;
  const _LoginButton({required this.loading, required this.onTap});

  @override
  State<_LoginButton> createState() => _LoginButtonState();
}

class _LoginButtonState extends State<_LoginButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: _pressed
            ? const Duration(milliseconds: 80)
            : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: widget.loading ? 0.75 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_blue, _blueDark],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: widget.loading
                  ? []
                  : [
                      BoxShadow(
                        color: _blue.withValues(alpha: 0.32),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: widget.loading
                    ? const CupertinoActivityIndicator(color: Color(0xFFFFFFFF))
                    : const Text(
                        'Iniciar sesión',
                        key: ValueKey('label'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFFFFFF),
                          letterSpacing: -0.2,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Dot-grid background painter ───────────────────────────────────────────────

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB8C4D8).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    const spacing = 22.0;
    const radius  = 1.0;

    // Offset the grid slightly so dots don't touch the very edge
    const offset = spacing / 2;
    for (double x = offset; x < size.width; x += spacing) {
      for (double y = offset; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
