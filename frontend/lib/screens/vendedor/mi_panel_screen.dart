import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api/client.dart';
import '../../api/models.dart';
import '../../widgets/pipeline_badge.dart';
import '../licitacion_detail_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _navy   = Color(0xFF0F1F3D);
const _blue   = Color(0xFF2563EB);
const _ink    = Color(0xFF111827);
const _muted  = Color(0xFF6B7280);
const _bg     = Color(0xFFF1F4F9);
const _white  = Color(0xFFFFFFFF);
const _red    = Color(0xFFDC2626);

class MiPanelScreen extends StatefulWidget {
  const MiPanelScreen({super.key});

  @override
  State<MiPanelScreen> createState() => _MiPanelScreenState();
}

class _MiPanelScreenState extends State<MiPanelScreen> {
  List<Licitacion> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await ApiClient().getMyLicitaciones();
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  // ── Derived data ─────────────────────────────────────────────────────────────

  List<Licitacion> get _urgentes => _items.where((l) {
    final d = l.fechaLimiteOferta;
    if (d == null) return false;
    try {
      final diff = DateTime.parse(d).difference(DateTime.now()).inDays;
      return diff >= 0 && diff <= 7;
    } catch (_) { return false; }
  }).toList()..sort((a, b) => (a.fechaLimiteOferta ?? '').compareTo(b.fechaLimiteOferta ?? ''));

  List<Licitacion> get _resto => _items.where((l) {
    final d = l.fechaLimiteOferta;
    if (d == null) return true;
    try {
      final diff = DateTime.parse(d).difference(DateTime.now()).inDays;
      return diff > 7 || diff < 0;
    } catch (_) { return true; }
  }).toList();

  double get _totalImporte => _items.fold(0, (s, l) => s + (l.importeLicitacion ?? 0));

  // ── Decline flow ──────────────────────────────────────────────────────────────

  Future<void> _confirmDecline(Licitacion lic) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('No me interesa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            const Text(
              'Esto notificará a tu administrador. Puede reasignártela.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            CupertinoTextField(
              controller: reasonCtrl,
              placeholder: 'Motivo (opcional)',
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Declinar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient().declineLicitacion(lic.id,
          reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim());
      HapticFeedback.lightImpact();
      await _load();
    } catch (e) {
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Error'),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          actions: [
            CupertinoDialogAction(child: const Text('OK'), onPressed: () => Navigator.pop(context)),
          ],
        ),
      );
    }
  }

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
          else if (_items.isEmpty)
            const SliverFillRemaining(
              child: Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.tray, color: _muted, size: 40),
                  SizedBox(height: 14),
                  Text('Sin licitaciones asignadas',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _navy)),
                  SizedBox(height: 6),
                  Text('Ve a Licitaciones y pulsa "Añadir a mi panel" en las que te interesen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: _muted)),
                ],
              )),
            )
          else ...[
            // ── KPI strip ───────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(
                  children: [
                    _Kpi(
                      label: 'Asignadas',
                      value: '${_items.length}',
                      icon: CupertinoIcons.doc_text_fill,
                      color: _blue,
                    ),
                    const SizedBox(width: 10),
                    _Kpi(
                      label: 'Vencen pronto',
                      value: '${_urgentes.length}',
                      icon: CupertinoIcons.clock_fill,
                      color: _urgentes.isEmpty ? _muted : _red,
                    ),
                    const SizedBox(width: 10),
                    _Kpi(
                      label: 'Importe total',
                      value: _fmtImporte(_totalImporte),
                      icon: CupertinoIcons.money_euro_circle_fill,
                      color: _navy,
                    ),
                  ],
                ),
              ),
            ),

            // ── Urgentes ────────────────────────────────────────────────────────
            if (_urgentes.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 4, height: 16,
                        decoration: BoxDecoration(
                          color: _red, borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Plazo próximo',
                        style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: _red, letterSpacing: -0.2),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_urgentes.length}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _LicitacionRow(
                      licitacion: _urgentes[i],
                      urgent: true,
                      onDecline: () => _confirmDecline(_urgentes[i]),
                      onRefresh: _load,
                    ),
                    childCount: _urgentes.length,
                  ),
                ),
              ),
            ],

            // ── Resto ────────────────────────────────────────────────────────────
            if (_resto.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 4, height: 16,
                        decoration: BoxDecoration(
                          color: _blue, borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Mis licitaciones',
                        style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: _navy, letterSpacing: -0.2),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_resto.length}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _LicitacionRow(
                      licitacion: _resto[i],
                      urgent: false,
                      onDecline: () => _confirmDecline(_resto[i]),
                      onRefresh: _load,
                    ),
                    childCount: _resto.length,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
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
          boxShadow: [
            BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800,
                color: color, letterSpacing: -0.5),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ── Licitacion row (same tile design as licitaciones_screen) ─────────────────

