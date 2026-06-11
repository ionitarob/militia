import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../api/client.dart';
import '../../api/models.dart';
import '../../widgets/pipeline_badge.dart';
import '../licitacion_detail_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _navy  = Color(0xFF0F1F3D);
const _blue  = Color(0xFF2563EB);
const _gold  = Color(0xFFF59E0B);
const _ink   = Color(0xFF111827);
const _muted = Color(0xFF6B7280);
const _bg    = Color(0xFFF1F4F9);
const _white = Color(0xFFFFFFFF);
const _red   = Color(0xFFDC2626);

class MiPanelAdminScreen extends StatefulWidget {
  const MiPanelAdminScreen({super.key});

  @override
  State<MiPanelAdminScreen> createState() => _MiPanelAdminScreenState();
}

class _MiPanelAdminScreenState extends State<MiPanelAdminScreen> {
  List<Licitacion> _mine = [];
  List<WorkloadUser> _team = [];
  bool _loading = true;
  String? _error;

  // Which vendedor rows are expanded
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiClient().getMyLicitaciones(),
        ApiClient().getTeamWorkload(),
      ]);
      if (mounted) {
        setState(() {
          _mine = results[0] as List<Licitacion>;
          _team = results[1] as List<WorkloadUser>;
          _loading = false;
        });
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

  // ── Derived ───────────────────────────────────────────────────────────────────

  int get _myUrgent => _mine.where((l) {
    final d = l.fechaLimiteOferta;
    if (d == null) return false;
    try { return DateTime.parse(d).difference(DateTime.now()).inDays <= 7; } catch (_) { return false; }
  }).length;

  int get _teamTotal => _team.fold(0, (s, u) => s + u.licitaciones.length);

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: _bg,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            backgroundColor: _bg,
            border: null,
            largeTitle: const Text(
              'Mi Panel',
              style: TextStyle(color: _navy, fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _load,
              child: const Icon(CupertinoIcons.arrow_clockwise, size: 20, color: _muted),
            ),
          ),

          if (_loading)
            const SliverFillRemaining(child: Center(child: CupertinoActivityIndicator()))
          else if (_error != null)
            SliverFillRemaining(
              child: Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.exclamationmark_circle, color: _muted, size: 32),
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: _muted, fontSize: 14)),
                  const SizedBox(height: 16),
                  CupertinoButton(onPressed: _load, child: const Text('Reintentar')),
                ],
              )),
            )
          else ...[

            // ── My KPIs ──────────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(children: [
                  _Kpi(label: 'Mis asignadas', value: '${_mine.length}',
                      icon: CupertinoIcons.doc_text_fill, color: _blue),
                  const SizedBox(width: 10),
                  _Kpi(label: 'Vencen pronto', value: '$_myUrgent',
                      icon: CupertinoIcons.clock_fill,
                      color: _myUrgent == 0 ? _muted : _red),
                  const SizedBox(width: 10),
                  _Kpi(label: 'Equipo total', value: '$_teamTotal',
                      icon: CupertinoIcons.person_2_fill, color: _navy),
                ]),
              ),
            ),

            // ── My licitaciones ──────────────────────────────────────────────────
            SliverToBoxAdapter(child: _SectionHeader(
              label: 'Mis licitaciones', count: _mine.length,
              color: _blue, icon: CupertinoIcons.person_circle_fill,
            )),

            if (_mine.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'No tienes licitaciones asignadas. Ve a Licitaciones y pulsa "Añadir a mi panel".',
                      style: TextStyle(fontSize: 13, color: _muted),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _LicRow(
                      licitacion: _mine[i],
                      onRefresh: _load,
                    ),
                    childCount: _mine.length,
                  ),
                ),
              ),

            // ── Team workload ────────────────────────────────────────────────────
            SliverToBoxAdapter(child: _SectionHeader(
              label: 'Equipo', count: _teamTotal,
              color: _navy, icon: CupertinoIcons.person_2_fill,
            )),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final u = _team[i];
                    final expanded = _expanded.contains(u.userId);
                    return _VendedorSection(
                      user: u,
                      expanded: expanded,
                      onToggle: () => setState(() {
                        if (expanded) { _expanded.remove(u.userId); }
                        else { _expanded.add(u.userId); }
                      }),
                      onRefresh: _load,
                    );
                  },
                  childCount: _team.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _SectionHeader({required this.label, required this.count, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700,
          color: color, letterSpacing: -0.2)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$count', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
      ]),
    );
  }
}

// ── KPI chip ──────────────────────────────────────────────────────────────────

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Kpi({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.5)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ── Vendedor expandable section ───────────────────────────────────────────────

class _VendedorSection extends StatelessWidget {
  final WorkloadUser user;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onRefresh;

  const _VendedorSection({
    required this.user,
    required this.expanded,
    required this.onToggle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final count = user.licitaciones.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Header row — always visible
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                // Avatar
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _avatarColor(user.userId).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _initials(user.displayName),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _avatarColor(user.userId)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.displayName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
                      Text(user.email,
                          style: const TextStyle(fontSize: 11, color: _muted)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: count == 0 ? const Color(0xFFF3F4F6) : _blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    count == 0 ? 'Sin asignar' : '$count licitacion${count == 1 ? '' : 'es'}',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: count == 0 ? _muted : _blue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(CupertinoIcons.chevron_down, size: 14, color: _muted),
                ),
              ]),
            ),
          ),

          // Expanded licitaciones
          if (expanded && count > 0) ...[
            Container(height: 0.5, margin: const EdgeInsets.symmetric(horizontal: 16), color: const Color(0xFFE5E7EB)),
            ...user.licitaciones.map((l) => _WorkloadLicRow(lic: l, onRefresh: onRefresh)),
            const SizedBox(height: 4),
          ],

          if (expanded && count == 0)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('Sin licitaciones asignadas.',
                  style: TextStyle(fontSize: 13, color: _muted)),
            ),
        ],
      ),
    );
  }
}

