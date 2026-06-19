import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/client.dart';
import '../api/models.dart';
import '../data/cat_tree.dart';
import '../widgets/pipeline_badge.dart';
import '../widgets/skeleton_tile.dart';
import '../widgets/liti_chat_overlay.dart';
import 'licitacion_detail_screen.dart';

const _navy = Color(0xFF0F1F3D);
const _blue = Color(0xFF2563EB);
const _gold = Color(0xFFF59E0B);
const _ink = Color(0xFF111827);
const _muted = Color(0xFF6B7280);
const _white = Color(0xFFFFFFFF);
const _green = Color(0xFF059669);
const _red = Color(0xFFDC2626);
const _border = Color(0xFFE5E7EB);

// ── Filter option data ────────────────────────────────────────────────────────

class _FO {
  final String label;
  final String value;
  const _FO(this.label, this.value);
}

class _FC {
  final String key;
  final String title;
  final IconData icon;
  final Color color;
  final List<_FO> options;
  const _FC({
    required this.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.options,
  });
}

const _filterCategories = [
  _FC(
    key: 'deadlineRange',
    title: 'Plazo restante',
    icon: CupertinoIcons.clock_fill,
    color: _gold,
    options: [
      _FO('< 7 días', 'lt7'),
      _FO('< 15 días', 'lt15'),
      _FO('< 30 días', 'lt30'),
      _FO('> 30 días', 'gt30'),
    ],
  ),
  _FC(
    key: 'importeRange',
    title: 'Importe',
    icon: CupertinoIcons.money_euro,
    color: _blue,
    options: [
      _FO('< 50K', 'lt50k'),
      _FO('50K – 100K', '50-100k'),
      _FO('100K – 250K', '100-250k'),
      _FO('250K – 500K', '250-500k'),
      _FO('500K – 1M', '500k-1m'),
      _FO('> 1M', 'gt1m'),
    ],
  ),
  _FC(
    key: 'ingramEstado',
    title: 'Estado Ingram',
    icon: CupertinoIcons.briefcase_fill,
    color: Color(0xFF7C3AED),
    options: [
      _FO('Pend. solicitud a división', 'PENDIENTE SOLICITUD DE COTIZACIÓN A LA DIVISIÓN'),
      _FO('Cotiz. solicitada a división', 'COTIZACIÓN SOLICITADA (A LA DIVISIÓN)'),
      _FO('Pend. envío a cliente', 'PENDIENTE ENVÍO DE COTIZACIÓN A CLIENTE'),
      _FO('Enviada a cliente (X4A)', 'COTIZACIÓN ENVIADA A CLIENTE - X4A'),
      _FO('Rechazado', 'RECHAZADO'),
    ],
  ),
  _FC(
    key: 'division',
    title: 'División',
    icon: CupertinoIcons.person_2_fill,
    color: Color(0xFFDB2777),
    options: [
      _FO('Alan Jaumandreu', 'DIVISIÓN ALAN JAUMANDREU'),
      _FO('Jorge Nicolás', 'DIVISIÓN JORGE NICOLÁS'),
      _FO('Servicios (Oscar González)', 'DIVISIÓN SERVICIOS (OSCAR GONZÁLEZ)'),
      _FO('Martin Trullas', 'DIVISIÓN MARTIN TRULLAS'),
      _FO('AVPRO/UCC (Alex Rincón)', 'DIVISIÓN AVPRO/UCC (ALEX RINCÓN)'),
      _FO('DCPOS/PHSEC (Sergio Patiño)', 'DIVISIÓN DCPOS/PHSEC (SERGIO PATIÑO)'),
      _FO('Cloud', 'DIVISIÓN CLOUD'),
    ],
  ),
  _FC(
    key: 'cat1',
    title: 'Área tecnológica',
    icon: CupertinoIcons.desktopcomputer,
    color: Color(0xFF0891B2),
    options: [
      _FO('Hardware', 'Hardware'),
      _FO('Software', 'Software'),
      _FO('Servicios', 'Servicios'),
      _FO('Otros', 'Otros'),
    ],
  ),
  _FC(
    key: 'comunidad',
    title: 'Comunidad autónoma',
    icon: CupertinoIcons.map_fill,
    color: _green,
    options: [
      _FO('Andalucía', 'Andalucía'),
      _FO('Aragón', 'Aragón'),
      _FO('Asturias', 'Asturias Principado de'),
      _FO('Canarias', 'Canarias'),
      _FO('Cantabria', 'Cantabria'),
      _FO('C-La Mancha', 'Castilla - La Mancha'),
      _FO('Castilla y León', 'Castilla y León'),
      _FO('Catalunya', 'Catalunya'),
      _FO('Valencia', 'Comunitat Valenciana'),
      _FO('Extremadura', 'Extremadura'),
      _FO('Galicia', 'Galicia'),
      _FO('Illes Balears', 'Illes Balears'),
      _FO('Madrid', 'Madrid Comunidad de'),
      _FO('Murcia', 'Murcia Región de'),
      _FO('Navarra', 'Navarra Comunidad Floral de'),
      _FO('País Vasco', 'País Vasco'),
      _FO('La Rioja', 'Rioja La'),
    ],
  ),
  _FC(
    key: 'mercado',
    title: 'Mercado vertical',
    icon: CupertinoIcons.building_2_fill,
    color: Color(0xFFD97706),
    options: [
      _FO('Sanidad', 'SANIDAD'),
      _FO('Educación', 'EDUCACIÓN'),
      _FO('Interior', 'INTERIOR'),
      _FO('Defensa', 'DEFENSA'),
      _FO('Justicia', 'JUSTICIA'),
      _FO('Transporte', 'TRANSPORTE'),
      _FO('Hacienda', 'ECONOMÍA Y HACIENDA'),
      _FO('Empleo', 'EMPLEO Y SEGURIDAD SOCIAL'),
      _FO('Industria', 'INDUSTRIA ENERGÍA Y TURISMO'),
      _FO('TIC', 'INFORMACIÓN Y COMUNICACIONES'),
      _FO('EELL', 'OTROS EELL'),
      _FO('Otros', 'OTROS'),
    ],
  ),
  _FC(
    key: 'tipoProcedimiento',
    title: 'Tipo procedimiento',
    icon: CupertinoIcons.doc_checkmark_fill,
    color: Color(0xFF0F766E),
    options: [
      _FO('Abierto', 'Abierto'),
      _FO('Negociado', 'Negociado'),
      _FO('Negociado c/Pub', 'Negociado con Publicidad'),
      _FO('Simplificado', 'Simplificado'),
      _FO('Restringido', 'Restringido'),
      _FO('Acuerdo Marco', 'Acuerdo Marco'),
      _FO('SDA', 'Sistema Dinámico de Adquisición'),
    ],
  ),
  _FC(
    key: 'duracionRange',
    title: 'Duración (meses)',
    icon: CupertinoIcons.calendar,
    color: Color(0xFF9D174D),
    options: [
      _FO('< 6m', 'lt6'),
      _FO('6-12m', '6-12'),
      _FO('12-18m', '12-18'),
      _FO('18-24m', '18-24'),
      _FO('24-36m', '24-36'),
      _FO('36-48m', '36-48'),
      _FO('48-60m', '48-60'),
      _FO('> 72m', 'gt72'),
    ],
  ),
  _FC(
    key: 'asignada',
    title: 'Asignación',
    icon: CupertinoIcons.person_fill,
    color: Color(0xFF7C3AED),
    options: [
      _FO('Asignada', 'si'),
      _FO('Sin asignar', 'no'),
    ],
  ),
];

