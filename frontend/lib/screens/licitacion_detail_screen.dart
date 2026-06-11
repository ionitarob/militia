import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show PopupMenuItem, RelativeRect, showMenu;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/client.dart';
import '../api/models.dart';
import '../services/auth_service.dart';
import 'pdf_preview_screen.dart';

// ── Shared dropdown utility ───────────────────────────────────────────────────

Future<String?> _popupMenu({
  required BuildContext context,
  required List<String> options,
  String? current,
  bool allowClear = false,
}) async {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null) return null;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
  final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  final items = <PopupMenuItem<String>>[
    if (allowClear && current != null)
      PopupMenuItem<String>(
        value: '',
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.xmark_circle,
              size: 14,
              color: Color(0xFFDC2626),
            ),
            const SizedBox(width: 10),
            const Text(
              'Quitar',
              style: TextStyle(color: Color(0xFFDC2626), fontSize: 13),
            ),
          ],
        ),
      ),
    ...options.map(
      (o) => PopupMenuItem<String>(
        value: o,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: o == current
                  ? const Icon(
                      CupertinoIcons.checkmark,
                      size: 13,
                      color: Color(0xFF2563EB),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                o,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: o == current ? FontWeight.w600 : FontWeight.w400,
                  color: o == current
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ];
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    items: items,
    color: const Color(0xFFFFFFFF),
    elevation: 12,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    constraints: const BoxConstraints(minWidth: 200, maxWidth: 340),
  );
}

const _navy = Color(0xFF0F1F3D);
const _blue = Color(0xFF2563EB);
const _gold = Color(0xFFF59E0B);
const _ink = Color(0xFF111827);
const _muted = Color(0xFF6B7280);
const _bg = Color(0xFFF1F4F9);
const _white = Color(0xFFFFFFFF);
const _red = Color(0xFFDC2626);
const _green = Color(0xFF059669);
const _border = Color(0xFFE5E7EB);

const _ingramEstados = [
  'PENDIENTE SOLICITUD DE COTIZACIÓN A LA DIVISIÓN',
  'COTIZACIÓN SOLICITADA (A LA DIVISIÓN)',
  'PENDIENTE ENVÍO DE COTIZACIÓN A CLIENTE',
  'COTIZACIÓN ENVIADA A CLIENTE - X4A',
  'RECHAZADO',
];
const _cotizacionDivisiones = [
  'DIVISIÓN ALAN',
  'DIVISIÓN JORGE',
  'DIVISIÓN SERVICIOS',
  'DIVISIÓN MARTIN TRULLAS',
  'DIVISIÓN AVPRO/UCC',
  'DIVISIÓN DCPOS/PHSEC',
  'DIVISIÓN CLOUD',
];
const _clientesFijos = [
  'ACUNTIA',
  'PLEXUS',
  'SEMIC',
  'ATOS',
  'ECONOCOM',
  'EVOLUTIO',
  'GMV',
  'HIBERUS',
  'IAAS365',
  'AYESA',
  'IDIOMUND',
  'INDRA',
  'INETUM',
  'NTT',
  'ORANGE',
  'SEIDOR',
  'SOLUTIA',
  'INFOREIN',
  'TAISA',
  'TELEFÓNICA',
  'T-SYSTEMS',
  'VODAFONE',
  'OTRO',
];

// ── Screen ────────────────────────────────────────────────────────────────────

class LicitacionDetailScreen extends StatefulWidget {
  final Licitacion licitacion;
  const LicitacionDetailScreen({super.key, required this.licitacion});

  @override
  State<LicitacionDetailScreen> createState() => _LicitacionDetailScreenState();
}

class _LicitacionDetailScreenState extends State<LicitacionDetailScreen> {
  late Licitacion _lic;

  List<LicitacionNote> _notes = [];
  List<LicitacionDocumento> _docs = [];
  List<CotizacionAdjunto> _adjuntos = [];
  bool _loadingNotes = true;
  bool _loadingDocs = true;
  bool _loadingAdjuntos = true;
  bool _uploadingAdjunto = false;

  String? _ingramEstado;
  String? _ingramOwner;
  String? _cotizacionSolicitadaA;
  bool _savingIngram = false;

  Map<String, ClienteCotizacion> _cotizaciones = {};
  bool _loadingCotizaciones = true;

  bool get _isAdmin => AuthService().currentUser?.isAdmin ?? false;

  @override
  void initState() {
    super.initState();
    _lic = widget.licitacion;
    _ingramEstado = _lic.ingramEstado;
    _ingramOwner = _lic.ingramOwner;
    _cotizacionSolicitadaA = _lic.cotizacionSolicitadaA;
    _loadNotes();
    _loadCotizaciones();
    _loadDocumentos();
    _loadAdjuntos();
  }