// ── Workload licitacion row ───────────────────────────────────────────────────

class _WorkloadLicRow extends StatelessWidget {
  final WorkloadLic lic;
  final VoidCallback onRefresh;
  const _WorkloadLicRow({required this.lic, required this.onRefresh});

  String? _deadlineLabel() {
    final d = lic.fechaLimiteOferta;
    if (d == null) return null;
    try {
      final date = DateTime.parse(d);
      final diff = date.difference(DateTime.now()).inDays;
      if (diff < 0) return 'Expirada';
      if (diff == 0) return 'Hoy';
      if (diff == 1) return 'Mañana';
      if (diff <= 7) return '$diff días';
      return DateFormat('d MMM', 'es').format(date);
    } catch (_) { return null; }
  }

  Color _deadlineColor() {
    final d = lic.fechaLimiteOferta;
    if (d == null) return _muted;
    try {
      final diff = DateTime.parse(d).difference(DateTime.now()).inDays;
      if (diff <= 7) return _red;
      if (diff <= 14) return _gold;
      return _muted;
    } catch (_) { return _muted; }
  }

  @override
  Widget build(BuildContext context) {
    final deadline = _deadlineLabel();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PipelineBadge(stage: lic.pipelineStage),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lic.titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _ink, height: 1.3)),
                const SizedBox(height: 4),
                Row(children: [
                  if (lic.importe != null) ...[
                    Text('€${_fmt(lic.importe!)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _navy)),
                    const SizedBox(width: 10),
                  ],
                  if (deadline != null)
                    Row(children: [
                      Icon(CupertinoIcons.clock, size: 11, color: _deadlineColor()),
                      const SizedBox(width: 3),
                      Text(deadline,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _deadlineColor())),
                    ]),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Admin's own licitacion row ────────────────────────────────────────────────

class _LicRow extends StatefulWidget {
  final Licitacion licitacion;
  final VoidCallback onRefresh;
  const _LicRow({required this.licitacion, required this.onRefresh});

  @override
  State<_LicRow> createState() => _LicRowState();
}

class _LicRowState extends State<_LicRow> {
  bool _pressed = false;

  String? _deadlineLabel() {
    final d = widget.licitacion.fechaLimiteOferta;
    if (d == null) return null;
    try {
      final date = DateTime.parse(d);
      final diff = date.difference(DateTime.now()).inDays;
      if (diff < 0) return 'Expirada';
      if (diff == 0) return 'Hoy';
      if (diff == 1) return 'Mañana';
      if (diff <= 7) return '$diff días';
      return DateFormat('d MMM', 'es').format(date);
    } catch (_) { return null; }
  }

  Color _deadlineColor() {
    final d = widget.licitacion.fechaLimiteOferta;
    if (d == null) return _muted;
    try {
      final diff = DateTime.parse(d).difference(DateTime.now()).inDays;
      if (diff <= 7) return _red;
      if (diff <= 14) return _gold;
      return _muted;
    } catch (_) { return _muted; }
  }

  @override
  Widget build(BuildContext context) {
    final lic = widget.licitacion;
    final deadline = _deadlineLabel();
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.selectionClick();
        Navigator.of(context)
            .push(CupertinoPageRoute(builder: (_) => LicitacionDetailScreen(licitacion: lic)))
            .then((_) => widget.onRefresh());
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: _pressed ? const Duration(milliseconds: 80) : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                PipelineBadge(stage: lic.pipelineStage),
                const Spacer(),
                if (deadline != null) Row(children: [
                  Icon(CupertinoIcons.clock, size: 12, color: _deadlineColor()),
                  const SizedBox(width: 4),
                  Text(deadline, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _deadlineColor())),
                ]),
              ]),
              const SizedBox(height: 10),
              Text(lic.titulo,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink, height: 1.3)),
              const SizedBox(height: 8),
              Row(children: [
                if (lic.mercadoVertical != null) ...[
                  const Icon(CupertinoIcons.tag, size: 12, color: _muted),
                  const SizedBox(width: 4),
                  Expanded(child: Text(lic.mercadoVertical!,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _muted))),
                ] else const Spacer(),
                if (lic.importeLicitacion != null)
                  Text('€${_fmt(lic.importeLicitacion!)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _navy)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmt(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000)    return '${(v / 1000).toStringAsFixed(0)}K';
  return v.toStringAsFixed(0);
}

String _initials(String name) {
  final parts = name.trim().split(' ');
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  return name.isNotEmpty ? name[0].toUpperCase() : '?';
}

Color _avatarColor(int id) {
  const colors = [
    Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFF059669),
    Color(0xFFD97706), Color(0xFFDC2626), Color(0xFF0891B2),
  ];
  return colors[id % colors.length];
}