const _kEaseOutExpo = Cubic(0.16, 1.0, 0.3, 1.0);

class _LicitacionRow extends StatefulWidget {
  final Licitacion licitacion;
  final bool urgent;
  final VoidCallback onDecline;
  final VoidCallback onRefresh;

  const _LicitacionRow({
    required this.licitacion,
    required this.urgent,
    required this.onDecline,
    required this.onRefresh,
  });

  @override
  State<_LicitacionRow> createState() => _LicitacionRowState();
}

class _LicitacionRowState extends State<_LicitacionRow>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l = widget.licitacion;
    final (estadoBg, estadoFg, estadoLabel) = _ingramEstadoStyle(l.ingramEstado);
    final isUrgentDeadline = l.fechaLimiteOferta != null && _isUrgent(l.fechaLimiteOferta!);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            HapticFeedback.selectionClick();
            Navigator.of(context)
                .push(CupertinoPageRoute(
                    builder: (_) => LicitacionDetailScreen(licitacion: l)))
                .then((_) => widget.onRefresh());
          },
          onTapCancel: () => setState(() => _pressed = false),
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _pressed ? 0.975 : 1.0,
            duration: _pressed
                ? const Duration(milliseconds: 70)
                : const Duration(milliseconds: 280),
            curve: _pressed ? Curves.easeIn : _kEaseOutExpo,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(12),
                border: widget.urgent
                    ? Border.all(color: _red.withValues(alpha: 0.30), width: 1)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: _navy.withValues(alpha: _hovered ? 0.11 : 0.065),
                    blurRadius: _hovered ? 18 : 10,
                    spreadRadius: _hovered ? 0 : -1,
                    offset: Offset(0, _hovered ? 5 : 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Teal header ──────────────────────────────────────────
                    Container(
                      color: const Color(0xFF2dd4bf),
                      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              l.titulo,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: _navy,
                                height: 1.4,
                                letterSpacing: -0.15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          PipelineBadge(stage: l.pipelineStage, small: true),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: widget.onDecline,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                CupertinoIcons.xmark_circle_fill,
                                size: 17,
                                color: _navy.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Body ─────────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Organismo
                          if (l.organismoNombre != null) ...[
                            Row(
                              children: [
                                const Icon(CupertinoIcons.building_2_fill,
                                    size: 11, color: _muted),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    l.organismoNombre!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: _muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                          // Meta row: importe | fecha | deadline + outlook
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (l.importeLicitacion != null) ...[
                                _MetaCol(
                                  label: 'Importe licitación',
                                  value: _fmtEur(l.importeLicitacion!),
                                  valueStyle: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: _navy,
                                  ),
                                  sub: 'IVA no incluido',
                                ),
                                _MetaDivider(),
                              ],
                              _MetaCol(
                                label: 'Fecha licitación',
                                value: l.fecha,
                                icon: CupertinoIcons.calendar,
                              ),
                              if (l.fechaLimiteOferta != null) ...[
                                _MetaDivider(),
                                _MetaCol(
                                  label: 'Fecha límite ofertas',
                                  value: l.fechaLimiteOferta!,
                                  icon: CupertinoIcons.clock,
                                  urgent: isUrgentDeadline,
                                ),
                              ],
                              const Spacer(),
                              if (l.fechaLimiteOferta != null)
                                _OutlookButton(onTap: () => _addToOutlook(l)),
                            ],
                          ),
                          // Estado + owner footer
                          if (l.ingramEstado != null ||
                              l.ingramOwner != null ||
                              l.assigneeNombre != null) ...[
                            const SizedBox(height: 9),
                            Row(
                              children: [
                                if (l.ingramEstado != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: estadoBg,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: estadoFg.withValues(alpha: 0.18)),
                                    ),
                                    child: Text(
                                      estadoLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: estadoFg,
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                if (l.ingramOwner != null ||
                                    l.assigneeNombre != null) ...[
                                  const Icon(CupertinoIcons.person_circle_fill,
                                      size: 13, color: _muted),
                                  const SizedBox(width: 4),
                                  Text(
                                    (l.ingramOwner ?? l.assigneeNombre ?? '')
                                        .split(' ')
                                        .first,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: l.ingramOwner != null ? _blue : _muted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _addToOutlook(Licitacion l) {
    final deadline = l.fechaLimiteOferta ?? l.fecha;
    final dt = DateTime.tryParse(deadline) ?? DateTime.now();
    final subject = Uri.encodeComponent(l.titulo);
    final body = Uri.encodeComponent(
      'Expediente: ${l.numeroExpediente}\n'
      '${l.organismoNombre != null ? 'Organismo: ${l.organismoNombre}\n' : ''}'
      '${l.importeLicitacion != null ? 'Importe: ${_fmtEur(l.importeLicitacion!)}\n' : ''}',
    );
    final url = Uri.parse(
      'https://outlook.live.com/calendar/0/deeplink/compose'
      '?subject=$subject&startdt=${dt.toIso8601String().substring(0, 10)}'
      '&enddt=${dt.toIso8601String().substring(0, 10)}&body=$body&allday=true',
    );
    launchUrl(url, mode: LaunchMode.externalApplication);
  }
}

// ── Meta column ───────────────────────────────────────────────────────────────

class _MetaCol extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;
  final String? sub;
  final IconData? icon;
  final bool urgent;

  const _MetaCol({
    required this.label,
    required this.value,
    this.valueStyle,
    this.sub,
    this.icon,
    this.urgent = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor = urgent ? _red : _ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: _muted, letterSpacing: 0.1)),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: urgent ? _red : _muted),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: valueStyle ??
                  TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                  ),
            ),
          ],
        ),
        if (sub != null)
          Text(sub!, style: const TextStyle(fontSize: 10, color: _muted)),
      ],
    );
  }
}