  Future<void> _loadNotes() async {
    try {
      final n = await ApiClient().getNotes(_lic.id);
      if (mounted)
        setState(() {
          _notes = n;
          _loadingNotes = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingNotes = false);
    }
  }

  Future<void> _loadDocumentos() async {
    try {
      final d = await ApiClient().getDocumentos(_lic.id);
      if (mounted)
        setState(() {
          _docs = d;
          _loadingDocs = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingDocs = false);
    }
  }

  Future<void> _loadAdjuntos() async {
    try {
      final a = await ApiClient().getAdjuntos(_lic.id);
      if (mounted)
        setState(() {
          _adjuntos = a;
          _loadingAdjuntos = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingAdjuntos = false);
    }
  }

  Future<void> _uploadAdjunto(String nombre, String contentType, Uint8List bytes) async {
    if (_uploadingAdjunto) return;
    setState(() => _uploadingAdjunto = true);
    try {
      final result = await ApiClient().createAdjunto(
        _lic.id,
        nombre: nombre,
        contentType: contentType,
        sizeBytes: bytes.length,
      );
      final uploadUrl = result['upload_url'] as String;
      final uploadRes = await http.put(
        Uri.parse(uploadUrl),
        headers: {'content-type': contentType},
        body: bytes,
      );
      if (uploadRes.statusCode != 200) throw Exception('Upload failed: ${uploadRes.statusCode}');
      await _loadAdjuntos();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _uploadingAdjunto = false);
    }
  }

  Future<void> _deleteAdjunto(int adjuntoId) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Eliminar adjunto'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient().deleteAdjunto(_lic.id, adjuntoId);
      if (mounted) {
        setState(() => _adjuntos = _adjuntos.where((a) => a.id != adjuntoId).toList());
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    final ct = _mimeFromName(file.name);
    await _uploadAdjunto(file.name, ct, file.bytes!);
  }

  String _mimeFromName(String name) {
    final ext = name.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':  return 'application/pdf';
      case 'png':  return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:     return 'application/octet-stream';
    }
  }

  Future<void> _loadCotizaciones() async {
    try {
      final list = await ApiClient().getClienteCotizaciones(_lic.id);
      final map = <String, ClienteCotizacion>{};
      for (final c in list) {
        map[c.clienteNombre] = c;
      }
      if (mounted)
        setState(() {
          _cotizaciones = map;
          _loadingCotizaciones = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingCotizaciones = false);
    }
  }

  Future<void> _saveIngram() async {
    if (_savingIngram) return;
    setState(() => _savingIngram = true);
    try {
      await ApiClient().patchIngram(
        _lic.id,
        ingramEstado: _ingramEstado,
        ingramOwner: _ingramOwner,
        cotizacionSolicitadaA: _cotizacionSolicitadaA,
      );
      HapticFeedback.lightImpact();
      if (mounted) {
        setState(() {
          _lic = _lic.copyWith(
            ingramEstado: () => _ingramEstado,
            ingramOwner: () => _ingramOwner,
            cotizacionSolicitadaA: () => _cotizacionSolicitadaA,
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _savingIngram = false);
    }
  }

  Future<void> _saveCotizacion(String cliente, String? xv, String? opp) async {
    try {
      await ApiClient().upsertClienteCotizacion(
        _lic.id,
        cliente,
        cotizacionXv: xv,
        oportunidad: opp,
      );
      if (mounted) {
        setState(() {
          _cotizaciones[cliente] = ClienteCotizacion(
            clienteNombre: cliente,
            cotizacionXv: xv,
            oportunidad: opp,
          );
        });
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(msg.replaceFirst('Exception: ', '')),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, r) {
        if (didPop) return;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => Navigator.of(context).pop(_lic),
        );
      },
      child: CupertinoPageScaffold(
        backgroundColor: _bg,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: _bg,
          border: null,
          previousPageTitle: 'Atrás',
          middle: Text(
            _lic.titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _navy,
              letterSpacing: -0.2,
            ),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── 50 / 50 body ───────────────────────────────────────────────
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, c) {
                    final wide = c.maxWidth >= 680;
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: c.maxWidth * 0.48,
                            child: _LeftPanel(
                              lic: _lic,
                              docs: _docs,
                              loadingDocs: _loadingDocs,
                            ),
                          ),
                          Container(width: 1, color: _border),
                          Expanded(child: _buildRightPanel()),
                        ],
                      );
                    }
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          _LeftPanel(
                            lic: _lic,
                            docs: _docs,
                            loadingDocs: _loadingDocs,
                          ),
                          Container(height: 1, color: _border),
                          _buildRightPanel(scroll: false),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Right panel (vendedor tools) ──────────────────────────────────────────

  Widget _buildRightPanel({bool scroll = true}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Asignación
        _PanelSection(
          icon: CupertinoIcons.person_circle_fill,
          label: 'Asignación',
          color: _blue,
          child: _lic.assigneeNombre != null
              ? _AssigneeRow(
                  name: _lic.assigneeNombre!,
                  isAdmin: _isAdmin,
                  onReassign: _showReassignSheet,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.person_crop_circle_badge_xmark,
                        size: 18,
                        color: _muted,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Sin asignar',
                          style: TextStyle(fontSize: 14, color: _muted),
                        ),
                      ),
                      if (_isAdmin)
                        Builder(
                          builder: (btnCtx) => CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            onPressed: () => _showReassignSheet(btnCtx),
                            child: const Text(
                              'Asignar',
                              style: TextStyle(
                                fontSize: 13,
                                color: _blue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: _selfAssign,
                          child: const Text(
                            'Añadir a mi panel',
                            style: TextStyle(
                              fontSize: 13,
                              color: _blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),

        // Gestión Comercial
        _PanelSection(
          icon: CupertinoIcons.briefcase_fill,
          label: 'Gestión Comercial',
          color: const Color(0xFF7C3AED),
          trailing: _savingIngram
              ? const CupertinoActivityIndicator(radius: 8)
              : null,
          child: Column(
            children: [
              _PickerRow(
                label: 'Estado',
                value: _ingramEstado,
                placeholder: 'Sin estado',
                options: _ingramEstados,
                allowClear: true,
                onSelected: (v) {
                  setState(() => _ingramEstado = v);
                  _saveIngram();
                },
              ),
              _divider(),
              _PickerRow(
                label: 'División',
                value: _cotizacionSolicitadaA,
                placeholder: 'Sin división',
                options: _cotizacionDivisiones,
                allowClear: true,
                onSelected: (v) {
                  setState(() => _cotizacionSolicitadaA = v);
                  _saveIngram();
                },
              ),
            ],
          ),
        ),

        // Clientes
        _PanelSection(
          icon: CupertinoIcons.table,
          label: 'Cotización enviada a',
          color: _navy,
          child: _loadingCotizaciones
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CupertinoActivityIndicator()),
                )
              : _ClientesTable(
                  clientes: _clientesFijos,
                  cotizaciones: _cotizaciones,
                  onSave: _saveCotizacion,
                ),
        ),

        // Cotizaciones XVantage (PDF upload)
        _PanelSection(
          icon: CupertinoIcons.doc_fill,
          label: 'Cotizaciones XVantage',
          color: const Color(0xFF0891B2),
          child: _CotizacionAdjuntosPanel(
            adjuntos: _adjuntos,
            loading: _loadingAdjuntos,
            uploading: _uploadingAdjunto,
            onPickFile: _pickAndUpload,
            onDropFile: (nombre, ct, bytes) => _uploadAdjunto(nombre, ct, bytes),
            onDelete: _deleteAdjunto,
          ),
        ),

        // Notas
        _PanelSection(
          icon: CupertinoIcons.chat_bubble_text_fill,
          label: 'Notas',
          color: _gold,
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: _showAddNoteSheet,
            child: const Icon(
              CupertinoIcons.plus_circle_fill,
              size: 20,
              color: _blue,
            ),
          ),
          child: _loadingNotes
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CupertinoActivityIndicator()),
                )
              : _notes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Text(
                    'Añade la primera nota.',
                    style: TextStyle(fontSize: 13, color: _muted),
                  ),
                )
              : Column(children: _notes.map((n) => _NoteRow(note: n)).toList()),
        ),

        const SizedBox(height: 40),
      ],
    );