// CAT2/CAT3 are not in the static list — shown dynamically after parent is selected.
const _cat2FC = _FC(
  key: 'cat2',
  title: 'Subcategoría (CAT2)',
  icon: CupertinoIcons.layers_fill,
  color: Color(0xFF0369A1),
  options: [],
);
const _cat3FC = _FC(
  key: 'cat3',
  title: 'Especialidad (CAT3)',
  icon: CupertinoIcons.tag_fill,
  color: Color(0xFF6D28D9),
  options: [],
);

// ── Ingram estado helpers ─────────────────────────────────────────────────────

(Color bg, Color fg, String label) _ingramEstadoStyle(String? estado) {
  if (estado == null) return (const Color(0xFFF3F4F6), _muted, 'Sin estado');
  if (estado.startsWith('PENDIENTE SOLICITUD'))
    return (const Color(0xFFFFFBEB), const Color(0xFFD97706), 'Pend. Sol.');
  if (estado.startsWith('COTIZACIÓN SOLICITADA'))
    return (const Color(0xFFEFF6FF), _blue, 'Cotiz. Sol.');
  if (estado.startsWith('PENDIENTE ENVÍO'))
    return (const Color(0xFFF5F3FF), const Color(0xFF7C3AED), 'Pend. Envío');
  if (estado.startsWith('COTIZACIÓN ENVIADA'))
    return (const Color(0xFFECFDF5), _green, 'Enviada');
  if (estado.startsWith('RECHAZADO'))
    return (const Color(0xFFFEF2F2), _red, 'Rechazado');
  return (
    const Color(0xFFF3F4F6),
    _muted,
    estado.length > 16 ? '${estado.substring(0, 14)}…' : estado,
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class LicitacionesScreen extends StatefulWidget {
  final LicitacionFilter? filter;
  const LicitacionesScreen({super.key, this.filter});

  @override
  State<LicitacionesScreen> createState() => _LicitacionesScreenState();
}

class _LicitacionesScreenState extends State<LicitacionesScreen> {
  final _api = ApiClient();
  final _scrollController = ScrollController();

  List<Licitacion> _items = [];
  int _page = 1;
  int _total = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  String _search = '';

  // Mutable filter state (initialized from widget.filter)
  String? _fDeadlineRange;
  String? _fImporteRange;
  String? _fIngramEstado;
  String? _fCat1;
  String? _fCat2;
  String? _fCat3;
  String? _fComunidad;
  String? _fMercado;
  String? _fTipoProcedimiento;
  String? _fDuracionRange;
  String? _fDivision;
  String? _fAsignada;
  String? _fAssigneeUserIds;

  // Dynamic options for CAT2/CAT3 (loaded from stats on init)
  List<_FO> _cat2Options = const [];
  List<_FO> _cat3Options = const [];
  List<AppUser> _salespeople = [];

  // 'activas' | 'caducadas' | 'todas'
  String _deadlineView = 'activas';

  // Sort state
  String _sortBy = 'fecha_desc'; // default: newest first

  static const _sortOptions = [
    ('fecha_desc',    'Más recientes primero'),
    ('fecha_asc',     'Más antiguas primero'),
    ('importe_desc',  'Mayor importe'),
    ('importe_asc',   'Menor importe'),
    ('plazo_asc',     'Plazo más próximo'),
    ('titulo_asc',    'Título A → Z'),
  ];

  @override
  void initState() {
    super.initState();
    _applyWidgetFilter();
    _load();
    _loadCatOptions();
    _loadSalespeople();
    _scrollController.addListener(_onScroll);
    litiChat.setScreenContext('Lista de licitaciones públicas activas');
  }

  Future<void> _loadSalespeople() async {
    try {
      final users = await _api.getUsers();
      if (mounted) {
        setState(() {
          _salespeople = users.where((u) => u.role != 'admin').toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadCatOptions() async {
    try {
      final stats = await _api.getDashboardStats();
      if (!mounted) return;
      setState(() {
        _cat2Options = stats.breakdown.cat2
            .where((b) => b.value.isNotEmpty)
            .map((b) => _FO(b.label, b.value))
            .toList();
        _cat3Options = stats.breakdown.cat3
            .where((b) => b.value.isNotEmpty)
            .map((b) => _FO(b.label, b.value))
            .toList();
      });
    } catch (_) {}
  }

  void _applyWidgetFilter() {
    final f = widget.filter;
    if (f == null) return;
    _fDeadlineRange = f.deadlineRange;
    _fImporteRange = f.importeRange;
    _fIngramEstado = f.ingramEstado;
    _fCat1 = f.cat1;
    _fCat2 = f.cat2;
    _fCat3 = f.cat3;
    _fComunidad = f.comunidad;
    _fMercado = f.mercado;
    _fTipoProcedimiento = f.tipoProcedimiento;
    _fDuracionRange = f.duracionRange;
    _fDivision = f.division;
    _fAsignada = f.asignada;
    _fAssigneeUserIds = f.assigneeUserIds;
  }

  LicitacionFilter get _activeFilter {
    return LicitacionFilter(
      deadlineRange: _fDeadlineRange ?? (_deadlineView == 'todas' ? null : _deadlineView),
      importeRange: _fImporteRange,
      ingramEstado: _fIngramEstado,
      cat1: _fCat1,
      cat2: _fCat2,
      cat3: _fCat3,
      comunidad: _fComunidad,
      mercado: _fMercado,
      tipoProcedimiento: _fTipoProcedimiento,
      duracionRange: _fDuracionRange,
      division: _fDivision,
      asignada: _fAsignada,
      assigneeUserIds: _fAssigneeUserIds,
      label: _buildLabel(),
    );
  }

  String _buildLabel() {
    final parts = <String>[];
    if (_fDeadlineRange != null)
      parts.add(_labelFor('deadlineRange', _fDeadlineRange!));
    if (_fImporteRange != null)
      parts.add(_labelFor('importeRange', _fImporteRange!));
    if (_fIngramEstado != null)
      parts.add(_labelFor('ingramEstado', _fIngramEstado!));
    if (_fCat1 != null) parts.add(_labelFor('cat1', _fCat1!));
    if (_fCat2 != null) parts.add(_labelFor('cat2', _fCat2!));
    if (_fCat3 != null) parts.add(_labelFor('cat3', _fCat3!));
    if (_fComunidad != null) parts.add(_labelFor('comunidad', _fComunidad!));
    if (_fMercado != null) parts.add(_labelFor('mercado', _fMercado!));
    if (_fTipoProcedimiento != null)
      parts.add(_labelFor('tipoProcedimiento', _fTipoProcedimiento!));
    if (_fDuracionRange != null)
      parts.add(_labelFor('duracionRange', _fDuracionRange!));
    if (_fDivision != null) parts.add(_labelFor('division', _fDivision!));
    if (_fAsignada != null) {
      if (_fAsignada == 'no') {
        parts.add('Sin asignar');
      } else if (_fAsignada == 'si') {
        if (_fAssigneeUserIds != null) {
          parts.add(_labelFor('asignada', _fAssigneeUserIds!));
        } else {
          parts.add('Asignada');
        }
      }
    }
    return parts.join(' · ');
  }

  String _labelFor(String key, String value) {
    if (value.contains(',')) {
      final parts = value.split(',');
      final translated = parts.map((p) => _singleLabelFor(key, p)).toList();
      if (translated.length <= 2) {
        return translated.join(', ');
      }
      return '${translated.length} sel.';
    }
    return _singleLabelFor(key, value);
  }

  String _singleLabelFor(String key, String value) {
    if (key == 'asignada') {
      if (value == 'no') return 'Sin asignar';
      if (value == 'si') return 'Asignada';
      final parsedId = int.tryParse(value);
      if (parsedId != null) {
        final match = _salespeople.where((u) => u.id == parsedId).firstOrNull;
        if (match != null) return match.displayName;
      }
    }
    final extra = {
      'cat2': _cat2Options,
      'cat3': _cat3Options,
    }[key];
    if (extra != null) {
      final match = extra.where((o) => o.value == value).firstOrNull;
      if (match != null) return match.label;
    }
    final cat = _filterCategories.where((c) => c.key == key).firstOrNull;
    return cat?.options.where((o) => o.value == value).firstOrNull?.label ??
        value;
  }

  int get _filterCount {
    return [
      _fDeadlineRange,
      _fImporteRange,
      _fIngramEstado,
      _fCat1,
      _fCat2,
      _fCat3,
      _fComunidad,
      _fMercado,
      _fTipoProcedimiento,
      _fDuracionRange,
      _fDivision,
      _fAsignada,
    ].where((v) => v != null).length;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.getLicitaciones(page: 1, filter: _activeFilter, orderBy: _sortBy);
      if (mounted)
        setState(() {
          _items = page.data;
          _total = page.total;
          _page = 1;
          _hasMore = page.data.length < page.total;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
        });
    } finally {
      if (mounted)
        setState(() {
          _loading = false;
        });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
    });
    try {
      final next = await _api.getLicitaciones(
        page: _page + 1,
        filter: _activeFilter,
        orderBy: _sortBy,
      );
      if (mounted)
        setState(() {
          _items.addAll(next.data);
          _page++;
          _hasMore = _items.length < _total;
        });
    } catch (_) {
    } finally {
      if (mounted)
        setState(() {
          _loading = false;
        });
    }
  }

  List<Licitacion> get _filtered {
    var list = _search.isEmpty
        ? [..._items]
        : _items.where((l) =>
            l.titulo.toLowerCase().contains(_search.toLowerCase()) ||
            l.numeroExpediente.toLowerCase().contains(_search.toLowerCase()) ||
            (l.mercadoVertical?.toLowerCase().contains(_search.toLowerCase()) ?? false),
          ).toList();

    return list;
  }

  Future<void> _showSortSheet() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Ordenar por'),
        actions: [
          for (final (key, label) in _sortOptions)
            CupertinoActionSheetAction(
              onPressed: () {
                setState(() => _sortBy = key);
                Navigator.pop(context);
                _load();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label),
                  if (_sortBy == key) ...[
                    const SizedBox(width: 8),
                    const Icon(CupertinoIcons.checkmark_alt, size: 16, color: _blue),
                  ],
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ),
    );
  }

  // ── Filter sheet ──────────────────────────────────────────────────────────

  Future<void> _showFilterSheet() async {
    // Snapshot current filter state to allow cancel
    final snap = {
      'deadlineRange': _fDeadlineRange,
      'importeRange': _fImporteRange,
      'ingramEstado': _fIngramEstado,
      'cat1': _fCat1,
      'cat2': _fCat2,
      'cat3': _fCat3,
      'comunidad': _fComunidad,
      'mercado': _fMercado,
      'tipoProcedimiento': _fTipoProcedimiento,
      'duracionRange': _fDuracionRange,
      'division': _fDivision,
      'asignada': _fAsignada,
      'assigneeUserIds': _fAssigneeUserIds,
    };

    final apply = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => _FilterSheet(
        initial: {
          'deadlineRange': _fDeadlineRange,
          'importeRange': _fImporteRange,
          'ingramEstado': _fIngramEstado,
          'cat1': _fCat1,
          'cat2': _fCat2,
          'cat3': _fCat3,
          'comunidad': _fComunidad,
          'mercado': _fMercado,
          'tipoProcedimiento': _fTipoProcedimiento,
          'duracionRange': _fDuracionRange,
          'division': _fDivision,
          'asignada': _fAsignada,
          'assigneeUserIds': _fAssigneeUserIds,
        },
        extraOptions: {
          'cat2': _cat2Options,
          'cat3': _cat3Options,
        },
        onChanged: (key, value) {
          setState(() {
            switch (key) {
              case 'deadlineRange':
                _fDeadlineRange = value;
              case 'importeRange':
                _fImporteRange = value;
              case 'ingramEstado':
                _fIngramEstado = value;
              case 'cat1':
                _fCat1 = value;
              case 'cat2':
                _fCat2 = value;
              case 'cat3':
                _fCat3 = value;
              case 'comunidad':
                _fComunidad = value;
              case 'mercado':
                _fMercado = value;
              case 'tipoProcedimiento':
                _fTipoProcedimiento = value;
              case 'duracionRange':
                _fDuracionRange = value;
              case 'division':
                _fDivision = value;
              case 'asignada':
                _fAsignada = value;
              case 'assigneeUserIds':
                _fAssigneeUserIds = value;
            }
          });
        },
      ),
    );

    if (apply == true) {
      _load();
    } else {
      // Restore snapshot if cancelled
      if (mounted) {
        setState(() {
          _fDeadlineRange = snap['deadlineRange'];
          _fImporteRange = snap['importeRange'];
          _fIngramEstado = snap['ingramEstado'];
          _fCat1 = snap['cat1'];
          _fCat2 = snap['cat2'];
          _fCat3 = snap['cat3'];
          _fComunidad = snap['comunidad'];
          _fMercado = snap['mercado'];
          _fTipoProcedimiento = snap['tipoProcedimiento'];
          _fDuracionRange = snap['duracionRange'];
          _fDivision = snap['division'];
          _fAsignada = snap['asignada'];
          _fAssigneeUserIds = snap['assigneeUserIds'];
        });
      }
    }
  }

  void _clearAllFilters() {
    setState(() {
      _fDeadlineRange = _fImporteRange = _fIngramEstado = null;
      _fCat1 = _fCat2 = _fCat3 = null;
      _fComunidad = _fMercado = _fTipoProcedimiento = _fDuracionRange = null;
      _fDivision = _fAsignada = _fAssigneeUserIds = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final count = _filterCount;

    return CupertinoPageScaffold(
      child: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, _) => [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            previousPageTitle: widget.filter != null ? 'Panel' : null,
            largeTitle: Text(
              count > 0 ? 'Licitaciones ($count)' : 'Licitaciones',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Activas / Caducadas / Todas cycle
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _deadlineView = switch (_deadlineView) {
                        'activas'   => 'caducadas',
                        'caducadas' => 'todas',
                        _           => 'activas',
                      };
                    });
                    _load();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: switch (_deadlineView) {
                        'caducadas' => _red.withValues(alpha: 0.12),
                        'todas'     => _navy,
                        _           => _blue.withValues(alpha: 0.08),
                      },
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      switch (_deadlineView) {
                        'caducadas' => 'Caducadas',
                        'todas'     => 'Todas',
                        _           => 'Activas',
                      },
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: switch (_deadlineView) {
                          'caducadas' => _red,
                          'todas'     => _white,
                          _           => _blue,
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Ordenar por
                GestureDetector(
                  onTap: _showSortSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _sortBy != 'fecha_desc'
                          ? _blue
                          : _blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.arrow_up_arrow_down, size: 13,
                            color: _sortBy != 'fecha_desc' ? _white : _blue),
                        const SizedBox(width: 5),
                        Text('Ordenar',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _sortBy != 'fecha_desc' ? _white : _blue,
                            )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Filtrar por
                GestureDetector(
                  onTap: _showFilterSheet,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: count > 0 ? _blue : _blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.slider_horizontal_3, size: 13,
                                color: count > 0 ? _white : _blue),
                            const SizedBox(width: 5),
                            Text('Filtrar',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: count > 0 ? _white : _blue,
                                )),
                          ],
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: _red,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: _white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_loading)
                  const CupertinoActivityIndicator(radius: 9)
                else
                  Text(
                    '$_total',
                    style: const TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
              ],
            ),
          ),
        ],
        body: CustomScrollView(
          slivers: [
            // Active filter strip
            if (count > 0)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: _blue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _blue.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.tag_fill,
                        size: 13,
                        color: _blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _buildLabel(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _blue,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _clearAllFilters,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _blue.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Limpiar',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _blue,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Search bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: CupertinoSearchTextField(
                  placeholder: 'Buscar por título o expediente…',
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
            ),

            // Content
            if (_error != null)
              SliverToBoxAdapter(
                child: _ErrorBanner(message: _error!, onRetry: _load),
              )
            else if (_items.isEmpty && _loading)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => SkeletonTile(index: i, isLast: i == 7),
                  childCount: 8,
                ),
              )
            else if (_items.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    'Sin resultados',
                    style: TextStyle(color: CupertinoColors.secondaryLabel),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  final items = _filtered;
                  if (i == items.length) {
                    return _hasMore
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CupertinoActivityIndicator()),
                          )
                        : const SizedBox(height: 32);
                  }
                  final l = items[i];
                  return _LicitacionTile(
                    index: i,
                    licitacion: l,
                    isLast: i == items.length - 1,
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      final updated = await Navigator.of(context).push<Licitacion>(
                        CupertinoPageRoute(
                          builder: (_) => LicitacionDetailScreen(licitacion: l),
                        ),
                      );
                      if (updated != null && mounted) {
                        setState(() {
                          final idx = _items.indexWhere((x) => x.id == updated.id);
                          if (idx != -1) _items[idx] = updated;
                        });
                      }
                    },
                  );
                }, childCount: _filtered.length + 1),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Filter sheet ──────────────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final Map<String, String?> initial;
  final void Function(String key, String? value) onChanged;
  final Map<String, List<_FO>> extraOptions;

  const _FilterSheet({
    required this.initial,
    required this.onChanged,
    this.extraOptions = const {},
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Map<String, String?> _values;
  List<AppUser> _salespeople = [];

  @override
  void initState() {
    super.initState();
    _values = Map.from(widget.initial);
    _loadSalespeople();
  }

  Future<void> _loadSalespeople() async {
    try {
      final users = await ApiClient().getUsers();
      if (mounted) {
        setState(() {
          _salespeople = users.where((u) => u.role != 'admin').toList();
        });
      }
    } catch (_) {}
  }

  int get _count => _values.entries
      .where((e) => e.value != null && e.key != 'assigneeUserIds')
      .length;

  // Show CAT2 only when CAT1 is selected; CAT3 only when CAT2 is selected.
  List<_FC> get _visibleCategories {
    final list = <_FC>[];
    for (final cat in _filterCategories) {
      list.add(cat);
      if (cat.key == 'cat1' && _values['cat1'] != null) {
        list.add(_cat2FC);
        if (_values['cat2'] != null) {
          list.add(_cat3FC);
        }
      }
    }
    return list;
  }

  String _labelFor(String key, String value) {
    if (value.contains(',')) {
      final parts = value.split(',');
      final translated = parts.map((p) => _singleLabelFor(key, p)).toList();
      if (translated.length <= 2) {
        return translated.join(', ');
      }
      return '${translated.length} sel.';
    }
    return _singleLabelFor(key, value);
  }

  String _singleLabelFor(String key, String value) {
    if (key == 'asignada') {
      if (value == 'no') return 'Sin asignar';
      if (value == 'si') return 'Asignada';
      final parsedId = int.tryParse(value);
      if (parsedId != null) {
        final match = _salespeople.where((u) => u.id == parsedId).firstOrNull;
        if (match != null) return match.displayName;
      }
    }
    final extra = widget.extraOptions[key];
    if (extra != null) {
      final match = extra.where((o) => o.value == value).firstOrNull;
      if (match != null) return match.label;
    }
    final cat = _filterCategories.where((c) => c.key == key).firstOrNull;
    return cat?.options.where((o) => o.value == value).firstOrNull?.label ??
        value;
  }

  List<_FO> _optionsFor(_FC cat) {
    final all = widget.extraOptions[cat.key] ?? cat.options;
    if (cat.key == 'cat2') {
      final cat1 = _values['cat1']?.toLowerCase().trim();
      if (cat1 == null) return all;
      final allowed = catTree[cat1]?.keys.map((k) => k.toLowerCase().trim()).toSet() ?? {};
      if (allowed.isEmpty) return all;
      return all.where((o) => allowed.contains(o.label.toLowerCase().trim())).toList();
    }
    if (cat.key == 'cat3') {
      final cat1 = _values['cat1']?.toLowerCase().trim();
      final cat2 = _values['cat2']?.toLowerCase().trim();
      if (cat1 == null || cat2 == null) return all;
      final allowed = catTree[cat1]?[cat2]?.map((v) => v.toLowerCase().trim()).toSet() ?? {};
      if (allowed.isEmpty) return all;
      return all.where((o) => allowed.contains(o.label.toLowerCase().trim())).toList();
    }
    return all;
  }

  Future<void> _pickCategory(BuildContext rowCtx, _FC cat) async {
    List<_FO> options = _optionsFor(cat);
    if (cat.key == 'asignada') {
      options = [
        const _FO('Sin asignar', 'no'),
        ..._salespeople.map((u) => _FO(u.displayName, u.id.toString())),
      ];
    }
    if (options.isEmpty) return;

    var currentVal = _values[cat.key];
    if (cat.key == 'asignada') {
      if (_values['asignada'] == 'no') {
        currentVal = 'no';
      } else if (_values['asignada'] == 'si') {
        currentVal = _values['assigneeUserIds'] ?? 'si';
      }
    }

    final selectedSet = currentVal == null || currentVal.isEmpty
        ? <String>{}
        : currentVal.split(',').toSet();

    final result = await showCupertinoModalPopup<Set<String>>(
      context: context,
      builder: (ctx) => _MultiSelectCategoryPicker(
        title: cat.title,
        options: options,
        selectedValues: selectedSet,
      ),
    );

    if (result == null) return;

    setState(() {
      if (result.isEmpty) {
        _values[cat.key] = null;
        if (cat.key == 'asignada') {
          _values['asignada'] = null;
          _values['assigneeUserIds'] = null;
        }
      } else {
        if (cat.key == 'asignada') {
          if (result.contains('no')) {
            _values['asignada'] = 'no';
            _values['assigneeUserIds'] = null;
          } else {
            _values['asignada'] = 'si';
            _values['assigneeUserIds'] = result.join(',');
          }
        } else {
          _values[cat.key] = result.join(',');
        }
      }

      // Cascade: changing CAT1 clears CAT2+CAT3; changing CAT2 clears CAT3.
      if (cat.key == 'cat1') {
        _values['cat2'] = null;
        _values['cat3'] = null;
      } else if (cat.key == 'cat2') {
        _values['cat3'] = null;
      }
    });

    if (cat.key == 'asignada') {
      widget.onChanged('asignada', _values['asignada']);
      widget.onChanged('assigneeUserIds', _values['assigneeUserIds']);
    } else {
      widget.onChanged(cat.key, _values[cat.key]);
      if (cat.key == 'cat1') {
        widget.onChanged('cat2', null);
        widget.onChanged('cat3', null);
      } else if (cat.key == 'cat2') {
        widget.onChanged('cat3', null);
      }
    }
  }

  void _clearAll() {
    setState(() {
      for (final k in _values.keys) {
        _values[k] = null;
      }
    });
    for (final cat in _filterCategories) {
      widget.onChanged(cat.key, null);
    }
    widget.onChanged('assigneeUserIds', null);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 0),
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Row(
              children: [
                const Text(
                  'Filtros',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                    letterSpacing: -0.4,
                  ),
                ),
                if (_count > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _blue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$_count',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _white,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (_count > 0)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: _clearAll,
                    child: const Text(
                      'Limpiar todo',
                      style: TextStyle(
                        fontSize: 14,
                        color: _red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Categories
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: _white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: _navy.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: List.generate(_visibleCategories.length, (i) {
                        final cats = _visibleCategories;
                        final cat = cats[i];
                        var val = _values[cat.key];
                        if (cat.key == 'asignada') {
                          if (_values['asignada'] == 'no') {
                            val = 'no';
                          } else if (_values['asignada'] == 'si') {
                            val = _values['assigneeUserIds'] ?? 'si';
                          }
                        }
                        final isLast = i == cats.length - 1;
                        return Column(
                          children: [
                            Builder(
                              builder: (rowCtx) {
                                return GestureDetector(
                                  onTap: () => _pickCategory(rowCtx, cat),
                                  behavior: HitTestBehavior.opaque,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 13,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: cat.color.withValues(
                                              alpha: 0.10,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              7,
                                            ),
                                          ),
                                          child: Icon(
                                            cat.icon,
                                            size: 14,
                                            color: cat.color,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            cat.title,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: _ink,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (val != null) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: cat.color.withValues(
                                                alpha: 0.10,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              _labelFor(cat.key, val),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: cat.color,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ] else ...[
                                          const Text(
                                            'Todos',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: _muted,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        const Icon(
                                          CupertinoIcons.chevron_right,
                                          size: 13,
                                          color: _muted,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            if (!isLast)
                              Container(
                                height: 0.5,
                                margin: const EdgeInsets.only(left: 56),
                                color: _border,
                              ),
                          ],
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          // Apply / Cancel
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, false),
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F4F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'Cancelar',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, true),
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: _navy,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            _count > 0
                                ? 'Ver resultados ($_count activos)'
                                : 'Ver resultados',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _white,
                            ),
                          ),
                        ),
                      ),
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

class _MultiSelectCategoryPicker extends StatefulWidget {
  final String title;
  final List<_FO> options;
  final Set<String> selectedValues;

  const _MultiSelectCategoryPicker({
    required this.title,
    required this.options,
    required this.selectedValues,
  });

  @override
  State<_MultiSelectCategoryPicker> createState() => _MultiSelectCategoryPickerState();
}

class _MultiSelectCategoryPickerState extends State<_MultiSelectCategoryPicker> {
  late Set<String> _tempSelected;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tempSelected = Set.from(widget.selectedValues);
  }

  @override
  Widget build(BuildContext context) {
    final filteredOptions = widget.options.where((o) {
      if (_searchQuery.isEmpty) return true;
      return o.label.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _navy,
                  ),
                ),
                const Spacer(),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => Navigator.pop(context, _tempSelected),
                  child: const Text(
                    'Listo',
                    style: TextStyle(
                      fontSize: 15,
                      color: _blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Search bar for categories with > 8 options
          if (widget.options.length > 8)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: CupertinoSearchTextField(
                placeholder: 'Buscar...',
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
          // List of options
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: filteredOptions.length,
              itemBuilder: (context, index) {
                final o = filteredOptions[index];
                final isSelected = _tempSelected.contains(o.value);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _tempSelected.remove(o.value);
                      } else {
                        if (widget.title == 'Asignación') {
                          if (o.value == 'no') {
                            _tempSelected.clear();
                          } else {
                            _tempSelected.remove('no');
                          }
                        }
                        _tempSelected.add(o.value);
                      }
                    });
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: _border, width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            o.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? _blue : _ink,
                            ),
                          ),
                        ),
                        Icon(
                          isSelected
                              ? CupertinoIcons.checkmark_square_fill
                              : CupertinoIcons.square,
                          color: isSelected ? _blue : _muted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category picker sheet ─────────────────────────────────────────────────────

// ── Tile ──────────────────────────────────────────────────────────────────────

// easeOutExpo — confident, snappy, natural. Emil Kowalski's go-to curve.
const _kEaseOutExpo = Cubic(0.16, 1.0, 0.3, 1.0);

class _LicitacionTile extends StatefulWidget {
  final Licitacion licitacion;
  final bool isLast;
  final VoidCallback onTap;
  final int index;

  const _LicitacionTile({
    required this.licitacion,
    required this.isLast,
    required this.onTap,
    required this.index,
  });

  @override
  State<_LicitacionTile> createState() => _LicitacionTileState();
}

class _LicitacionTileState extends State<_LicitacionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryOpacity;
  late final Animation<Offset> _entrySlide;
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _entryOpacity = CurvedAnimation(parent: _entryCtrl, curve: _kEaseOutExpo);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: _kEaseOutExpo));
    final delay = (widget.index * 45).clamp(0, 400);
    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted) _entryCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.licitacion;
    final (estadoBg, estadoFg, estadoLabel) = _ingramEstadoStyle(
      l.ingramEstado,
    );
    final isUrgentDeadline =
        l.fechaLimiteOferta != null && _isUrgent(l.fechaLimiteOferta!);

    return FadeTransition(
      opacity: _entryOpacity,
      child: SlideTransition(
        position: _entrySlide,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) {
                setState(() => _pressed = false);
                widget.onTap();
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
                        // ── Header ────────────────────────────────────────────
                        Container(
                          color: const Color(0xFF2dd4bf),
                          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
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
                              const SizedBox(width: 10),
                              PipelineBadge(
                                stage: l.pipelineStage,
                                small: true,
                              ),
                            ],
                          ),
                        ),
                        // ── Body ─────────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Organismo
                              if (l.organismoNombre != null) ...[
                                Row(
                                  children: [
                                    const Icon(
                                      CupertinoIcons.building_2_fill,
                                      size: 11,
                                      color: _muted,
                                    ),
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
                                    _OutlookButton(
                                      onTap: () => _addToOutlook(l),
                                    ),
                                ],
                              ),
                              // Estado + assignee footer
                              if (l.ingramEstado != null ||
                                  l.assignees.isNotEmpty) ...[
                                const SizedBox(height: 9),
                                Row(
                                  children: [
                                    if (l.ingramEstado != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: estadoBg,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: estadoFg.withValues(
                                              alpha: 0.18,
                                            ),
                                          ),
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
                                    if (l.assignees.isNotEmpty) ...[
                                      const Icon(
                                        CupertinoIcons.person_circle_fill,
                                        size: 13,
                                        color: _muted,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        l.assignees
                                            .map((a) => a.displayName.split(' ').first)
                                            .join(' · '),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: _muted,
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
        ),
      ),
    );
  }

  Future<void> _addToOutlook(Licitacion l) async {
    final deadline = l.fechaLimiteOferta ?? l.fecha;
    final dt = DateTime.tryParse(deadline) ?? DateTime.now();

    // Format as YYYYMMDD for all-day ICS dates
    String icsDate(DateTime d) =>
        '${d.year}${d.month.toString().padLeft(2,'0')}${d.day.toString().padLeft(2,'0')}';
    // End date is exclusive in ICS all-day events
    final endDt = dt.add(const Duration(days: 1));
    final now = DateTime.now().toUtc();
    String icsNow(DateTime d) =>
        '${icsDate(d)}T${d.hour.toString().padLeft(2,'0')}${d.minute.toString().padLeft(2,'0')}${d.second.toString().padLeft(2,'0')}Z';

    final description = [
      'Expediente: ${l.numeroExpediente}',
      if (l.organismoNombre != null) 'Organismo: ${l.organismoNombre}',
      if (l.importeLicitacion != null) 'Importe: ${_fmtEur(l.importeLicitacion!)}',
    ].join('\\n');

    final ics = 'BEGIN:VCALENDAR\r\n'
        'VERSION:2.0\r\n'
        'PRODID:-//IMLiti//ES\r\n'
        'BEGIN:VEVENT\r\n'
        'UID:licitacion-${l.id}@imliti\r\n'
        'DTSTAMP:${icsNow(now)}\r\n'
        'DTSTART;VALUE=DATE:${icsDate(dt)}\r\n'
        'DTEND;VALUE=DATE:${icsDate(endDt)}\r\n'
        'SUMMARY:⏰ Fecha límite: ${l.titulo}\r\n'
        'DESCRIPTION:$description\r\n'
        'END:VEVENT\r\n'
        'END:VCALENDAR\r\n';

    final tmp = await getTemporaryDirectory();
    final file = File(p.join(tmp.path, 'licitacion_${l.id}.ics'));
    await file.writeAsString(ics);
    launchUrl(Uri.file(file.path), mode: LaunchMode.platformDefault);
  }
}

// ── Meta column widget ────────────────────────────────────────────────────────

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
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: _muted,
            letterSpacing: 0.1,
          ),
        ),
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
              style:
                  valueStyle ??
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

// ── Thin vertical divider between meta columns ────────────────────────────────

class _MetaDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: _border,
    );
  }
}

// ── Outlook calendar button with hover state ──────────────────────────────────

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
            color: _hovered
                ? _outlookBlue
                : _outlookBlue.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: _outlookBlue.withValues(alpha: _hovered ? 0 : 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.calendar_badge_plus,
                size: 12,
                color: _hovered ? _white : _outlookBlue,
              ),
              const SizedBox(width: 5),
              Text(
                'Añadir a Calendario',
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

bool _isUrgent(String iso) {
  try {
    final diff = DateTime.parse(iso).difference(DateTime.now()).inDays;
    return diff <= 7;
  } catch (_) {
    return false;
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _red.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_circle,
              color: _red,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message.replaceFirst('Exception: ', ''),
                style: const TextStyle(fontSize: 13, color: _red),
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: onRetry,
              child: const Text('Reintentar', style: TextStyle(fontSize: 13)),
            ),
          ],
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
