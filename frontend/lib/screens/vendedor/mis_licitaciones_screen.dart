import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../api/client.dart';
import '../../api/models.dart';
import '../../widgets/pipeline_badge.dart';
import '../licitacion_detail_screen.dart';

const _navy  = Color(0xFF0F1F3D);
const _gold  = Color(0xFFF59E0B);
const _ink   = Color(0xFF111827);
const _muted = Color(0xFF6B7280);
const _bg    = Color(0xFFF1F4F9);
const _white = Color(0xFFFFFFFF);
const _red   = Color(0xFFDC2626);

class MisLicitacionesScreen extends StatefulWidget {
  const MisLicitacionesScreen({super.key});

  @override
  State<MisLicitacionesScreen> createState() => _MisLicitacionesScreenState();
}

class _MisLicitacionesScreenState extends State<MisLicitacionesScreen> {
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
      if (mounted) {
        setState(() { _items = items; _loading = false; });
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

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: _bg,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            backgroundColor: _bg,
            border: null,
            largeTitle: const Text(
              'Mis Licitaciones',
              style: TextStyle(
                color: _navy,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _load,
              child: const Icon(CupertinoIcons.arrow_clockwise, size: 20, color: _muted),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_circle, color: _muted, size: 32),
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: _muted, fontSize: 14)),
                    const SizedBox(height: 16),
                    CupertinoButton(onPressed: _load, child: const Text('Reintentar')),
                  ],
                ),
              ),
            )
          else if (_items.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.tray, color: _muted, size: 40),
                    SizedBox(height: 14),
                    Text(
                      'Sin licitaciones asignadas',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _navy),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Tu administrador te asignará licitaciones aquí.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: _muted),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _LicitacionCard(
                    licitacion: _items[i],
                    onDecline: () => _confirmDecline(_items[i]),
                    onRefresh: _load,
                  ),
                  childCount: _items.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

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
            Text(
              'Esto notificará a tu administrador. Puede reasignártela.',
              style: const TextStyle(fontSize: 13),
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
      await ApiClient().declineLicitacion(
        lic.id,
        reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      );
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
}

// ── Licitacion card ───────────────────────────────────────────────────────────

class _LicitacionCard extends StatefulWidget {
  final Licitacion licitacion;
  final VoidCallback onDecline;
  final VoidCallback onRefresh;

  const _LicitacionCard({
    required this.licitacion,
    required this.onDecline,
    required this.onRefresh,
  });

  @override
  State<_LicitacionCard> createState() => _LicitacionCardState();
}

class _LicitacionCardState extends State<_LicitacionCard> {
  bool _pressed = false;

  String? _formattedDeadline() {
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
    } catch (_) { return d; }
  }

  Color _deadlineColor() {
    final d = widget.licitacion.fechaLimiteOferta;
    if (d == null) return _muted;
    try {
      final diff = DateTime.parse(d).difference(DateTime.now()).inDays;
      if (diff < 0) return _red;
      if (diff <= 7) return _red;
      if (diff <= 14) return _gold;
      return _muted;
    } catch (_) { return _muted; }
  }

  @override
  Widget build(BuildContext context) {
    final lic = widget.licitacion;
    final deadline = _formattedDeadline();

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.selectionClick();
        Navigator.of(context).push(CupertinoPageRoute(
          builder: (_) => LicitacionDetailScreen(licitacion: lic),
        )).then((_) => widget.onRefresh());
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: _pressed
            ? const Duration(milliseconds: 80)
            : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _navy.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PipelineBadge(stage: lic.pipelineStage),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: widget.onDecline,
                    child: const Icon(
                      CupertinoIcons.xmark_circle,
                      size: 20,
                      color: _muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                lic.titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (lic.mercadoVertical != null) ...[
                    const Icon(CupertinoIcons.tag, size: 12, color: _muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        lic.mercadoVertical!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (lic.importeLicitacion != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '€${_fmt(lic.importeLicitacion!)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _navy,
                      ),
                    ),
                  ],
                ],
              ),
              if (deadline != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(CupertinoIcons.clock, size: 12, color: _deadlineColor()),
                    const SizedBox(width: 4),
                    Text(
                      deadline,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _deadlineColor(),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}
