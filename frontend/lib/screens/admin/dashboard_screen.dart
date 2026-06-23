import 'dart:math' as math;
import '../../widgets/liti_chat_overlay.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show GestureBinding, PointerScrollEvent;
import 'package:flutter/material.dart'
    show PopupMenuItem, RelativeRect, Scrollbar, Tooltip, showMenu;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../api/client.dart';
import '../../api/models.dart';
import '../../data/cat_tree.dart';
import '../../services/auth_service.dart';
import '../adjudicaciones_screen.dart';
import '../chat_screen.dart';
import '../login_screen.dart';
import '../licitaciones_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _navy = Color(0xFF0F1F3D);
const _blue = Color(0xFF2563EB);
const _gold = Color(0xFFF59E0B);
const _ink = Color(0xFF111827);
const _muted = Color(0xFF6B7280);
const _bg = Color(0xFFF1F4F9);
const _white = Color(0xFFFFFFFF);
const _red = Color(0xFFDC2626);
const _border = Color(0xFFE5E7EB);
const _teal = Color(0xFF0D9488);

// Strong ease-out: cubic-bezier(0.23, 1, 0.32, 1)
const _strong = Cubic(0.23, 1.0, 0.32, 1.0);

// Shared sequential palette — used across bar charts + donut
const _palette = [
  Color(0xFF6366F1), // indigo
  Color(0xFF2563EB), // blue
  Color(0xFF0D9488), // teal
  Color(0xFF059669), // green
  Color(0xFF7C3AED), // purple
  Color(0xFFD97706), // amber
  Color(0xFFE11D48), // rose
  Color(0xFF0EA5E9), // sky
];

