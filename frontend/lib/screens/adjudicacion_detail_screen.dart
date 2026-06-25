import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/client.dart';
import '../api/models.dart';

const _teal = Color(0xFF0D9488);
const _gold = Color(0xFFF59E0B);

const _purple = Color(0xFF7C3AED);
const _navy   = Color(0xFF1E1B4B);
const _ink    = Color(0xFF111827);
const _muted  = Color(0xFF6B7280);
const _border = Color(0xFFE5E7EB);
const _white  = Color(0xFFFFFFFF);
const _bg     = Color(0xFFF8FAFC);
const _green  = Color(0xFF16A34A);

String _fmtEurFull(double v) {
  final s = v.toStringAsFixed(2).replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => '.',
  ).replaceFirst(RegExp(r'\.(\d{2})$'), ',\$1');
  return '$s €';
}

String _fmtDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

Widget _divider() => Container(
  margin: const EdgeInsets.symmetric(horizontal: 16),
  height: 1,
  color: _border,
);

// ── Screen ────────────────────────────────────────────────────────────────────

class AdjudicacionDetailScreen extends StatefulWidget {
  final Adjudicacion adj;
  const AdjudicacionDetailScreen({super.key, required this.adj});

  @override
  State<AdjudicacionDetailScreen> createState() => _AdjudicacionDetailScreenState();
}

class _AdjudicacionDetailScreenState extends State<AdjudicacionDetailScreen> {
  late Adjudicacion _adj;
  bool _loadingDetail = false;

