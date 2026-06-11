import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../api/client.dart';
import '../services/auth_service.dart';
import '../main.dart';

// ── Design tokens (matches login_screen.dart) ─────────────────────────────────
const _navy      = Color(0xFF0F1F3D);
const _navyGrad  = Color(0xFF1C3461);
const _blue      = Color(0xFF2563EB);
const _blueDark  = Color(0xFF1E40AF);
const _gold      = Color(0xFFF59E0B);
const _ink       = Color(0xFF111827);
const _muted     = Color(0xFF6B7280);
const _bgPage    = Color(0xFFF1F4F9);
const _bgCard    = Color(0xFFFFFFFF);
const _bgInput   = Color(0xFFF9FAFB);
const _border    = Color(0xFFE5E7EB);
const _errorRed  = Color(0xFFDC2626);
const _green     = Color(0xFF16A34A);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with TickerProviderStateMixin {
  // Step 1 fields
  final _emailCtrl    = TextEditingController();
  final _nombreCtrl   = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus   = FocusNode();
  final _nombreFocus  = FocusNode();
  final _passFocus    = FocusNode();
  String _role = 'ventas';
  bool _obscurePassword = true;

  // Step 2 fields
  final _otpCtrls = List.generate(6, (_) => TextEditingController());
  final _otpFocus = List.generate(6, (_) => FocusNode());

  int _step = 1; // 1 = form, 2 = otp, 3 = done/pending
  int _requestId = 0;
  bool _loading = false;
  String? _error;

  // Card entrance
  late final AnimationController _cardCtrl;
  late final Animation<double>   _cardOpacity;
  late final Animation<Offset>   _cardSlide;

  @override
  void initState() {
    super.initState();
    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
    _cardOpacity = CurvedAnimation(parent: _cardCtrl, curve: const Interval(0.0, 0.65, curve: Curves.easeOut));
    _cardSlide = Tween<Offset>(begin: const Offset(0, 0.055), end: Offset.zero).animate(
      CurvedAnimation(parent: _cardCtrl, curve: const Cubic(0.23, 1.0, 0.32, 1.0)),
    );
    _cardCtrl.forward();
  }

  @override
  void dispose() {
    _cardCtrl.dispose();
    _emailCtrl.dispose(); _nombreCtrl.dispose(); _passwordCtrl.dispose();
    _emailFocus.dispose(); _nombreFocus.dispose(); _passFocus.dispose();
    for (final c in _otpCtrls) { c.dispose(); }
    for (final f in _otpFocus) { f.dispose(); }
    super.dispose();
  }

  Future<void> _submitStep1() async {
    if (_loading) return;
    final email    = _emailCtrl.text.trim();
    final nombre   = _nombreCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || nombre.isEmpty || password.isEmpty) {
      setState(() => _error = 'Rellena todos los campos');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() { _loading = true; _error = null; });
    try {
      final reqId = await ApiClient().registerRequest(
        email: email,
        nombre: nombre,
        password: password,
        role: _role,
      );
      setState(() { _requestId = reqId; _step = 2; _loading = false; });
    } catch (e) {
      HapticFeedback.heavyImpact();
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String get _otpValue => _otpCtrls.map((c) => c.text).join();

  Future<void> _submitStep2() async {
    if (_loading) return;
    final otp = _otpValue;
    if (otp.length < 6) {
      setState(() => _error = 'Introduce los 6 dígitos del código');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() { _loading = true; _error = null; });
    try {
      final result = await ApiClient().verifyOtp(requestId: _requestId, otpCode: otp);
      final status = result['status'] as String;
      if (status == 'approved') {
        // Vendedor: log in directly
        final user = AuthUser.fromJson(result['user'] as Map<String, dynamic>);
        // Write tokens to storage manually via AuthService internals isn't exposed,
        // so we do it via a lightweight login call instead. Since we have tokens,
        // store them and navigate.
        await AuthService().storeTokensFromRegistration(
          accessToken:  result['access_token'] as String,
          refreshToken: result['refresh_token'] as String,
          user: user,
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(PageRouteBuilder(
          pageBuilder:        (ctx, a1, a2) => const AppShell(),
          transitionDuration: const Duration(milliseconds: 380),
          transitionsBuilder: (ctx, anim, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          ),
        ));
      } else {
        // Admin pending approval
        setState(() { _step = 3; _loading = false; });
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: _bgPage,
      child: Stack(
        fit: StackFit.expand,
        children: [
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
                      child: _buildCard(),
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

  Widget _buildCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
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
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo
          Center(child: _LogoMark()),
          const SizedBox(height: 24),
          Text(
            _step == 1 ? 'Crear cuenta' : _step == 2 ? 'Verificar correo' : 'Solicitud enviada',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _navy,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _step == 1
                ? 'Solo cuentas @ingrammicro.com'
                : _step == 2
                    ? 'Hemos enviado un código de 6 dígitos a ${_emailCtrl.text.trim()}'
                    : 'Un administrador revisará tu solicitud y te notificará.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, color: _muted, height: 1.4),
          ),
          const SizedBox(height: 28),

          if (_step == 1) ..._buildStep1(),
          if (_step == 2) ..._buildStep2(),
          if (_step == 3) ..._buildStep3(),

          // Error
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(CupertinoIcons.exclamationmark_circle_fill,
                              size: 13, color: _errorRed),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(fontSize: 13, color: _errorRed, height: 1.4)),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          if (_step != 3) const SizedBox(height: 20),

          // Back to login
          if (_step != 3)
            Center(
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () {
                  if (_step == 2) {
                    setState(() { _step = 1; _error = null; });
                  } else {
                    Navigator.of(context).pop();
                  }
                },
                child: Text(
                  _step == 2 ? '← Volver al formulario' : '¿Ya tienes cuenta? Inicia sesión',
                  style: const TextStyle(fontSize: 13, color: _blue),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildStep1() => [
    _RegInputField(
      controller: _emailCtrl,
      focusNode:  _emailFocus,
      placeholder: 'Correo @ingrammicro.com',
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _nombreFocus.requestFocus(),
      prefixIcon: CupertinoIcons.mail,
    ),
    const SizedBox(height: 10),
    _RegInputField(
      controller: _nombreCtrl,
      focusNode:  _nombreFocus,
      placeholder: 'Nombre completo',
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _passFocus.requestFocus(),
      prefixIcon: CupertinoIcons.person,
    ),
    const SizedBox(height: 10),
    _RegInputField(
      controller: _passwordCtrl,
      focusNode:  _passFocus,
      placeholder: 'Contraseña',
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submitStep1(),
      prefixIcon: CupertinoIcons.lock,
      suffix: CupertinoButton(
        padding: const EdgeInsets.only(right: 6),
        minimumSize: Size.zero,
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        child: Icon(
          _obscurePassword ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
          size: 17,
          color: _muted,
        ),
      ),
    ),
    const SizedBox(height: 16),

    // Role toggle
    Container(
      decoration: BoxDecoration(
        color: _bgInput,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rol', style: TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              _RoleChip(label: 'Vendedor', value: 'ventas', selected: _role == 'ventas',
                  onTap: () => setState(() => _role = 'ventas')),
              const SizedBox(width: 8),
              _RoleChip(label: 'Administrador', value: 'admin', selected: _role == 'admin',
                  onTap: () => setState(() => _role = 'admin')),
            ],
          ),
          if (_role == 'admin') ...[
            const SizedBox(height: 8),
            const Text(
              'Los administradores requieren aprobación de un admin existente.',
              style: TextStyle(fontSize: 11.5, color: _muted, height: 1.4),
            ),
          ],
        ],
      ),
    ),
    const SizedBox(height: 20),

    _PrimaryButton(
      label: 'Continuar',
      loading: _loading,
      onTap: _submitStep1,
    ),
  ];

  List<Widget> _buildStep2() => [
    // 6-box OTP input
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) => Padding(
        padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
        child: _OtpBox(
          controller: _otpCtrls[i],
          focusNode:  _otpFocus[i],
          onChanged: (v) {
            if (v.length == 1 && i < 5) {
              _otpFocus[i + 1].requestFocus();
            } else if (v.isEmpty && i > 0) {
              _otpFocus[i - 1].requestFocus();
            }
            if (_otpValue.length == 6) _submitStep2();
          },
        ),
      )),
    ),
    const SizedBox(height: 20),
    _PrimaryButton(
      label: 'Verificar',
      loading: _loading,
      onTap: _submitStep2,
    ),
  ];

  List<Widget> _buildStep3() => [
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(CupertinoIcons.checkmark_circle_fill, color: _green, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Correo verificado. Tu solicitud de administrador está pendiente de aprobación.',
              style: TextStyle(fontSize: 13.5, color: _green, height: 1.4),
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    _PrimaryButton(
      label: 'Volver al inicio de sesión',
      loading: false,
      onTap: () => Navigator.of(context).pop(),
    ),
  ];
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _RoleChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _blue : _bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? _blue : _border, width: selected ? 1.5 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: selected ? const Color(0xFFFFFFFF) : _ink,
          ),
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 54,
      child: CupertinoTextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _ink),
        decoration: BoxDecoration(
          color: _bgInput,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
    );
  }
}