// ── Screen ────────────────────────────────────────────────────────────────────

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  DashboardStats? _stats;
  bool _loading = true;
  String? _error;

  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _load();
    litiChat.setScreenContext(
      'Dashboard — panel de control con estadísticas de licitaciones, pipeline y adjudicaciones',
    );
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  // Each section offset 70ms — Emil Kowalski stagger (30-80ms between items)
  Animation<double> _anim(int i) {
    final s = (i * 0.07).clamp(0.0, 0.65);
    return CurvedAnimation(
      parent: _entrance,
      curve: Interval(s, (s + 0.40).clamp(0.0, 1.0), curve: _strong),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _entrance.reset();
    try {
      final stats = await ApiClient().getDashboardStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _loading = false;
        });
        _entrance.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AuthService().logout();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      CupertinoPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _nav(LicitacionFilter? f) {
    HapticFeedback.selectionClick();
    Navigator.of(
      context,
    ).push(CupertinoPageRoute(builder: (_) => LicitacionesScreen(filter: f)));
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final user = AuthService().currentUser;
    final now = DateTime.now();
    final h = now.hour;
    final greet = h < 13
        ? 'Buenos días'
        : h < 20
        ? 'Buenas tardes'
        : 'Buenas noches';
    final nombre = user?.nombre?.split(' ').first ?? 'Admin';

    return CupertinoPageScaffold(
      backgroundColor: _bg,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Compact header ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, top + 20, 20, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greet,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          nombre,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                            letterSpacing: -0.8,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _cap(DateFormat('EEEE, d MMMM', 'es').format(now)),
                          style: TextStyle(
                            fontSize: 12,
                            color: _muted.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: CupertinoActivityIndicator(radius: 9),
                        )
                      else
                        _IconBtn(
                          icon: CupertinoIcons.arrow_clockwise,
                          onTap: _load,
                        ),
                      const SizedBox(width: 8),
                      _IconBtn(
                        icon: CupertinoIcons.sparkles,
                        onTap: () => Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => const ChatScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _UserChip(user: user, onLogout: _logout),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (_error != null)
            SliverFillRemaining(
              child: _ErrorState(error: _error!, onRetry: _load),
            )
          else if (_loading)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            )
          else ...[
            // ── Row 1: KPI trees + secondary chips + schedule ─────────────
            SliverToBoxAdapter(
              child: _FadeSlide(
                anim: _anim(0),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left column: stat trees + secondary KPI chips + team
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Licitaciones section card ──────────────────
                            _SectionCard(
                              title: 'Licitaciones',
                              icon: CupertinoIcons.doc_text_fill,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Row 1: Total 70% + Nuevas 48h 30%
                                  IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          flex: 7,
                                          child: _Press(
                                            onTap: () => _nav(null),
                                            child: _TotalChip(value: _stats!.total),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          flex: 3,
                                          child: _Press(
                                            onTap: () => _nav(
                                              const LicitacionFilter(
                                                reciente: '48h',
                                                label: 'Nuevas 48h',
                                              ),
                                            ),
                                            child: _NuevasChip(
                                              value: _stats!.nuevasRecientes,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  // Row 2: Activas + Caducadas
                                  IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: _StatTree(
                                            parentLabel: 'Activas',
                                            parentCount: _stats!.activas,
                                            parentAccent: _blue,
                                            parentDark: true,
                                            parentTooltip:
                                                'Licitaciones aún en fecha de presentación',
                                            onParentTap: () => _nav(
                                              const LicitacionFilter(
                                                deadlineRange: 'vigentes',
                                                label: 'Activas',
                                              ),
                                            ),
                                            children: [
                                              _StatLeaf(
                                                icon: CupertinoIcons.person_fill,
                                                label: 'Asignadas',
                                                count: _stats!.activasAsignadas,
                                                accent: const Color(0xFF22C55E),
                                                good: true,
                                                tooltip:
                                                    'Un usuario del portal ya se ha asignado esta licitación para su gestión',
                                                onTap: () => _nav(
                                                  const LicitacionFilter(
                                                    deadlineRange: 'vigentes',
                                                    pipelineStage: 'asignada',
                                                    label: 'Activas asignadas',
                                                  ),
                                                ),
                                              ),
                                              _StatLeaf(
                                                icon: CupertinoIcons
                                                    .exclamationmark_circle_fill,
                                                label: 'Sin asignar',
                                                count: _stats!.activasSinAsignar,
                                                accent: _gold,
                                                good: false,
                                                tooltip:
                                                    'Hasta el momento, ningún usuario se ha asignado esta licitación para su gestión',
                                                onTap: () => _nav(
                                                  const LicitacionFilter(
                                                    deadlineRange: 'vigentes',
                                                    pipelineStage: 'nueva',
                                                    label: 'Sin asignar',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _StatTree(
                                            parentLabel: 'Caducadas',
                                            parentCount: _stats!.inactivas,
                                            parentAccent: _red,
                                            parentTooltip:
                                                'Licitaciones fuera de fecha de presentación',
                                            onParentTap: () => _nav(
                                              const LicitacionFilter(
                                                deadlineRange: 'caducadas',
                                                label: 'Caducadas',
                                              ),
                                            ),
                                            children: [
                                              _StatLeaf(
                                                icon: CupertinoIcons
                                                    .checkmark_seal_fill,
                                                label: 'Adjudicadas',
                                                count: _stats!.inactivasAdjudicadas,
                                                accent: _teal,
                                                good: true,
                                                onTap: () => _nav(
                                                  const LicitacionFilter(
                                                    deadlineRange: 'caducadas',
                                                    label: 'Caducadas adjudicadas',
                                                  ),
                                                ),
                                              ),
                                              _StatLeaf(
                                                icon:
                                                    CupertinoIcons.xmark_circle_fill,
                                                label: 'No adjudicadas',
                                                count: _stats!.inactivasNoAdjudicadas,
                                                accent: _red,
                                                good: false,
                                                onTap: () => _nav(
                                                  const LicitacionFilter(
                                                    deadlineRange: 'caducadas',
                                                    label: 'No adjudicadas',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            // ── Adjudicaciones section card ─────────────────
                            _SectionCard(
                              title: 'Adjudicaciones',
                              icon: CupertinoIcons.checkmark_seal_fill,
                              child: IntrinsicHeight(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _Press(
                                        onTap: () => Navigator.of(context).push(
                                          CupertinoPageRoute(
                                            builder: (_) =>
                                                const AdjudicacionesScreen(),
                                          ),
                                        ),
                                        child: _KpiChip(
                                          value: _stats!.adjudicacionesTotal,
                                          label: 'Total',
                                          icon:
                                              CupertinoIcons.checkmark_seal_fill,
                                          accent: _teal,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _Press(
                                        onTap: () => Navigator.of(context).push(
                                          CupertinoPageRoute(
                                            builder: (_) =>
                                                const AdjudicacionesScreen(
                                                  recientes: '2',
                                                ),
                                          ),
                                        ),
                                        child: _KpiChip(
                                          value: _stats!.adjudicacionesRecientes,
                                          label: 'Nuevas 48h',
                                          icon: CupertinoIcons.bolt_fill,
                                          accent: _teal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Team card — bottom of left column
                            _TeamCard(
                              members: _stats!.teamActivity,
                              onTap: (m) => _nav(
                                LicitacionFilter(
                                  assigneeUserIds: m.userId.toString(),
                                  label: m.displayName,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Right column: Cronograma + Duración — needs fixed height
                      // because _ChartCard uses Expanded internally (requires bounded parent).
                      Expanded(
                        child: _ScheduleCard(
                          plazo: _stats!.breakdown.plazo,
                          duracion: _stats!.breakdown.duracion,
                          onPlazoTap: (v, l) => _nav(
                            LicitacionFilter(deadlineRange: v, label: l),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Row 2: Área tecnológica 70% · Tipo procedimiento 30% ──────────
            SliverToBoxAdapter(
              child: _FadeSlide(
                anim: _anim(2),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: SizedBox(
                    height: 320,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 7,
                          child: _CatTabbedCard(
                            cat1: _stats!.breakdown.cat1,
                            cat2: _stats!.breakdown.cat2,
                            cat3: _stats!.breakdown.cat3,
                            onNavigate: _nav,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: _DistCard(
                            title: 'Tipo de procedimiento',
                            icon: CupertinoIcons.doc_plaintext,
                            iconColor: const Color(0xFF0891B2),
                            items: _stats!.breakdown.tipoProcedimiento,
                            total: _stats!.activas,
                            onTap: (v, l) => _nav(
                              LicitacionFilter(tipoProcedimiento: v, label: l),
                            ),
                          ),
                        ),
                      ],
                    ), // Row
                  ), // SizedBox
                ), // Padding
              ), // FadeSlide
            ), // SliverToBoxAdapter
            // ── Row 3: Valor · Comunidades · Mercado ─────────────────────────
            SliverToBoxAdapter(
              child: _FadeSlide(
                anim: _anim(3),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: SizedBox(
                    height: 300,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _DistCard(
                            title: 'Valor',
                            icon: CupertinoIcons.money_euro_circle_fill,
                            iconColor: const Color(0xFF059669),
                            items: _stats!.breakdown.importe,
                            onTap: (v, l) => _nav(
                              LicitacionFilter(importeRange: v, label: l),
                            ),
                            total: _stats!.activas,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DistCard(
                            title: 'Comunidades Autónomas',
                            icon: CupertinoIcons.map_fill,
                            iconColor: const Color(0xFF0EA5E9),
                            items: _stats!.breakdown.comunidad,
                            onTap: (v, l) =>
                                _nav(LicitacionFilter(comunidad: v, label: l)),
                            total: _stats!.activas,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DistCard(
                            title: 'Mercado vertical',
                            icon: CupertinoIcons.building_2_fill,
                            iconColor: const Color(0xFF7C3AED),
                            items: _stats!.breakdown.mercado,
                            onTap: (v, l) =>
                                _nav(LicitacionFilter(mercado: v, label: l)),
                            total: _stats!.activas,
                          ),
                        ),
                      ],
                    ), // Row
                  ), // SizedBox
                ), // Padding
              ), // FadeSlide
            ), // SliverToBoxAdapter
            // ── Declines ──────────────────────────────────────────────────────
            if (_stats!.pendingDeclines.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _FadeSlide(
                  anim: _anim(5),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                    child: _SLabel(
                      text: 'REQUIEREN REVISIÓN',
                      icon: CupertinoIcons.exclamationmark_circle_fill,
                      color: _red,
                      count: _stats!.pendingDeclines.length,
                    ),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _FadeSlide(
                    anim: _anim(6 + i),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _DeclineCard(
                        decline: _stats!.pendingDeclines[i],
                        onRefresh: _load,
                      ),
                    ),
                  ),
                  childCount: _stats!.pendingDeclines.length,
                ),
              ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 56)),
          ],
        ],
      ),
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Fade + slide entrance ─────────────────────────────────────────────────────
// opacity 0→1, translateY 10→0 — never from scale(0), always fully shaped

class _FadeSlide extends StatelessWidget {
  final Animation<double> anim;
  final Widget child;
  const _FadeSlide({required this.anim, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: anim,
    builder: (_, w) => Opacity(
      opacity: anim.value,
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - anim.value)),
        child: w,
      ),
    ),
    child: child,
  );
}

// ── Press scale wrapper ───────────────────────────────────────────────────────
// scale(0.97) on press — 100ms ease-out, 200ms ease-out release

class _Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Press({required this.child, this.onTap});
  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _hovered = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
    onEnter: (_) => Future.microtask(() {
      if (mounted) setState(() => _hovered = true);
    }),
    onExit: (_) => Future.microtask(() {
      if (mounted)
        setState(() {
          _hovered = false;
          _down = false;
        });
    }),
    child: GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _down = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down
            ? 0.97
            : _hovered
            ? 1.015
            : 1.0,
        duration: Duration(
          milliseconds: _down
              ? 90
              : _hovered
              ? 140
              : 220,
        ),
        curve: _strong,
        child: widget.child,
      ),
    ),
  );
}

// ── Icon button ───────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => _Press(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, size: 16, color: _muted),
    ),
  );
}

// ── User chip ─────────────────────────────────────────────────────────────────

class _UserChip extends StatelessWidget {
  final AuthUser? user;
  final VoidCallback onLogout;
  const _UserChip({required this.user, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final name =
        user?.nombre?.split(' ').first ?? user?.email.split('@').first ?? '?';
    final init = name.isEmpty ? '?' : name[0].toUpperCase();
    return _Press(
      onTap: onLogout,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.07),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: _navy,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  init,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              CupertinoIcons.chevron_down,
              size: 10,
              color: _muted.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? color;
  final int? count;
  const _SLabel({
    required this.text,
    required this.icon,
    this.color,
    this.count,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 11, color: color ?? _muted.withValues(alpha: 0.6)),
      const SizedBox(width: 6),
      Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color ?? _muted.withValues(alpha: 0.7),
          letterSpacing: 1.2,
        ),
      ),
      if (count != null) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: (color ?? _muted).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color ?? _muted,
            ),
          ),
        ),
      ],
    ],
  );
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          CupertinoIcons.exclamationmark_circle,
          color: _muted,
          size: 32,
        ),
        const SizedBox(height: 12),
        Text(
          error,
          style: const TextStyle(color: _muted, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        CupertinoButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    ),
  );
}

// ── Compact KPI chip (horizontal) ────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border),
      boxShadow: [
        BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
      ],
    ),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: _muted),
            const SizedBox(width: 5),
            Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _muted,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

class _KpiChip extends StatelessWidget {
  final int value;
  final String label;
  final IconData icon;
  final Color accent;
  const _KpiChip({
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: _navy.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 13, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value.toDouble()),
                duration: const Duration(milliseconds: 700),
                curve: _strong,
                builder: (_, v, _) => Text(
                  '${v.round()}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: _muted,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ── Total pill ────────────────────────────────────────────────────────────────

class _NuevasChip extends StatelessWidget {
  final int value;
  const _NuevasChip({required this.value});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      color: _blue,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: _blue.withValues(alpha: 0.22),
          blurRadius: 16,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.toDouble()),
          duration: const Duration(milliseconds: 700),
          curve: _strong,
          builder: (_, v, _) => Text(
            '${v.round()}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _white,
              letterSpacing: -0.8,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Nuevas 48h',
          style: TextStyle(
            fontSize: 10,
            color: _white.withValues(alpha: 0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _TotalChip extends StatelessWidget {
  final int value;
  const _TotalChip({required this.value});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: _navy,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: _navy.withValues(alpha: 0.22),
          blurRadius: 16,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.toDouble()),
          duration: const Duration(milliseconds: 700),
          curve: _strong,
          builder: (_, v, _) => Text(
            '${v.round()}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _white,
              letterSpacing: -0.8,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Total',
              style: TextStyle(
                fontSize: 10,
                color: _white.withValues(alpha: 0.45),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Licitaciones totales en portal de Adjudicaciones TIC',
              preferBelow: true,
              child: Icon(
                CupertinoIcons.info_circle,
                size: 11,
                color: _white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// ── StatLeaf — data class for a tree child row ───────────────────────────────

class _StatLeaf {
  final IconData icon;
  final String label;
  final int count;
  final Color accent;
  final bool good;
  final VoidCallback onTap;
  final String? tooltip;
  const _StatLeaf({
    required this.icon,
    required this.label,
    required this.count,
    required this.accent,
    required this.good,
    required this.onTap,
    this.tooltip,
  });
}

// ── StatTree — parent card with tree-connected child rows ─────────────────────

class _StatTree extends StatelessWidget {
  final String parentLabel;
  final int parentCount;
  final Color parentAccent;
  final bool parentDark;
  final VoidCallback onParentTap;
  final List<_StatLeaf> children;
  final String? parentTooltip;

  const _StatTree({
    required this.parentLabel,
    required this.parentCount,
    required this.parentAccent,
    this.parentDark = false,
    required this.onParentTap,
    required this.children,
    this.parentTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final bg = parentDark ? _navy : _white;
    final fg = parentDark ? _white : _ink;
    final fgMd = parentDark ? _white.withValues(alpha: 0.50) : _muted;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: parentDark
                ? _navy.withValues(alpha: 0.25)
                : _navy.withValues(alpha: 0.06),
            blurRadius: parentDark ? 16 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Parent row (tappable) ──────────────────────────────────────────
          GestureDetector(
            onTap: onParentTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 7),
                    decoration: BoxDecoration(
                      color: parentAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          parentLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: fgMd,
                          ),
                        ),
                        if (parentTooltip != null) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: parentTooltip!,
                            preferBelow: true,
                            child: Icon(
                              CupertinoIcons.info_circle,
                              size: 11,
                              color: fgMd.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: parentCount.toDouble()),
                    duration: const Duration(milliseconds: 700),
                    curve: _strong,
                    builder: (_, v, _) => Text(
                      '${v.round()}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: fg,
                        letterSpacing: -0.6,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Divider ────────────────────────────────────────────────────────
          Container(
            height: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: fg.withValues(alpha: 0.08),
          ),
          // ── Child rows ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // vertical tree line
                  Container(
                    width: 1.5,
                    margin: const EdgeInsets.only(right: 10, top: 4, bottom: 4),
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children
                          .map(
                            (leaf) => GestureDetector(
                              onTap: leaf.onTap,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    // good/bad tinted icon badge
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: leaf.accent.withValues(
                                          alpha: parentDark ? 0.18 : 0.10,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Icon(
                                        leaf.icon,
                                        size: 11,
                                        color: leaf.accent,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              leaf.label,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: fgMd,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (leaf.tooltip != null) ...[
                                            const SizedBox(width: 3),
                                            Tooltip(
                                              message: leaf.tooltip!,
                                              preferBelow: true,
                                              child: Icon(
                                                CupertinoIcons.info_circle,
                                                size: 10,
                                                color: fgMd.withValues(
                                                  alpha: 0.45,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    TweenAnimationBuilder<double>(
                                      tween: Tween(
                                        begin: 0,
                                        end: leaf.count.toDouble(),
                                      ),
                                      duration: const Duration(
                                        milliseconds: 700,
                                      ),
                                      curve: _strong,
                                      builder: (_, v, _) => Text(
                                        '${v.round()}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: leaf.good
                                              ? leaf.accent
                                              : (parentDark
                                                    ? fg
                                                    : _red.withValues(
                                                        alpha: leaf.count == 0
                                                            ? 0.35
                                                            : 1.0,
                                                      )),
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Timeline card (Plazo restante) ────────────────────────────────────────────
// Gradient bars: teal → amber spectrum, proportional widths

class _TimelineCard extends StatefulWidget {
  final List<BreakdownItem> items;
  final void Function(String, String) onTap;
  const _TimelineCard({required this.items, required this.onTap});
  @override
  State<_TimelineCard> createState() => _TimelineCardState();
}

class _TimelineCardState extends State<_TimelineCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // 1100ms total: enough for 4-bar stagger to complete cleanly
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Urgency gradient: teal → blue → amber → gray
  static const _barColors = [
    LinearGradient(colors: [Color(0xFF0D9488), Color(0xFF34D399)]),
    LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF60A5FA)]),
    LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)]),
    LinearGradient(colors: [Color(0xFF9CA3AF), Color(0xFFD1D5DB)]),
  ];

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final max = items
        .fold(0, (m, i) => i.count > m ? i.count : m)
        .clamp(1, 999999);
    final total = items.fold(0, (s, i) => s + i.count);
    final n = items.length;

    return _ChartCard(
      title: 'Cronograma de licitaciónes',
      subtitle: 'Plazo restante',
      icon: CupertinoIcons.clock_fill,
      iconColor: _teal,
      trailing: total > 0 ? '$total licitaciones' : null,
      child: Column(
        children: List.generate(n, (i) {
          final item = items[i];
          final grad = i < _barColors.length ? _barColors[i] : _barColors.last;
          // Each bar gets its own interval: bars stagger 0.12 apart, each runs 0.65 of the total
          final start = i * 0.12;
          final end = (start + 0.65).clamp(0.0, 1.0);
          final barAnim = CurvedAnimation(
            parent: _ctrl,
            curve: Interval(start, end, curve: _strong),
          );
          return _GradientBarRow(
            label: item.label,
            count: item.count,
            maxCount: max,
            gradient: grad,
            barAnim: barAnim,
            isLast: i == n - 1,
            onTap: item.count > 0
                ? () => widget.onTap(item.value, item.label)
                : null,
          );
        }),
      ),
    );
  }
}

// ── Cronograma + Duración merged card ────────────────────────────────────────

class _ScheduleCard extends StatefulWidget {
  final List<BreakdownItem> plazo;
  final List<BreakdownItem> duracion;
  final void Function(String, String) onPlazoTap;
  const _ScheduleCard({
    required this.plazo,
    required this.duracion,
    required this.onPlazoTap,
  });
  @override
  State<_ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<_ScheduleCard>
    with SingleTickerProviderStateMixin {
  int _tab = 0;
  late final AnimationController _ctrl;
  final _scrollCtrl = ScrollController();

  static const _plazoColors = [
    LinearGradient(colors: [Color(0xFF0D9488), Color(0xFF34D399)]),
    LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF60A5FA)]),
    LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)]),
    LinearGradient(colors: [Color(0xFF9CA3AF), Color(0xFFD1D5DB)]),
    LinearGradient(colors: [Color(0xFFDC2626), Color(0xFFF87171)]), // Caducadas
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _switchTab(int t) {
    if (t == _tab) return;
    setState(() => _tab = t);
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final isPlazo = _tab == 0;
    final items = isPlazo ? widget.plazo : widget.duracion;
    final max = items
        .fold(0, (m, i) => i.count > m ? i.count : m)
        .clamp(1, 999999);
    final total = items.fold(0, (s, i) => s + i.count);
    final n = items.length;

    return _ChartCard(
      title: isPlazo ? 'Cronograma' : 'Duración',
      subtitle: isPlazo ? 'Plazo restante' : 'Meses de contrato',
      icon: CupertinoIcons.clock_fill,
      iconColor: _teal,
      expand: false,
      trailing: total > 0 ? '$total licitaciones' : null,
      headerBottom: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
        child: Row(
          children: [
            _SchedTab(
              label: 'Plazo',
              active: _tab == 0,
              onTap: () => _switchTab(0),
            ),
            const SizedBox(width: 6),
            _SchedTab(
              label: 'Duración',
              active: _tab == 1,
              onTap: () => _switchTab(1),
            ),
          ],
        ),
      ),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            // Register as fallback — only wins when inner Scrollable is at its
            // extent and didn't claim the event, preventing page scroll chaining.
            GestureBinding.instance.pointerSignalResolver.register(
              event,
              (_) {},
            );
          }
        },
        child: Scrollbar(
          controller: _scrollCtrl,
          thumbVisibility: true,
          radius: const Radius.circular(4),
          thickness: 3,
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            child: Column(
              children: List.generate(n, (i) {
                final item = items[i];
                if (isPlazo) {
                  final grad = i < _plazoColors.length
                      ? _plazoColors[i]
                      : _plazoColors.last;
                  final start = i * 0.12;
                  final end = (start + 0.65).clamp(0.0, 1.0);
                  final barAnim = CurvedAnimation(
                    parent: _ctrl,
                    curve: Interval(start, end, curve: _strong),
                  );
                  return _GradientBarRow(
                    label: item.label,
                    count: item.count,
                    maxCount: max,
                    gradient: grad,
                    barAnim: barAnim,
                    isLast: i == n - 1,
                    onTap: item.count > 0
                        ? () => widget.onPlazoTap(item.value, item.label)
                        : null,
                  );
                } else {
                  final barAnim = CurvedAnimation(
                    parent: _ctrl,
                    curve: Interval(
                      (i * 0.08).clamp(0.0, 0.6),
                      ((i * 0.08) + 0.55).clamp(0.0, 1.0),
                      curve: _strong,
                    ),
                  );
                  return _DarkBarRow(
                    label: item.label,
                    count: item.count,
                    max: max,
                    color: _palette[i % _palette.length],
                    barAnim: barAnim,
                    isLast: i == n - 1,
                  );
                }
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _SchedTab extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SchedTab({
    required this.label,
    required this.active,
    required this.onTap,
  });
  @override
  State<_SchedTab> createState() => _SchedTabState();
}

class _SchedTabState extends State<_SchedTab> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: widget.active
                ? _blue
                : _hovered
                ? const Color(0xFFEFF6FF)
                : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: widget.active ? _white : _muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientBarRow extends StatefulWidget {
  final String label;
  final int count;
  final int maxCount;
  final LinearGradient gradient;
  final Animation<double> barAnim;
  final bool isLast;
  final VoidCallback? onTap;
  const _GradientBarRow({
    required this.label,
    required this.count,
    required this.maxCount,
    required this.gradient,
    required this.barAnim,
    required this.isLast,
    this.onTap,
  });
  @override
  State<_GradientBarRow> createState() => _GradientBarRowState();
}

class _GradientBarRowState extends State<_GradientBarRow> {
  bool _hovered = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final frac = widget.maxCount > 0 ? widget.count / widget.maxCount : 0.0;
    final canTap = widget.onTap != null;

    return Column(
      children: [
        MouseRegion(
          cursor: canTap ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: canTap
              ? (_) => Future.microtask(() {
                  if (mounted) setState(() => _hovered = true);
                })
              : null,
          onExit: canTap
              ? (_) => Future.microtask(() {
                  if (mounted)
                    setState(() {
                      _hovered = false;
                      _down = false;
                    });
                })
              : null,
          child: GestureDetector(
            onTapDown: canTap ? (_) => setState(() => _down = true) : null,
            onTapUp: canTap
                ? (_) {
                    setState(() => _down = false);
                    widget.onTap!();
                  }
                : null,
            onTapCancel: canTap ? () => setState(() => _down = false) : null,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: Duration(milliseconds: _down ? 80 : 180),
              curve: _strong,
              decoration: BoxDecoration(
                color: _hovered && !_down
                    ? _bg.withValues(alpha: 0.7)
                    : const Color(0x00000000),
                borderRadius: BorderRadius.circular(8),
              ),
              child: AnimatedOpacity(
                opacity: _down ? 0.7 : 1.0,
                duration: const Duration(milliseconds: 120),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 72,
                            child: Text(
                              widget.label,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _muted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (_, c) => Stack(
                                children: [
                                  Container(
                                    height: 24,
                                    width: c.maxWidth,
                                    decoration: BoxDecoration(
                                      color: _bg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  AnimatedBuilder(
                                    animation: widget.barAnim,
                                    builder: (_, w) => Container(
                                      height: 24,
                                      width:
                                          (c.maxWidth *
                                                  frac *
                                                  widget.barAnim.value)
                                              .clamp(0.0, c.maxWidth),
                                      decoration: BoxDecoration(
                                        gradient: widget.gradient,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 30,
                            child: AnimatedBuilder(
                              animation: widget.barAnim,
                              builder: (_, w) => Text(
                                '${(widget.count * widget.barAnim.value).round()}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: _ink,
                                ),
                              ),
                            ),
                          ),
                          if (canTap)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                CupertinoIcons.chevron_right,
                                size: 10,
                                color: _muted.withValues(alpha: 0.35),
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
        if (!widget.isLast)
          Container(height: 0.5, color: _border.withValues(alpha: 0.7)),
      ],
    );
  }
}

// ── Pipeline cheese chart ─────────────────────────────────────────────────────
// Donut chart (cheese wheel): arcs proportional to stage count, total in center,
// legend below. Animates by sweeping arcs from 0 → full angle.

class _FunnelCard extends StatefulWidget {
  final List<BreakdownItem> stages;
  final int total;
  final void Function(String, String) onTap;
  const _FunnelCard({
    required this.stages,
    required this.total,
    required this.onTap,
  });
  @override
  State<_FunnelCard> createState() => _FunnelCardState();
}

class _FunnelCardState extends State<_FunnelCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  int? _hoveredSlice;

  static const _sliceColors = [
    Color(0xFF1E3A5F),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF0D9488),
    Color(0xFF059669),
    Color(0xFFD97706),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: _strong);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stages = widget.stages;
    final total = stages.fold(0, (s, i) => s + i.count);
    // Use all stages for the bar (zero ones show as empty placeholder)
    final hasData = total > 0;

    return _ChartCard(
      title: 'Pipeline',
      icon: CupertinoIcons.chart_pie_fill,
      iconColor: const Color(0xFF6366F1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Big segmented bar ───────────────────────────────────────
          AnimatedBuilder(
            animation: _anim,
            builder: (_, w) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The bar itself
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 36,
                      child: hasData
                          ? Row(
                              children: [
                                for (int i = 0; i < stages.length; i++) ...[
                                  if (stages[i].count > 0) ...[
                                    Expanded(
                                      flex: stages[i].count,
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        onEnter: (_) =>
                                            setState(() => _hoveredSlice = i),
                                        onExit: (_) => setState(
                                          () => _hoveredSlice = null,
                                        ),
                                        child: GestureDetector(
                                          onTap: () => widget.onTap(
                                            stages[i].value,
                                            stages[i].label,
                                          ),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 140,
                                            ),
                                            color: _hoveredSlice == i
                                                ? _sliceColors[i %
                                                          _sliceColors.length]
                                                      .withValues(alpha: 0.72)
                                                : _sliceColors[i %
                                                      _sliceColors.length],
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (i < stages.length - 1 &&
                                        stages
                                            .sublist(i + 1)
                                            .any((s) => s.count > 0))
                                      const SizedBox(width: 3),
                                  ],
                                ],
                              ],
                            )
                          // Empty state bar
                          : Container(color: const Color(0xFFE5E7EB)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Labels pinned under each segment
                  Row(
                    children: [
                      for (int i = 0; i < stages.length; i++) ...[
                        if (stages[i].count > 0) ...[
                          Expanded(
                            flex: stages[i].count,
                            child: GestureDetector(
                              onTap: () => widget.onTap(
                                stages[i].value,
                                stages[i].label,
                              ),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                onEnter: (_) =>
                                    setState(() => _hoveredSlice = i),
                                onExit: (_) =>
                                    setState(() => _hoveredSlice = null),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${(stages[i].count * _anim.value).round()}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: _hoveredSlice == i
                                            ? _sliceColors[i %
                                                  _sliceColors.length]
                                            : _ink,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    Text(
                                      stages[i].label,
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        color: _muted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (i < stages.length - 1 &&
                              stages.sublist(i + 1).any((s) => s.count > 0))
                            const SizedBox(width: 3),
                        ],
                      ],
                    ],
                  ),
                  // Empty state labels
                  if (!hasData)
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: List.generate(stages.length, (i) {
                        final color = _sliceColors[i % _sliceColors.length];
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${stages[i].label}  0',
                              style: TextStyle(
                                fontSize: 10,
                                color: _muted.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Team card ─────────────────────────────────────────────────────────────────

class _TeamCard extends StatelessWidget {
  final List<TeamActivity> members;
  final void Function(TeamActivity) onTap;
  const _TeamCard({required this.members, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.person_2_fill, size: 13, color: _muted),
              const SizedBox(width: 6),
              const Text(
                'Mi equipo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _muted,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (members.isEmpty)
            const Text(
              'Sin miembros',
              style: TextStyle(fontSize: 12, color: _muted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in members)
                  _TeamSquare(member: m, onTap: () => onTap(m)),
              ],
            ),
        ],
      ),
    );
  }
}

class _TeamSquare extends StatefulWidget {
  final TeamActivity member;
  final VoidCallback? onTap;
  const _TeamSquare({required this.member, this.onTap});
  @override
  State<_TeamSquare> createState() => _TeamSquareState();
}

class _TeamSquareState extends State<_TeamSquare> {
  bool _hovered = false;

  static const _avatarColors = [
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF0D9488),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFF1E3A5F),
  ];

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final name = m.displayName;
    final initials = name
        .split(' ')
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();
    final avatarColor = _avatarColors[m.userId % _avatarColors.length];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: avatarColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                name.split(' ').first,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              Text(
                '${m.assignedCount}',
                style: const TextStyle(
                  fontSize: 9,
                  color: _muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Distribution card (importe + mercado) ────────────────────────────────────

class _DistCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<BreakdownItem> items;
  final void Function(String, String) onTap;
  final int total;
  const _DistCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.items,
    required this.onTap,
    required this.total,
  });
  @override
  State<_DistCard> createState() => _DistCardState();
}

class _DistCardState extends State<_DistCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: _strong);
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.items
        .fold(0, (m, i) => i.count > m ? i.count : m)
        .clamp(1, 999999);
    final totalVal = widget.items.fold(0, (s, i) => s + i.count);

    return _ChartCard(
      title: widget.title,
      icon: widget.icon,
      iconColor: widget.iconColor,
      trailing: totalVal > 0 ? 'Total: $totalVal' : null,
      expand: true,
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            GestureBinding.instance.pointerSignalResolver.register(
              event,
              (_) {},
            );
          }
        },
        child: Scrollbar(
          controller: _scrollCtrl,
          thumbVisibility: true,
          radius: const Radius.circular(4),
          thickness: 3,
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            child: Column(
              children: List.generate(widget.items.length, (i) {
                final item = widget.items[i];
                return _DarkBarRow(
                  label: item.label,
                  count: item.count,
                  max: max,
                  color: _palette[i % _palette.length],
                  barAnim: _anim,
                  isLast: i == widget.items.length - 1,
                  onTap: item.count > 0
                      ? () => widget.onTap(item.value, item.label)
                      : null,
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _DarkBarRow extends StatefulWidget {
  final String label;
  final int count;
  final int max;
  final Color color;
  final Animation<double> barAnim;
  final bool isLast;
  final VoidCallback? onTap;
  final Widget? trailing;
  final VoidCallback? onTrailingTap;
  const _DarkBarRow({
    required this.label,
    required this.count,
    required this.max,
    required this.color,
    required this.barAnim,
    required this.isLast,
    this.onTap,
    this.trailing,
    this.onTrailingTap,
  });
  @override
  State<_DarkBarRow> createState() => _DarkBarRowState();
}

class _DarkBarRowState extends State<_DarkBarRow> {
  bool _hovered = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final frac = widget.max > 0 ? widget.count / widget.max : 0.0;
    final canTap = widget.onTap != null;

    return Column(
      children: [
        MouseRegion(
          cursor: canTap ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: canTap
              ? (_) => Future.microtask(() {
                  if (mounted) setState(() => _hovered = true);
                })
              : null,
          onExit: canTap
              ? (_) => Future.microtask(() {
                  if (mounted)
                    setState(() {
                      _hovered = false;
                      _down = false;
                    });
                })
              : null,
          child: GestureDetector(
            onTapDown: canTap ? (_) => setState(() => _down = true) : null,
            onTapUp: canTap
                ? (_) {
                    setState(() => _down = false);
                    widget.onTap!();
                  }
                : null,
            onTapCancel: canTap ? () => setState(() => _down = false) : null,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: Duration(milliseconds: _down ? 80 : 180),
              curve: _strong,
              decoration: BoxDecoration(
                color: _hovered && !_down
                    ? widget.color.withValues(alpha: 0.04)
                    : const Color(0x00000000),
                borderRadius: BorderRadius.circular(6),
              ),
              child: AnimatedOpacity(
                opacity: _down ? 0.65 : 1.0,
                duration: const Duration(milliseconds: 120),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: widget.count == 0
                                ? _muted.withValues(alpha: 0.4)
                                : _ink,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 4,
                        child: LayoutBuilder(
                          builder: (_, c) => Stack(
                            children: [
                              Container(
                                height: 8,
                                width: c.maxWidth,
                                decoration: BoxDecoration(
                                  color: widget.color.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              AnimatedBuilder(
                                animation: widget.barAnim,
                                builder: (_, w) => Container(
                                  height: 8,
                                  width:
                                      (c.maxWidth * frac * widget.barAnim.value)
                                          .clamp(0.0, c.maxWidth),
                                  decoration: BoxDecoration(
                                    color: widget.count == 0
                                        ? _border
                                        : widget.color,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 26,
                        child: AnimatedBuilder(
                          animation: widget.barAnim,
                          builder: (_, w) => Text(
                            '${(widget.count * widget.barAnim.value).round()}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: widget.count == 0
                                  ? _muted.withValues(alpha: 0.3)
                                  : _ink,
                            ),
                          ),
                        ),
                      ),
                      if (widget.trailing != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: widget.onTrailingTap,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: widget.trailing!,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!widget.isLast)
          Container(height: 0.5, color: _border.withValues(alpha: 0.5)),
      ],
    );
  }
}

// ── CAT taxonomy (cat1 → cat2 → [cat3]) ──────────────────────────────────────
// Values are normalised to lowercase for matching against DB labels.

// Use shared catTree from data/cat_tree.dart
const _catTree = catTree;

bool _matchLabel(String label, String key) =>
    label.toLowerCase().trim() == key.toLowerCase().trim();

List<BreakdownItem> _filterCat2ForCat1(
  List<BreakdownItem> cat2,
  String cat1Label,
) {
  final key = cat1Label.toLowerCase();
  final allowed = _catTree[key]?.keys.toSet() ?? {};
  if (allowed.isEmpty) return cat2;
  return cat2
      .where((i) => allowed.any((k) => _matchLabel(i.label, k)))
      .toList();
}

List<BreakdownItem> _filterCat3ForCat2(
  List<BreakdownItem> cat3,
  String cat1Label,
  String cat2Label,
) {
  final cat1Key = cat1Label.toLowerCase();
  final cat2Key = cat2Label.toLowerCase();
  final allowed = _catTree[cat1Key]?[cat2Key]?.toSet() ?? {};
  if (allowed.isEmpty) return cat3;
  return cat3
      .where((i) => allowed.any((k) => _matchLabel(i.label, k)))
      .toList();
}

// ── Unified CAT drill-down card ───────────────────────────────────────────────

class _CatTabbedCard extends StatefulWidget {
  final List<BreakdownItem> cat1;
  final List<BreakdownItem> cat2;
  final List<BreakdownItem> cat3;
  final void Function(LicitacionFilter) onNavigate;
  const _CatTabbedCard({
    required this.cat1,
    required this.cat2,
    required this.cat3,
    required this.onNavigate,
  });
  @override
  State<_CatTabbedCard> createState() => _CatTabbedCardState();
}

class _CatTabbedCardState extends State<_CatTabbedCard>
    with SingleTickerProviderStateMixin {
  // drill level: 0=cat1, 1=cat2, 2=cat3
  int _level = 0;
  String? _selectedCat1; // label as returned by API
  String? _selectedCat2;
  late final AnimationController _barCtrl;
  late final Animation<double> _barAnim;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _barAnim = CurvedAnimation(parent: _barCtrl, curve: _strong);
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _barCtrl.forward();
    });
  }

  @override
  void dispose() {
    _barCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<BreakdownItem> get _currentItems {
    if (_level == 0) return widget.cat1;
    if (_level == 1) return _filterCat2ForCat1(widget.cat2, _selectedCat1!);
    return _filterCat3ForCat2(widget.cat3, _selectedCat1!, _selectedCat2!);
  }

  // Navigate to licitaciones for a specific item at current level
  void _navigateItem(String label) {
    widget.onNavigate(
      LicitacionFilter(
        cat1: _level == 0 ? label : _selectedCat1,
        cat2: _level == 1 ? label : (_level == 2 ? _selectedCat2 : null),
        cat3: _level == 2 ? label : null,
        label: label,
      ),
    );
  }

  void _drillDown(String label) {
    setState(() {
      if (_level == 0) {
        _selectedCat1 = label;
        _level = 1;
      } else if (_level == 1) {
        _selectedCat2 = label;
        _level = 2;
      }
    });
    _barCtrl.forward(from: 0);
  }

  void _goBack() {
    setState(() {
      _level = math.max(0, _level - 1);
      if (_level == 0) _selectedCat1 = null;
      if (_level <= 1) _selectedCat2 = null;
    });
    _barCtrl.forward(from: 0);
  }

  bool _canDrillDown(BreakdownItem item) {
    if (_level == 0) {
      final key = item.label.toLowerCase();
      return _catTree.containsKey(key);
    }
    if (_level == 1) {
      final cat1Key = _selectedCat1!.toLowerCase();
      final cat2Key = item.label.toLowerCase();
      final children = _catTree[cat1Key]?[cat2Key] ?? [];
      return children.isNotEmpty;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final items = _currentItems;
    final max = items
        .fold(0, (m, i) => i.count > m ? i.count : m)
        .clamp(1, 999999);
    final total = widget.cat1.fold(0, (s, i) => s + i.count);

    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with breadcrumb
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    CupertinoIcons.tag_fill,
                    size: 15,
                    color: Color(0xFFD97706),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Breadcrumb(
                    level: _level,
                    cat1: _selectedCat1,
                    cat2: _selectedCat2,
                    onBack: _level > 0 ? _goBack : null,
                  ),
                ),
                if (total > 0)
                  Text(
                    'Total: $total',
                    style: const TextStyle(fontSize: 11.5, color: _muted),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 0.5, color: _border),
          // Scrollable bar rows
          Expanded(
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (_) {},
                  );
                }
              },
              child: Scrollbar(
                controller: _scrollCtrl,
                thumbVisibility: true,
                radius: const Radius.circular(4),
                thickness: 3,
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: Column(
                      children: List.generate(items.length, (i) {
                        final item = items[i];
                        final drillable = _canDrillDown(item);
                        return _DarkBarRow(
                          label: item.label,
                          count: item.count,
                          max: max,
                          color: _palette[i % _palette.length],
                          barAnim: _barAnim,
                          isLast: i == items.length - 1,
                          onTap: drillable
                              ? () => _drillDown(item.label)
                              : () => _navigateItem(item.label),
                          trailing: const _VerCategoriaChip(),
                          onTrailingTap: () => _navigateItem(item.label),
                        );
                      }),
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

class _VerCategoriaChip extends StatelessWidget {
  const _VerCategoriaChip();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Ver categoría',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: _blue,
            ),
          ),
          SizedBox(width: 2),
          Icon(CupertinoIcons.arrow_right, size: 9, color: _blue),
        ],
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  final int level;
  final String? cat1;
  final String? cat2;
  final VoidCallback? onBack;
  const _Breadcrumb({required this.level, this.cat1, this.cat2, this.onBack});

  @override
  Widget build(BuildContext context) {
    final crumbs = <String>['Área tecnológica'];
    if (cat1 != null) crumbs.add(cat1!);
    if (cat2 != null) crumbs.add(cat2!);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (int i = 0; i < crumbs.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                CupertinoIcons.chevron_right,
                size: 10,
                color: _muted,
              ),
            ),
          if (i < crumbs.length - 1 && onBack != null)
            GestureDetector(
              onTap: onBack,
              behavior: HitTestBehavior.opaque,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    crumbs[i],
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                      color: _blue,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ),
            )
          else
            Text(
              crumbs[i],
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: i == crumbs.length - 1
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: i == crumbs.length - 1 ? _ink : _muted,
                letterSpacing: -0.1,
              ),
            ),
        ],
      ],
    );
  }
}

// ── Chart card shell ──────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final String? trailing;
  final Widget? headerBottom;
  final Widget child;
  final bool expand;
  const _ChartCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.iconColor,
    this.trailing,
    this.headerBottom,
    required this.child,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: _navy.withValues(alpha: 0.05),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            14,
            14,
            headerBottom != null ? 0 : 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(icon, size: 13, color: iconColor),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 10,
                            color: _muted.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  if (trailing != null)
                    Text(
                      trailing!,
                      style: TextStyle(
                        fontSize: 10,
                        color: _muted.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
              if (headerBottom case final w?) w,
            ],
          ),
        ),
        Container(height: 0.5, color: _border),
        if (expand)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: child,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: child,
          ),
      ],
    ),
  );
}

// ── Team member card ──────────────────────────────────────────────────────────

class _MemberCard extends StatefulWidget {
  final TeamActivity member;
  final int rank;
  final int max;
  final VoidCallback onTap;
  const _MemberCard({
    required this.member,
    required this.rank,
    required this.max,
    required this.onTap,
  });
  @override
  State<_MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<_MemberCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _barCtrl;
  late final Animation<double> _barAnim;
  bool _hovered = false;
  bool _down = false;

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _barAnim = CurvedAnimation(parent: _barCtrl, curve: _strong);
    Future.delayed(Duration(milliseconds: 200 + widget.rank * 60), () {
      if (mounted) _barCtrl.forward();
    });
  }

  @override
  void dispose() {
    _barCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final isTop = widget.rank == 1;
    final frac = widget.max > 0 ? m.assignedCount / widget.max : 0.0;
    final name = m.nombre ?? m.email.split('@').first;
    final initials = name
        .split(' ')
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => Future.microtask(() {
        if (mounted) setState(() => _hovered = true);
      }),
      onExit: (_) => Future.microtask(() {
        if (mounted)
          setState(() {
            _hovered = false;
            _down = false;
          });
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) {
          setState(() => _down = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _down = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _down
              ? 0.97
              : _hovered
              ? 1.015
              : 1.0,
          duration: Duration(
            milliseconds: _down
                ? 90
                : _hovered
                ? 140
                : 220,
          ),
          curve: _strong,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(16),
              border: isTop
                  ? Border.all(color: _blue.withValues(alpha: 0.20))
                  : null,
              boxShadow: [
                BoxShadow(
                  color: isTop
                      ? _blue.withValues(alpha: 0.08)
                      : _navy.withValues(alpha: 0.05),
                  blurRadius: isTop ? 16 : 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                // Avatar + rank badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isTop ? _navy : _bg,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isTop ? _white : _navy,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: isTop ? _gold : _bg,
                          shape: BoxShape.circle,
                          border: Border.all(color: _white, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            '${widget.rank}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: isTop ? _white : _muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                // Name + bar
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: m.assignedCount.toDouble(),
                            ),
                            duration: const Duration(milliseconds: 700),
                            curve: _strong,
                            builder: (_, v, w) => Text(
                              '${v.round()}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: isTop ? _navy : _muted,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        m.latestTitulo ?? 'Sin asignaciones recientes',
                        style: TextStyle(
                          fontSize: 11,
                          color: _muted.withValues(alpha: 0.65),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (_, c) => Stack(
                          children: [
                            Container(
                              height: 4,
                              width: c.maxWidth,
                              decoration: BoxDecoration(
                                color: _bg,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            AnimatedBuilder(
                              animation: _barAnim,
                              builder: (_, w) => Container(
                                height: 4,
                                width: (c.maxWidth * frac * _barAnim.value)
                                    .clamp(0.0, c.maxWidth),
                                decoration: BoxDecoration(
                                  color: isTop
                                      ? _blue
                                      : _blue.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 13,
                  color: _muted.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Decline card ──────────────────────────────────────────────────────────────

class _DeclineCard extends StatelessWidget {
  final PendingDecline decline;
  final VoidCallback onRefresh;
  const _DeclineCard({required this.decline, required this.onRefresh});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _red.withValues(alpha: 0.18)),
      boxShadow: [
        BoxShadow(
          color: _navy.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 4),
          decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                decline.titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${decline.userNombre ?? 'Vendedor'} · No interesado'
                '${decline.reason != null ? " · ${decline.reason}" : ""}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _Press(
          onTap: () => _showAssign(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Asignar',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _white,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _showAssign(BuildContext context) async {
    try {
      final box = context.findRenderObject() as RenderBox?;
      final users = await ApiClient().getUsers();
      final vendedores = users.where((u) => u.role != 'admin').toList();
      if (!context.mounted) return;
      if (box == null) return;
      final overlay =
          Navigator.of(context).overlay!.context.findRenderObject()
              as RenderBox;
      final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
      final picked = await showMenu<AppUser>(
        context: context,
        position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
        color: const Color(0xFFFFFFFF),
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 300),
        items: vendedores
            .map(
              (v) => PopupMenuItem<AppUser>(
                value: v,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  v.displayName,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            )
            .toList(),
      );
      if (picked == null || !context.mounted) return;
      await ApiClient().forceAssign(decline.licitacionId, picked.id);
      if (context.mounted) onRefresh();
    } catch (_) {
      /* ignore */
    }
  }
}