class _MetaDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        color: const Color(0xFFE5E7EB),
      );
}

// ── Outlook button ────────────────────────────────────────────────────────────

class _OutlookButton extends StatefulWidget {
  final VoidCallback onTap;
  const _OutlookButton({required this.onTap});

  @override
  State<_OutlookButton> createState() => _OutlookButtonState();
}

class _OutlookButtonState extends State<_OutlookButton> {
  bool _hovered = false;
  static const _outlookBlue = Color(0xFF0078D4);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? _outlookBlue : _outlookBlue.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
                color: _outlookBlue.withValues(alpha: _hovered ? 0 : 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.calendar_badge_plus,
                  size: 12, color: _hovered ? _white : _outlookBlue),
              const SizedBox(width: 5),
              Text(
                'Añadir a Outlook',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _hovered ? _white : _outlookBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmtEur(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M €';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K €';
  return '${v.toStringAsFixed(0)} €';
}

String _fmtImporte(double v) {
  if (v == 0) return '—';
  if (v >= 1000000) return '€${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '€${(v / 1000).toStringAsFixed(0)}K';
  return '€${v.toStringAsFixed(0)}';
}

bool _isUrgent(String iso) {
  try {
    final diff = DateTime.parse(iso).difference(DateTime.now()).inDays;
    return diff <= 7;
  } catch (_) {
    return false;
  }
}

(Color bg, Color fg, String label) _ingramEstadoStyle(String? estado) {
  if (estado == null) { return (const Color(0xFFF3F4F6), _muted, 'Sin estado'); }
  if (estado.startsWith('PENDIENTE SOLICITUD')) {
    return (const Color(0xFFFFFBEB), const Color(0xFFD97706), 'Pend. Sol.');
  }
  if (estado.startsWith('COTIZACIÓN SOLICITADA')) {
    return (const Color(0xFFEFF6FF), _blue, 'Cotiz. Sol.');
  }
  if (estado.startsWith('PENDIENTE ENVÍO')) {
    return (const Color(0xFFF5F3FF), const Color(0xFF7C3AED), 'Pend. Envío');
  }
  if (estado.startsWith('COTIZACIÓN ENVIADA')) {
    return (const Color(0xFFECFDF5), const Color(0xFF059669), 'Enviada');
  }
  if (estado.startsWith('RECHAZADO')) {
    return (const Color(0xFFFEF2F2), _red, 'Rechazado');
  }
  return (
    const Color(0xFFF3F4F6),
    _muted,
    estado.length > 16 ? '${estado.substring(0, 14)}…' : estado,
  );
}