class _RegInputField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffix;

  const _RegInputField({
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
  State<_RegInputField> createState() => _RegInputFieldState();
}

class _RegInputFieldState extends State<_RegInputField> {
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
            ? [BoxShadow(color: _blue.withValues(alpha: 0.11), blurRadius: 10, offset: const Offset(0, 2))]
            : [],
      ),
      child: Row(
        children: [
          if (widget.prefixIcon != null) ...[
            const SizedBox(width: 13),
            Icon(widget.prefixIcon, size: 16, color: _focused ? _blue : _muted),
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
              style: const TextStyle(fontSize: 15, color: _ink),
              placeholderStyle: const TextStyle(fontSize: 15, color: _muted),
            ),
          ),
          if (widget.suffix != null) widget.suffix! else const SizedBox(width: 14),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _PrimaryButton({required this.label, required this.loading, required this.onTap});

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: _pressed ? const Duration(milliseconds: 80) : const Duration(milliseconds: 160),
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
                  : [BoxShadow(color: _blue.withValues(alpha: 0.32), blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: widget.loading
                    ? const CupertinoActivityIndicator(color: Color(0xFFFFFFFF))
                    : Text(
                        widget.label,
                        key: ValueKey(widget.label),
                        style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600,
                          color: Color(0xFFFFFFFF), letterSpacing: -0.2,
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

class _LogoMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navyGrad, _navy],
        ),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: _navy.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('IM',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800,
                    color: Color(0xFFFFFFFF), letterSpacing: -1.0, height: 1.0)),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 2),
              child: Container(
                width: 5, height: 5,
                decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB8C4D8).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    const spacing = 22.0;
    const radius  = 1.0;
    const offset  = spacing / 2;
    for (double x = offset; x < size.width; x += spacing) {
      for (double y = offset; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