    if (!scroll) return content;
    return SingleChildScrollView(child: content);
  }

  // ── Self-assign (vendedor) ────────────────────────────────────────────────

  Future<void> _selfAssign() async {
    final me = AuthService().currentUser;
    if (me == null) return;
    try {
      await ApiClient().assignLicitacion(_lic.id, me.id);
      if (!mounted) return;
      setState(() {
        _lic = _lic.copyWith(
          assigneeId: () => me.id,
          assigneeNombre: () => me.nombre ?? me.email,
        );
      });
    } catch (e) {
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Error'),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }

  // ── Reassign ──────────────────────────────────────────────────────────────

  Future<void> _showReassignSheet(BuildContext btnCtx) async {
    try {
      final box = btnCtx.findRenderObject() as RenderBox?;
      final users = await ApiClient().getUsers();
      final vendedores = users.where((u) => u.role != 'admin').toList();
      if (!mounted || box == null) return;
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
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: v.id == _lic.assigneeId
                          ? const Icon(
                              CupertinoIcons.checkmark,
                              size: 13,
                              color: Color(0xFF2563EB),
                            )
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      v.displayName,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      );
      if (!mounted || picked == null) return;
      await ApiClient().assignLicitacion(_lic.id, picked.id);
      setState(() {
        _lic = _lic.copyWith(
          assigneeId: () => picked.id,
          assigneeNombre: () => picked.displayName,
        );
      });
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  // ── Notes ─────────────────────────────────────────────────────────────────

  Future<void> _showAddNoteSheet() async {
    final ctrl = TextEditingController();
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (_) => _NoteInputSheet(controller: ctrl),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    try {
      final note = await ApiClient().createNote(_lic.id, ctrl.text.trim());
      if (mounted) {
        setState(() => _notes = [..._notes, note]);
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }
}

// ── Left panel (static portal data) ─────────────────────────────────────────

class _LeftPanel extends StatelessWidget {
  final Licitacion lic;
  final List<LicitacionDocumento> docs;
  final bool loadingDocs;

  const _LeftPanel({
    required this.lic,
    this.docs = const [],
    this.loadingDocs = false,
  });

  @override
  Widget build(BuildContext context) {
    final diff = lic.fechaLimiteOferta != null
        ? DateTime.tryParse(
            lic.fechaLimiteOferta!,
          )?.difference(DateTime.now()).inDays
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lic.organismoNombre != null) ...[
            Text(
              'Organismo licitador',
              style: const TextStyle(
                fontSize: 10,
                color: _muted,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              lic.organismoNombre!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            'Publicado ${_fmtDate(lic.fecha)}',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 20),

          // ── Importes ────────────────────────────────────────────────
          if (lic.importeLicitacion != null || lic.valorEstimado != null) ...[
            _DataCard(
              children: [
                if (lic.importeLicitacion != null) ...[
                  _DataRow(
                    label: 'Importe licitación',
                    value:
                        '${_fmtEurFull(lic.importeLicitacion!)} (IVA no incluido)',
                    bold: true,
                    valueColor: _navy,
                  ),
                ],
                if (lic.importeLicitacion != null && lic.valorEstimado != null)
                  _divider(),
                if (lic.valorEstimado != null) ...[
                  _DataRow(
                    label: 'Valor estimado',
                    value:
                        '${_fmtEurFull(lic.valorEstimado!)} (IVA no incluido)',
                    valueColor: _muted,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
          ],

          // ── Core procurement fields ─────────────────────────────
          _DataCard(
            children: [
              _DataRow(
                label: 'Número de expediente',
                value: lic.numeroExpediente,
                mono: true,
              ),
              if (lic.tipoProcedimiento != null) ...[
                _divider(),
                _DataRow(
                  label: 'Tipo de procedimiento',
                  value: lic.tipoProcedimiento!,
                ),
              ],
              if (lic.tipoTramitacion != null) ...[
                _divider(),
                _DataRow(
                  label: 'Tipo de tramitación',
                  value: lic.tipoTramitacion!,
                ),
              ],
              if (lic.cpvLabel != null) ...[
                _divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: const Text(
                          'Clasificación CPV',
                          style: TextStyle(fontSize: 13, color: _muted),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 5,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final cpv in lic.cpvLabel!.split('; '))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF2563EB,
                                  ).withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF2563EB,
                                    ).withValues(alpha: 0.15),
                                  ),
                                ),
                                child: Text(
                                  cpv,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF1D4ED8),
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
              if (lic.duracionMeses != null) ...[
                _divider(),
                _DataRow(
                  label: 'Duración',
                  value: '${lic.duracionMeses} meses',
                ),
              ],
              if (lic.prorrogasMeses != null) ...[
                _divider(),
                _DataRow(
                  label: 'Prórrogas',
                  value: '${lic.prorrogasMeses} meses',
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // ── Deadline ────────────────────────────────────────────
          if (lic.fechaLimiteOferta != null) ...[
            _DeadlineCard(
              iso: lic.fechaLimiteOferta!,
              diff: diff,
              plazoEstado: lic.plazoOfertaEstado,
            ),
            const SizedBox(height: 10),
          ],

          // ── Geography + market ──────────────────────────────────
          _DataCard(
            children: [
              if (lic.mercadoVertical != null) ...[
                _DataRow(
                  label: 'Mercado vertical',
                  value: lic.mercadoVertical!,
                  icon: CupertinoIcons.building_2_fill,
                  iconColor: const Color(0xFFD97706),
                ),
              ],
              if (lic.provincia != null) ...[
                if (lic.mercadoVertical != null) _divider(),
                _DataRow(
                  label: 'Provincia',
                  value: lic.provincia!,
                  icon: CupertinoIcons.location_fill,
                  iconColor: _muted,
                ),
              ],
              if (lic.comunidadAutonoma != null) ...[
                if (lic.mercadoVertical != null || lic.provincia != null)
                  _divider(),
                _DataRow(
                  label: 'Comunidad autónoma',
                  value: lic.comunidadAutonoma!,
                  icon: CupertinoIcons.map_fill,
                  iconColor: _green,
                ),
              ],
            ],
          ),

          // ── Criterios de adjudicación ───────────────────────────
          if (lic.puntosPrecio != null ||
              lic.puntosMejoras != null ||
              lic.puntosSubjetivos != null) ...[
            const SizedBox(height: 10),
            _DataCard(
              children: [
                _SectionHeader(label: 'Criterios de adjudicación'),
                if (lic.puntosPrecio != null) ...[
                  _divider(),
                  _DataRow(
                    label: 'Precio (objetivos)',
                    value: '${lic.puntosPrecio} puntos',
                    icon: CupertinoIcons.money_euro_circle,
                    iconColor: _green,
                  ),
                ],
                if (lic.puntosMejoras != null) ...[
                  _divider(),
                  _DataRow(
                    label: 'Mejoras (objetivos)',
                    value: '${lic.puntosMejoras} puntos',
                    icon: CupertinoIcons.star,
                    iconColor: _gold,
                  ),
                ],
                if (lic.puntosSubjetivos != null) ...[
                  _divider(),
                  _DataRow(
                    label: 'Subjetivos',
                    value: '${lic.puntosSubjetivos} puntos',
                    icon: CupertinoIcons.person_fill,
                    iconColor: const Color(0xFF7C3AED),
                  ),
                ],
              ],
            ),
          ],

          if (lic.estado != null) ...[
            const SizedBox(height: 10),
            _DataCard(
              children: [_DataRow(label: 'Estado portal', value: lic.estado!)],
            ),
          ],

          // ── Documentos adjuntos ─────────────────────────────────
          if (loadingDocs || docs.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DataCard(
              children: [
                _SectionHeader(label: 'Documentos adjuntos'),
                if (loadingDocs)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CupertinoActivityIndicator()),
                  )
                else
                  ...List.generate(docs.length, (i) {
                    final doc = docs[i];
                    final isPdf =
                        doc.contentType == 'application/pdf' ||
                        doc.nombre.toLowerCase().endsWith('.pdf');
                    return Column(
                      children: [
                        if (i > 0) _divider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: isPdf
                                      ? _red.withValues(alpha: 0.08)
                                      : _blue.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  isPdf
                                      ? CupertinoIcons.doc_fill
                                      : CupertinoIcons.doc_text_fill,
                                  size: 15,
                                  color: isPdf ? _red : _blue,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  doc.nombre,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _ink,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (isPdf)
                                CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  onPressed: () => Navigator.of(context).push(
                                    CupertinoPageRoute(
                                      builder: (_) => PdfPreviewScreen(
                                        url: doc.url,
                                        title: doc.nombre,
                                      ),
                                    ),
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.eye,
                                    size: 16,
                                    color: _muted,
                                  ),
                                ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                onPressed: () => launchUrl(
                                  Uri.parse(doc.url),
                                  mode: LaunchMode.externalApplication,
                                ),
                                child: const Icon(
                                  CupertinoIcons.arrow_down_to_line,
                                  size: 16,
                                  color: _muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Panel section wrapper ─────────────────────────────────────────────────────

class _PanelSection extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Widget child;
  final Widget? trailing;

  const _PanelSection({
    required this.icon,
    required this.label,
    required this.color,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 13, color: color),
              ),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
        ),
        _DataCard(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          children: [child],
        ),
        const SizedBox(height: 2),
      ],
    );
  }
}

// ── Data card ─────────────────────────────────────────────────────────────────

class _DataCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets? margin;

  const _DataCard({required this.children, this.margin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

// ── Data row ──────────────────────────────────────────────────────────────────

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  final bool mono;
  final IconData? icon;
  final Color? iconColor;

  const _DataRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
    this.mono = false,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor ?? _muted),
            const SizedBox(width: 6),
          ],
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: _muted),
            ),
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
}

// ── Deadline card ─────────────────────────────────────────────────────────────

class _DeadlineCard extends StatelessWidget {
  final String iso;
  final int? diff;
  final String? plazoEstado;

  const _DeadlineCard({
    required this.iso,
    required this.diff,
    this.plazoEstado,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String urgencyLabel;
    if (diff == null) {
      color = _muted;
      urgencyLabel = iso;
    } else if (diff! < 0) {
      color = _red;
      urgencyLabel = 'Expirada';
    } else if (diff == 0) {
      color = _red;
      urgencyLabel = 'Hoy';
    } else if (diff! <= 7) {
      color = _red;
      urgencyLabel = 'En $diff días';
    } else if (diff! <= 14) {
      color = _gold;
      urgencyLabel = 'En $diff días';
    } else {
      color = _green;
      urgencyLabel = _fmtDate(iso);
    }

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(CupertinoIcons.clock_fill, size: 16, color: color),
                const SizedBox(width: 8),
                const Text(
                  'Fecha límite presentación ofertas',
                  style: TextStyle(fontSize: 13, color: _muted),
                ),
                const Spacer(),
                Text(
                  urgencyLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          if (diff != null && diff! >= 0 && diff! <= 30) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: LayoutBuilder(
                builder: (ctx, c) {
                  final frac = 1.0 - (diff! / 30).clamp(0.0, 1.0);
                  return Stack(
                    children: [
                      Container(
                        height: 4,
                        width: c.maxWidth,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      Container(
                        height: 4,
                        width: c.maxWidth * frac,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
          if (plazoEstado != null) ...[
            Container(height: 0.5, color: color.withValues(alpha: 0.15)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Text(
                    'Estado plazo',
                    style: TextStyle(fontSize: 12, color: _muted),
                  ),
                  const Spacer(),
                  Text(
                    plazoEstado!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Picker row ────────────────────────────────────────────────────────────────

class _PickerRow extends StatelessWidget {
  final String label;
  final String? value;
  final String placeholder;
  final List<String> options;
  final bool allowClear;
  final void Function(String?) onSelected;

  const _PickerRow({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.options,
    required this.onSelected,
    this.allowClear = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return GestureDetector(
      onTap: () async {
        final picked = await _popupMenu(
          context: context,
          options: options,
          current: value,
          allowClear: allowClear,
        );
        if (picked != null) onSelected(picked.isEmpty ? null : picked);
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: _muted),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      hasValue ? _shortEstado(value!) : placeholder,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: hasValue
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: hasValue ? _navy : _muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    CupertinoIcons.chevron_right,
                    size: 12,
                    color: _muted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortEstado(String v) {
    if (v.startsWith('PENDIENTE SOLICITUD')) return 'Pend. Solicitud';
    if (v.startsWith('COTIZACIÓN SOLICITADA')) return 'Cotiz. Solicitada';
    if (v.startsWith('PENDIENTE ENVÍO')) return 'Pend. Envío';
    if (v.startsWith('COTIZACIÓN ENVIADA')) return 'Enviada a Cliente';
    if (v.startsWith('RECHAZADO')) return 'Rechazado';
    return v;
  }
}

// ── Clientes table ────────────────────────────────────────────────────────────

class _ClientesTable extends StatefulWidget {
  final List<String> clientes;
  final Map<String, ClienteCotizacion> cotizaciones;
  final Future<void> Function(String, String?, String?) onSave;

  const _ClientesTable({
    required this.clientes,
    required this.cotizaciones,
    required this.onSave,
  });

  @override
  State<_ClientesTable> createState() => _ClientesTableState();
}

class _ClientesTableState extends State<_ClientesTable> {
  // clients with checkbox checked (expanding the row)
  final Set<String> _checked = {};
  // inline controllers: cliente -> (xvCtrl, oppCtrl)
  final Map<String, (TextEditingController, TextEditingController)> _ctrls = {};
  final Set<String> _saving = {};
  final Set<String> _editing = {}; // rows unlocked for editing

  @override
  void initState() {
    super.initState();
    // pre-check clients that already have data
    for (final c in widget.cotizaciones.keys) {
      final d = widget.cotizaciones[c]!;
      if ((d.cotizacionXv?.isNotEmpty ?? false) ||
          (d.oportunidad?.isNotEmpty ?? false)) {
        _checked.add(c);
        _ctrls[c] = (
          TextEditingController(text: d.cotizacionXv ?? ''),
          TextEditingController(text: d.oportunidad ?? ''),
        );
        // rows with existing saved data start locked
      }
    }
  }

  @override
  void dispose() {
    for (final p in _ctrls.values) {
      p.$1.dispose();
      p.$2.dispose();
    }
    super.dispose();
  }

  void _toggle(String cliente) {
    setState(() {
      if (_checked.contains(cliente)) {
        _checked.remove(cliente);
        _editing.remove(cliente);
        _ctrls[cliente]?.$1.dispose();
        _ctrls[cliente]?.$2.dispose();
        _ctrls.remove(cliente);
        widget.onSave(cliente, null, null);
      } else {
        _checked.add(cliente);
        final d = widget.cotizaciones[cliente];
        _ctrls[cliente] = (
          TextEditingController(text: d?.cotizacionXv ?? ''),
          TextEditingController(text: d?.oportunidad ?? ''),
        );
      }
    });
  }

  Future<void> _save(String cliente) async {
    final p = _ctrls[cliente];
    if (p == null) return;
    setState(() => _saving.add(cliente));
    await widget.onSave(
      cliente,
      p.$1.text.trim().isEmpty ? null : p.$1.text.trim(),
      p.$2.text.trim().isEmpty ? null : p.$2.text.trim(),
    );
    if (mounted) {
      setState(() {
        _saving.remove(cliente);
        _editing.remove(cliente);
      });
    }
  }

  Future<void> _showAddPicker(BuildContext context) async {
    // "OTRO CUAL?" is always available — each custom entry gets a unique name
    final available = widget.clientes
        .where((c) => c == 'OTRO' || !_checked.contains(c))
        .toList();
    if (available.isEmpty) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      color: const Color(0xFFFFFFFF),
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
      items: available
          .map(
            (c) => PopupMenuItem<String>(
              value: c,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                c,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          )
          .toList(),
    );
    if (picked == null || !mounted) return;

    if (picked == 'OTRO') {
      final name = await showCupertinoModalPopup<String>(
        context: this.context,
        builder: (ctx) => _ClienteNameSheet(
          onConfirm: (text) => Navigator.pop(ctx, text),
          onCancel: () => Navigator.pop(ctx),
        ),
      );
      if (!mounted || name == null || name.trim().isEmpty) return;
      _toggle(name.trim().toUpperCase());
    } else {
      _toggle(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final checked = [
      ...widget.clientes.where((c) => _checked.contains(c)),
      ..._checked.where((c) => !widget.clientes.contains(c)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (checked.isNotEmpty) ...[
          // Header
          Container(
            color: const Color(0xFFF8FAFC),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: const Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    'CLIENTE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _muted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'OPORTUNIDAD',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _muted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'COTIZACIÓN',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _muted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(width: 60),
              ],
            ),
          ),
          Container(height: 0.5, color: _border),
          ...List.generate(checked.length, (i) {
            final cliente = checked[i];
            final isSaving = _saving.contains(cliente);
            final p = _ctrls[cliente];
            final hasSaved = widget.cotizaciones[cliente]?.cotizacionXv?.isNotEmpty == true ||
                widget.cotizaciones[cliente]?.oportunidad?.isNotEmpty == true;
            final isLocked = hasSaved && !_editing.contains(cliente);
            return Column(
              children: [
                Container(
                  color: const Color(0xFFF0F7FF),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 80,
                        child: Text(
                          cliente,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _navy,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: p != null
                            ? CupertinoTextField(
                                controller: p.$2,
                                placeholder: 'Oportunidad',
                                readOnly: isLocked,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isLocked ? _muted : _ink,
                                ),
                                placeholderStyle: const TextStyle(
                                  fontSize: 12,
                                  color: _muted,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isLocked ? const Color(0xFFF3F4F6) : _white,
                                  border: Border.all(color: isLocked ? const Color(0xFFE5E7EB) : _border),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                onSubmitted: (_) => _save(cliente),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: p != null
                            ? CupertinoTextField(
                                controller: p.$1,
                                placeholder: 'Cotización XV',
                                readOnly: isLocked,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isLocked ? _muted : _ink,
                                ),
                                placeholderStyle: const TextStyle(
                                  fontSize: 12,
                                  color: _muted,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isLocked ? const Color(0xFFF3F4F6) : _white,
                                  border: Border.all(color: isLocked ? const Color(0xFFE5E7EB) : _border),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                onSubmitted: (_) => _save(cliente),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 4),
                      if (isSaving)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: CupertinoActivityIndicator(radius: 8),
                        )
                      else if (isLocked)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: Size.zero,
                          onPressed: () => setState(() => _editing.add(cliente)),
                          child: const Icon(
                            CupertinoIcons.pencil_circle,
                            size: 20,
                            color: _muted,
                          ),
                        )
                      else
                        CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              minimumSize: Size.zero,
                              onPressed: () => _save(cliente),
                              child: const Icon(
                                CupertinoIcons.checkmark_circle_fill,
                                size: 20,
                                color: _green,
                              ),
                            ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: () => _toggle(cliente),
                        child: const Icon(
                          CupertinoIcons.xmark_circle_fill,
                          size: 18,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < checked.length - 1)
                  Container(height: 0.5, color: _border),
              ],
            );
          }),
          Container(height: 0.5, color: _border),
        ],
        // Add button
        GestureDetector(
          onTap: () => _showAddPicker(context),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(CupertinoIcons.plus_circle, size: 16, color: _blue),
                const SizedBox(width: 6),
                Text(
                  checked.isEmpty ? 'Añadir cliente' : 'Añadir otro cliente',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Assignee row ──────────────────────────────────────────────────────────────

class _AssigneeRow extends StatelessWidget {
  final String name;
  final bool isAdmin;
  final void Function(BuildContext)? onReassign;

  const _AssigneeRow({
    required this.name,
    required this.isAdmin,
    this.onReassign,
  });

  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(' ')
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _blue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ),
          if (isAdmin)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: onReassign != null ? () => onReassign!(context) : null,
              child: const Text(
                'Reasignar',
                style: TextStyle(
                  fontSize: 13,
                  color: _blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Cotizacion adjuntos panel ─────────────────────────────────────────────────

class _CotizacionAdjuntosPanel extends StatefulWidget {
  final List<CotizacionAdjunto> adjuntos;
  final bool loading;
  final bool uploading;
  final VoidCallback onPickFile;
  final void Function(String nombre, String ct, Uint8List bytes) onDropFile;
  final void Function(int id) onDelete;

  const _CotizacionAdjuntosPanel({
    required this.adjuntos,
    required this.loading,
    required this.uploading,
    required this.onPickFile,
    required this.onDropFile,
    required this.onDelete,
  });

  @override
  State<_CotizacionAdjuntosPanel> createState() =>
      _CotizacionAdjuntosPanelState();
}

class _CotizacionAdjuntosPanelState extends State<_CotizacionAdjuntosPanel> {
  bool _dragging = false;

  String _fmtSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String _mimeFromName(String name) {
    final ext = name.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':  return 'application/pdf';
      case 'png':  return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:     return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Drop zone / upload button
        DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (detail) async {
            setState(() => _dragging = false);
            for (final xfile in detail.files) {
              final bytes = await xfile.readAsBytes();
              final ct = _mimeFromName(xfile.name);
              widget.onDropFile(xfile.name, ct, bytes);
            }
          },
          child: GestureDetector(
            onTap: widget.uploading ? null : widget.onPickFile,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: _dragging
                    ? const Color(0xFF0891B2).withValues(alpha: 0.07)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _dragging
                      ? const Color(0xFF0891B2)
                      : const Color(0xFFCBD5E1),
                  width: _dragging ? 1.5 : 1,
                ),
              ),
              child: widget.uploading
                  ? const Center(child: CupertinoActivityIndicator())
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.cloud_upload,
                          size: 24,
                          color: _dragging
                              ? const Color(0xFF0891B2)
                              : _muted,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _dragging
                              ? 'Suelta para subir'
                              : 'Arrastra un archivo o toca para seleccionar',
                          style: TextStyle(
                            fontSize: 12,
                            color: _dragging
                                ? const Color(0xFF0891B2)
                                : _muted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
            ),
          ),
        ),

        // File list
        if (widget.adjuntos.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Sin adjuntos.',
              style: TextStyle(fontSize: 13, color: _muted),
            ),
          )
        else
          ...widget.adjuntos.map(
            (a) => _AdjuntoRow(
              adjunto: a,
              fmtSize: _fmtSize(a.sizeBytes),
              onDelete: () => widget.onDelete(a.id),
            ),
          ),
      ],
    );
  }
}

class _AdjuntoRow extends StatelessWidget {
  final CotizacionAdjunto adjunto;
  final String fmtSize;
  final VoidCallback onDelete;

  const _AdjuntoRow({
    required this.adjunto,
    required this.fmtSize,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          const Icon(CupertinoIcons.doc_fill, size: 16, color: Color(0xFF0891B2)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  adjunto.nombre,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (fmtSize.isNotEmpty)
                  Text(
                    fmtSize,
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
              ],
            ),
          ),
          if (adjunto.contentType == 'application/pdf' ||
              adjunto.nombre.toLowerCase().endsWith('.pdf'))
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (_) => PdfPreviewScreen(
                    url: adjunto.url,
                    title: adjunto.nombre,
                  ),
                ),
              ),
              child: const Icon(CupertinoIcons.eye, size: 16, color: _muted),
            ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => launchUrl(Uri.parse(adjunto.url)),
            child: const Icon(CupertinoIcons.arrow_down_to_line, size: 16, color: _muted),
          ),
          const SizedBox(width: 2),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: onDelete,
            child: const Icon(CupertinoIcons.trash, size: 15, color: _red),
          ),
        ],
      ),
    );
  }
}

// ── Note row ──────────────────────────────────────────────────────────────────

class _NoteRow extends StatelessWidget {
  final LicitacionNote note;
  const _NoteRow({required this.note});

  @override
  Widget build(BuildContext context) {
    final name = note.userNombre ?? 'Usuario';
    final initials = name
        .split(' ')
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _navy,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _navy,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _fmtDate(note.createdAt),
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  note.content,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _ink,
                    height: 1.4,
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

// ── Cliente name input sheet ─────────────────────────────────────────────────

class _ClienteNameSheet extends StatefulWidget {
  final ValueChanged<String> onConfirm;
  final VoidCallback onCancel;
  const _ClienteNameSheet({required this.onConfirm, required this.onCancel});

  @override
  State<_ClienteNameSheet> createState() => _ClienteNameSheetState();
}

class _ClienteNameSheetState extends State<_ClienteNameSheet> {
  String _text = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      decoration: const BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            'Nombre del cliente',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _navy,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: CupertinoTextField.borderless(
              placeholder: 'Ej: ACCENTURE',
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              padding: const EdgeInsets.all(14),
              onChanged: (v) => _text = v,
              onSubmitted: (_) => widget.onConfirm(_text),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: widget.onCancel,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
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
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => widget.onConfirm(_text),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _blue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Añadir',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Note input sheet ──────────────────────────────────────────────────────────

class _NoteInputSheet extends StatelessWidget {
  final TextEditingController controller;
  const _NoteInputSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      decoration: const BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            'Añadir nota',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _navy,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: CupertinoTextField.borderless(
              controller: controller,
              placeholder: 'Escribe tu nota...',
              maxLines: 4,
              autofocus: true,
              padding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, false),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
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
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, true),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: _navy,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Publicar',
                        style: TextStyle(
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
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _divider() => Container(
  height: 0.5,
  margin: const EdgeInsets.only(left: 16),
  color: _border,
);

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: _muted,
        letterSpacing: 0.5,
      ),
    ),
  );
}

String _fmtEurFull(double v) {
  // Format with Spanish thousands separator and 2 decimal places: 10.073.250,00€
  final parts = v.toStringAsFixed(2).split('.');
  final intPart = parts[0];
  final decPart = parts[1];
  final buffer = StringBuffer();
  int count = 0;
  for (int i = intPart.length - 1; i >= 0; i--) {
    if (count > 0 && count % 3 == 0) buffer.write('.');
    buffer.write(intPart[i]);
    count++;
  }
  return '${buffer.toString().split('').reversed.join()},$decPart€';
}

String _fmtDate(String iso) {
  try {
    return DateFormat('d MMM yyyy', 'es').format(DateTime.parse(iso));
  } catch (_) {
    return iso;
  }
}
