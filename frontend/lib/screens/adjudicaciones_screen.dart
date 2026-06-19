import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../api/client.dart';
import '../api/models.dart';
import 'adjudicacion_detail_screen.dart';

const _purple    = Color(0xFF7C3AED);
const _purpleLight = Color(0xFFF5F3FF);
const _ink       = Color(0xFF111827);
const _muted     = Color(0xFF6B7280);
const _border    = Color(0xFFE5E7EB);
const _white     = Color(0xFFFFFFFF);
const _bg        = Color(0xFFF8FAFC);

String _fmtEur(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M €';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K €';
  return '${v.toStringAsFixed(0)} €';
}

class AdjudicacionesScreen extends StatefulWidget {
  // recientes: if non-null, filters to last N days (pass '2' for 48h chip)
  final String? recientes;
  const AdjudicacionesScreen({super.key, this.recientes});

  @override
  State<AdjudicacionesScreen> createState() => _AdjudicacionesScreenState();
}

class _AdjudicacionesScreenState extends State<AdjudicacionesScreen> {
  final _api = ApiClient();
  final _scrollController = ScrollController();

  List<Adjudicacion> _items = [];
  int _page = 1;
  int _total = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final page = await _api.getAdjudicaciones(
        page: 1,
        recientes: widget.recientes,
      );
      if (mounted) {
        setState(() {
          _items = page.data;
          _total = page.total;
          _page = 1;
          _hasMore = page.data.length < page.total;
        });
      }
    } catch (e) {
      if (mounted) { setState(() => _error = e.toString()); }
    } finally {
      if (mounted) { setState(() => _loading = false); }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final next = await _api.getAdjudicaciones(
        page: _page + 1,
        recientes: widget.recientes,
      );
      if (mounted) {
        setState(() {
          _items.addAll(next.data);
          _page++;
          _hasMore = _items.length < _total;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.recientes != null ? 'Adjudicaciones recientes' : 'Adjudicaciones';

    return CupertinoPageScaffold(
      backgroundColor: _bg,
      child: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, _) => [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            largeTitle: Text(title),
            trailing: _total > 0
                ? Text('$_total', style: const TextStyle(fontSize: 13, color: _muted, fontWeight: FontWeight.w500))
                : null,
          ),
        ],
        body: _error != null
            ? Center(child: Text(_error!, style: const TextStyle(color: _muted)))
            : _items.isEmpty && !_loading
                ? const Center(child: Text('Sin adjudicaciones', style: TextStyle(color: _muted)))
                : CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) {
                              if (i == _items.length) {
                                return _loading
                                    ? const Padding(
                                        padding: EdgeInsets.all(20),
                                        child: Center(child: CupertinoActivityIndicator()),
                                      )
                                    : const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _AdjudicacionCard(adj: _items[i]),
                              );
                            },
                            childCount: _items.length + 1,
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _AdjudicacionCard extends StatefulWidget {
  final Adjudicacion adj;
  const _AdjudicacionCard({required this.adj});

  @override
  State<_AdjudicacionCard> createState() => _AdjudicacionCardState();
}

class _AdjudicacionCardState extends State<_AdjudicacionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.adj;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(
            CupertinoPageRoute(
              builder: (_) => AdjudicacionDetailScreen(adj: a),
            ),
          );
        },
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _hovered ? _purpleLight : _white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovered ? _purple.withValues(alpha: 0.4) : _border,
          ),
          boxShadow: _hovered
              ? [BoxShadow(color: _purple.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))]
              : [],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: purple badge + titulo
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _purple,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Adjudicación',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _white, letterSpacing: 0.2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      a.titulo,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (a.importeAdjudicado != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      _fmtEur(a.importeAdjudicado!),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _purple),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 8),

              // Organismo
              if (a.organismoNombre != null)
                Row(children: [
                  const Icon(CupertinoIcons.building_2_fill, size: 11, color: _muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      a.organismoNombre!,
                      style: const TextStyle(fontSize: 12, color: _muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),

              // Adjudicatario
              if (a.adjudicatarioNombre != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(CupertinoIcons.person_fill, size: 11, color: _purple),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      a.adjudicatarioNombre!,
                      style: const TextStyle(fontSize: 12, color: _purple, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ],

              const SizedBox(height: 8),

              // Footer row: fecha · mercado · expediente
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (a.fechaAdjudicacion != null)
                    _Chip(CupertinoIcons.calendar, a.fechaAdjudicacion!),
                  if (a.mercadoVertical != null)
                    _Chip(CupertinoIcons.tag_fill, a.mercadoVertical!),
                  if (a.comunidadAutonoma != null)
                    _Chip(CupertinoIcons.map_pin_ellipse, a.comunidadAutonoma!),
                  if (a.numeroExpediente.isNotEmpty)
                    _Chip(CupertinoIcons.doc, a.numeroExpediente),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: _muted),
      const SizedBox(width: 3),
      Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
    ],
  );
}