  @override
  void initState() {
    super.initState();
    _adj = widget.adj;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _loadingDetail = true);
    try {
      final full = await ApiClient().getAdjudicacion(_adj.id);
      if (mounted) setState(() => _adj = full);
    } catch (_) {
      // Keep the list-level data we already have
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: _bg,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: _bg,
        border: null,
        previousPageTitle: 'Atrás',
        middle: Text(
          _adj.titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _navy,
            letterSpacing: -0.2,
          ),
        ),
        trailing: _adj.externalId != null
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () {
                  final url = 'https://contrataciondelestado.es/wps/poc?uri=deeplink:detalle_licitacion&idEvol=${_adj.externalId}';
                  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
                child: const Icon(CupertinoIcons.globe, size: 20, color: _purple),
              )
            : null,
      ),
      child: SafeArea(
        child: _loadingDetail && _adj.tipoProcedimiento == null && _adj.tipoTramitacion == null
            ? const Center(child: CupertinoActivityIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Organismo
                    if (_adj.organismoNombre != null) ...[
                      const Text(
                        'Organismo licitador',
                        style: TextStyle(fontSize: 10, color: _muted, letterSpacing: 0.2),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _adj.organismoNombre!,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ── Adjudicatario + importe ──────────────────────────
                    if (_adj.adjudicatarioNombre != null || _adj.importeAdjudicado != null) ...[
                      _DataCard(children: [
                        if (_adj.adjudicatarioNombre != null) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                            child: Row(
                              children: [
                                Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                    color: _purple.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(CupertinoIcons.person_fill, size: 14, color: _purple),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _adj.adjudicatarioNombre!,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _purple),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_adj.adjudicatarioNombre != null && _adj.importeAdjudicado != null)
                          _divider(),
                        if (_adj.importeAdjudicado != null)
                          _DataRow(
                            label: 'Importe adjudicado',
                            value: '${_fmtEurFull(_adj.importeAdjudicado!)} (IVA no incluido)',
                            bold: true,
                            valueColor: _green,
                          ),
                        if (_adj.importeAdjudicado != null && _adj.importe != null)
                          _divider(),
                        if (_adj.importe != null)
                          _DataRow(
                            label: 'Importe licitación',
                            value: '${_fmtEurFull(_adj.importe!)} (IVA no incluido)',
                          ),
                        if (_adj.importe != null && _adj.valorEstimado != null)
                          _divider(),
                        if (_adj.valorEstimado != null)
                          _DataRow(
                            label: 'Valor estimado',
                            value: '${_fmtEurFull(_adj.valorEstimado!)} (IVA no incluido)',
                            valueColor: _muted,
                          ),
                        if (_adj.ratio != null) ...[
                          _divider(),
                          _DataRow(
                            label: 'Ratio adj./licit.',
                            value: '${(_adj.ratio! * 100).toStringAsFixed(1)} %',
                          ),
                        ],
                      ]),
                      const SizedBox(height: 10),
                    ],

                    // ── Expediente + procedimiento ───────────────────────
                    _DataCard(children: [
                      _DataRow(label: 'Número de expediente', value: _adj.numeroExpediente, mono: true),
                      if (_adj.tipoProcedimiento != null) ...[
                        _divider(),
                        _DataRow(label: 'Tipo de procedimiento', value: _adj.tipoProcedimiento!),
                      ],
                      if (_adj.tipoTramitacion != null) ...[
                        _divider(),
                        _DataRow(label: 'Tipo de tramitación', value: _adj.tipoTramitacion!),
                      ],
                      if (_adj.cpvLabel != null) ...[
                        _divider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Expanded(
                                flex: 4,
                                child: Text('Clasificación CPV', style: TextStyle(fontSize: 13, color: _muted)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 5,
                                child: Text(
                                  _adj.cpvLabel!,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 12, color: _ink),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 10),

                    // ── Duración + fechas ────────────────────────────────
                    if (_adj.fechaAdjudicacion != null || _adj.fechaVencimientoContrato != null ||
                        _adj.duracionMeses != null || _adj.prorrogasMeses != null) ...[
                      _DataCard(children: [
                        if (_adj.fechaAdjudicacion != null) ...[
                          _DataRow(
                            label: 'Fecha de adjudicación',
                            value: _fmtDate(_adj.fechaAdjudicacion!),
                            icon: CupertinoIcons.calendar,
                          ),
                        ],
                        if (_adj.fechaAdjudicacion != null && _adj.fechaVencimientoContrato != null)
                          _divider(),
                        if (_adj.fechaVencimientoContrato != null)
                          _DataRow(
                            label: 'Vencimiento contrato',
                            value: _fmtDate(_adj.fechaVencimientoContrato!),
                            icon: CupertinoIcons.calendar_badge_minus,
                          ),
                        if ((_adj.fechaAdjudicacion != null || _adj.fechaVencimientoContrato != null) &&
                            _adj.duracionMeses != null)
                          _divider(),
                        if (_adj.duracionMeses != null)
                          _DataRow(label: 'Duración', value: '${_adj.duracionMeses} meses'),
                        if (_adj.duracionMeses != null && _adj.prorrogasMeses != null)
                          _divider(),
                        if (_adj.prorrogasMeses != null)
                          _DataRow(label: 'Prórrogas', value: '${_adj.prorrogasMeses} meses'),
                      ]),
                      const SizedBox(height: 10),
                    ],

                    // ── Localización ────────────────────────────────────
                    if (_adj.comunidadAutonoma != null || _adj.provincia != null || _adj.ambitoGeografico != null) ...[
                      _DataCard(children: [
                        if (_adj.comunidadAutonoma != null)
                          _DataRow(label: 'Comunidad Autónoma', value: _adj.comunidadAutonoma!),
                        if (_adj.comunidadAutonoma != null && _adj.provincia != null)
                          _divider(),
                        if (_adj.provincia != null)
                          _DataRow(label: 'Provincia', value: _adj.provincia!),
                        if ((_adj.comunidadAutonoma != null || _adj.provincia != null) && _adj.ambitoGeografico != null)
                          _divider(),
                        if (_adj.ambitoGeografico != null)
                          _DataRow(label: 'Ámbito geográfico', value: _adj.ambitoGeografico!),
                      ]),
                      const SizedBox(height: 10),
                    ],

                    // ── Puntuaciones ─────────────────────────────────────
                    if (_adj.puntosPrecio != null || _adj.puntosMejoras != null || _adj.puntosSubjetivos != null) ...[
                      _DataCard(children: [
                        _SectionHeader(label: 'Criterios de valoración'),
                        if (_adj.puntosPrecio != null)
                          _DataRow(label: 'Criterios precio', value: '${_adj.puntosPrecio} pts'),
                        if (_adj.puntosPrecio != null && _adj.puntosMejoras != null)
                          _divider(),
                        if (_adj.puntosMejoras != null)
                          _DataRow(label: 'Mejoras técnicas', value: '${_adj.puntosMejoras} pts'),
                        if ((_adj.puntosPrecio != null || _adj.puntosMejoras != null) && _adj.puntosSubjetivos != null)
                          _divider(),
                        if (_adj.puntosSubjetivos != null)
                          _DataRow(label: 'Criterios subjetivos', value: '${_adj.puntosSubjetivos} pts'),
                      ]),
                      const SizedBox(height: 10),
                    ],

                    // ── Mercado / vertical ───────────────────────────────
                    if (_adj.mercadoVertical != null) ...[
                      _DataCard(children: [
                        _DataRow(label: 'Mercado vertical', value: _adj.mercadoVertical!),
                      ]),
                      const SizedBox(height: 10),
                    ],

                    // ── Datos comerciales (cotizaciones de la licitación) ─
                    if (_adj.cotizaciones.isNotEmpty) ...[
                      _DatosComerciales(cotizaciones: _adj.cotizaciones),
                      const SizedBox(height: 10),
                    ],

                    // ── Licitación relacionada ───────────────────────────
                    if (_adj.licitacionId != null) ...[
                      _RelatedLicitacion(licitacionId: _adj.licitacionId!),
                      const SizedBox(height: 10),
                    ],

                    // ── Portal link ──────────────────────────────────────
                    if (_adj.externalId != null) ...[
                      _PortalLinkCard(externalId: _adj.externalId!),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

// ── Related licitacion card ───────────────────────────────────────────────────

class _RelatedLicitacion extends StatelessWidget {
  final int licitacionId;
  const _RelatedLicitacion({required this.licitacionId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // We navigate back so user can find it in Licitaciones – or just show the id
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Licitación vinculada'),
            content: Text('ID de licitación: $licitacionId'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _purple.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(CupertinoIcons.doc_text, size: 16, color: _purple),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Ver licitación vinculada',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _purple),
                ),
              ),
              const Icon(CupertinoIcons.chevron_right, size: 13, color: _purple),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Portal link card ──────────────────────────────────────────────────────────

class _PortalLinkCard extends StatelessWidget {
  final String externalId;
  const _PortalLinkCard({required this.externalId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final url = 'https://contrataciondelestado.es/wps/poc?uri=deeplink:detalle_licitacion&idEvol=$externalId';
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
      child: Container(
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(color: _navy.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(CupertinoIcons.globe, size: 16, color: _muted),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Ver en el Portal de Contratación',
                  style: TextStyle(fontSize: 13, color: _muted),
                ),
              ),
              const Icon(CupertinoIcons.arrow_up_right, size: 13, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Datos Comerciales ─────────────────────────────────────────────────────────

class _DatosComerciales extends StatelessWidget {
  final List<ClienteCotizacion> cotizaciones;
  const _DatosComerciales({required this.cotizaciones});

  String _estadoLabel(String? e) {
    if (e == null) return '—';
    const map = {
      'nueva': 'Sin gestionar',
      'asignada': 'Asignada',
      'cotizacion_solicitada': 'Cotización solicitada',
      'cotizaciones_enviadas': 'Cotización enviada',
      'ganada': 'Ganada',
      'perdida': 'Perdida',
      'desierta': 'Desierta',
    };
    return map[e] ?? e;
  }

  Color _estadoColor(String? e) {
    switch (e) {
      case 'ganada': return _teal;
      case 'perdida':
      case 'desierta': return const Color(0xFFDC2626);
      case 'cotizaciones_enviadas': return const Color(0xFF2563EB);
      default: return _muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Icon(CupertinoIcons.briefcase_fill, size: 11, color: _gold),
                ),
                const SizedBox(width: 8),
                const Text(
                  'DATOS COMERCIALES',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _muted,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ...cotizaciones.asMap().entries.map((entry) {
            final i = entry.key;
            final c = entry.value;
            final isLast = i == cotizaciones.length - 1;
            return Column(
              children: [
                Container(height: 1, color: _border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Client name + estado badge
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.clienteNombre,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _estadoColor(c.estado).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _estadoLabel(c.estado),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _estadoColor(c.estado),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Extra flags
                      if (c.sePresenta || c.vaConPliego == true || c.fabricanteProteccion) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (c.sePresenta)
                              _Flag(label: 'Se presenta', color: _teal),
                            if (c.vaConPliego == true)
                              _Flag(label: 'Va con pliego', color: const Color(0xFF2563EB)),
                            if (c.fabricanteProteccion)
                              _Flag(
                                label: c.fabricanteNombre != null
                                    ? 'Fab. ${c.fabricanteNombre}'
                                    : 'Protección fabricante',
                                color: _gold,
                              ),
                          ],
                        ),
                      ],
                      // Divisiones
                      if (c.divisiones.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          c.divisiones.join(' · '),
                          style: const TextStyle(fontSize: 11, color: _muted),
                        ),
                      ],
                      // Oportunidad / cotizacion IDs
                      if (c.oportunidadId != null || c.cotizacionId != null) ...[
                        const SizedBox(height: 8),
                        if (c.oportunidadId != null)
                          _IdRow(label: 'Oportunidad', value: c.oportunidadId!, link: c.oportunidad),
                        if (c.cotizacionId != null)
                          _IdRow(label: 'Cotización XV', value: c.cotizacionId!, link: c.cotizacionXv),
                      ],
                    ],
                  ),
                ),
                if (isLast) const SizedBox(height: 4),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  final String label;
  final Color color;
  const _Flag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

class _IdRow extends StatelessWidget {
  final String label;
  final String value;
  final String? link;
  const _IdRow({required this.label, required this.value, this.link});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Text('$label: ', style: const TextStyle(fontSize: 11, color: _muted)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11, color: _ink, fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (link != null)
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => launchUrl(Uri.parse(link!), mode: LaunchMode.externalApplication),
            child: const Icon(CupertinoIcons.arrow_up_right_square, size: 14, color: _purple),
          ),
      ],
    ),
  );
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _DataCard extends StatelessWidget {
  final List<Widget> children;
  const _DataCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2)),
      ],
    ),
    child: Column(children: children),
  );
}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  final bool mono;
  final IconData? icon;

  const _DataRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
    this.mono = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: _muted),
          const SizedBox(width: 6),
        ],
        Expanded(
          flex: 4,
          child: Text(label, style: const TextStyle(fontSize: 13, color: _muted)),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 5,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? _ink,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _muted, letterSpacing: 0.6),
    ),
  );
}
