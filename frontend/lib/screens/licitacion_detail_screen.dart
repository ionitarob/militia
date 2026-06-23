import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show PopupMenuItem, RelativeRect, Scrollbar, SelectionArea, showMenu;
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/client.dart';
import '../api/models.dart';
import '../services/auth_service.dart';
import '../widgets/liti_chat_overlay.dart';
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
  'PENDIENTE SOLICITUD DE COTIZACIÓN A PROVEEDOR',
  'COTIZACIÓN SOLICITADA (A PROVEEDOR)',
  'PENDIENTE ENVÍO DE COTIZACIÓN A CLIENTE',
  'COTIZACIÓN ENVIADA A CLIENTE - X4A',
  'RECHAZADO',
];
const _cotizacionDivisiones = [
  'DIVISIÓN ALAN JAUMANDREU',
  'DIVISIÓN JORGE NICOLÁS',
  'DIVISIÓN SERVICIOS (OSCAR GONZÁLEZ)',
  'DIVISIÓN MARTIN TRULLAS',
  'DIVISIÓN AVPRO/UCC (ALEX RINCÓN)',
  'DIVISIÓN DCPOS/PHSEC (SERGIO PATIÑO)',
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

  Map<String, ClienteCotizacion> _cotizaciones = {};
  bool _loadingCotizaciones = true;

  AdjudicacionResumen? _adjudicacion;

  List<StageHistoryItem> _stageHistory = [];
  bool _loadingHistory = true;
  final ScrollController _historialScrollCtrl = ScrollController();

  bool get _isAdmin => AuthService().currentUser?.role == 'admin';
  bool get _canEdit =>
      _isAdmin ||
      _lic.assignees.any((a) => a.id == AuthService().currentUser?.id);

  @override
  void initState() {
    super.initState();
    _lic = widget.licitacion;
    _loadNotes();
    _loadCotizaciones();
    _loadDocumentos();
    _loadAdjuntos();
    _loadStageHistory();
    _loadAdjudicacion();
    litiChat.setScreenContext(
      'Detalle de licitación — Título: ${_lic.titulo} | '
      'Expediente: ${_lic.numeroExpediente} | '
      '${_lic.organismoNombre != null ? "Organismo: ${_lic.organismoNombre} | " : ""}'
      '${_lic.importeLicitacion != null ? "Importe: ${_lic.importeLicitacion}€ | " : ""}'
      '${_lic.comunidadAutonoma != null ? "CCAA: ${_lic.comunidadAutonoma} | " : ""}'
      '${_lic.fechaLimiteOferta != null ? "Fecha límite: ${_lic.fechaLimiteOferta}" : ""}',
      licitacionId: _lic.id,
    );
  }

  @override
  void dispose() {
    _historialScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAdjudicacion() async {
    try {
      final a = await ApiClient().getAdjudicacionResumen(_lic.id);
      if (mounted) setState(() => _adjudicacion = a);
    } catch (_) {}
  }

  Future<void> _loadStageHistory() async {
    try {
      final h = await ApiClient().getStageHistory(_lic.id);
      if (mounted) {
        setState(() {
          _stageHistory = h;
          _loadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
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

  Future<void> _uploadAdjunto(
    String nombre,
    String contentType,
    Uint8List bytes,
  ) async {
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
      if (uploadRes.statusCode != 200)
        throw Exception('Upload failed: ${uploadRes.statusCode}');
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
        setState(
          () => _adjuntos = _adjuntos.where((a) => a.id != adjuntoId).toList(),
        );
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
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
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

  Future<void> _saveCotizacion(
    String cliente,
    String? xv,
    String? opp,
    String? cotizacionId,
    String? oportunidadId,
    String? estado,
    List<String> divisiones,
    bool fabricanteProteccion,
    String? fabricanteNombre,
    bool? vaConPliego,
  ) async {
    try {
      final me = AuthService().currentUser;
      await ApiClient().upsertClienteCotizacion(
        _lic.id,
        cliente,
        cotizacionXv: xv,
        oportunidad: opp,
        cotizacionId: cotizacionId,
        oportunidadId: oportunidadId,
        estado: estado,
        divisiones: divisiones,
        fabricanteProteccion: false,
        fabricanteNombre: null,
        userId: me?.id,
        vaConPliego: vaConPliego,
      );
      if (mounted) {
        setState(() {
          _cotizaciones[cliente] = ClienteCotizacion(
            clienteNombre: cliente,
            cotizacionXv: xv,
            oportunidad: opp,
            cotizacionId: cotizacionId,
            oportunidadId: oportunidadId,
            estado: estado,
            divisiones: divisiones,
            fabricanteProteccion: false,
            fabricanteNombre: null,
            userId: me?.id,
            vaConPliego: vaConPliego,
          );
          // Auto-advance pipeline stage from client estados (never override terminal outcomes)
          const terminal = {
            'ganada',
            'perdida',
            'rechazada',
            'desierta',
            'presentada',
          };
          if (!terminal.contains(_lic.pipelineStage)) {
            final all = _cotizaciones.values;
            final String derived;
            if (all.any(
              (c) => c.estado == 'COTIZACIÓN ENVIADA A CLIENTE - X4A',
            )) {
              derived = 'cotizaciones_enviadas';
            } else if (all.any((c) => c.estado != null)) {
              derived = 'en_proceso';
            } else {
              derived = _lic.pipelineStage;
            }
            if (derived != _lic.pipelineStage) {
              _lic = _lic.copyWith(pipelineStage: derived);
            }
          }
        });
        _loadStageHistory();
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<void> _onRechazar(bool rechazada, String? motivo) async {
    try {
      final newStage = rechazada ? 'rechazada' : 'en_proceso';
      await ApiClient().updateStage(_lic.id, newStage);
      if (mounted) {
        setState(() {
          _lic = _lic.copyWith(pipelineStage: newStage);
        });
        _loadStageHistory();
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
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
          child: SelectionArea(
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
                                adjudicacion: _adjudicacion,
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
            ), // Column
          ), // SelectionArea
        ), // SafeArea
      ), // CupertinoPageScaffold
    ); // PopScope
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
          child: Column(
            children: [
              ..._lic.assignees.map((a) {
                final isMe = AuthService().currentUser?.id == a.id;
                return _AssigneeRow(
                  name: a.displayName,
                  isAdmin: _isAdmin,
                  canUnassign: _isAdmin || isMe,
                  onReassign: _isAdmin ? _showReassignSheet : null,
                  onUnassign: () => _unassign(a.id),
                );
              }),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    if (_lic.assignees.isEmpty) ...[
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
                    ] else
                      const Spacer(),
                    if (_isAdmin)
                      Builder(
                        builder: (btnCtx) => CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: () => _showReassignSheet(btnCtx),
                          child: Text(
                            _lic.assignees.isEmpty ? 'Asignar' : 'Añadir',
                            style: const TextStyle(
                              fontSize: 13,
                              color: _blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    else if (!_lic.assignees.any(
                      (a) => a.id == AuthService().currentUser?.id,
                    ))
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
            ],
          ),
        ),

        // Clientes
        _PanelSection(
          icon: CupertinoIcons.table,
          label: 'Cotizaciones',
          color: _navy,
          child: _loadingCotizaciones
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CupertinoActivityIndicator()),
                )
              : _ClientesTable(
                  clientes: _clientesFijos,
                  cotizaciones: _cotizaciones,
                  assignees: _lic.assignees,
                  onSave: _saveCotizacion,
                  canEdit: _canEdit,
                  licitacionId: _lic.id,
                  isRechazada: _lic.pipelineStage == 'rechazada',
                ),
        ),

        // Archivos adjuntos (PDF upload)
        _PanelSection(
          icon: CupertinoIcons.doc_fill,
          label: 'Archivos adjuntos',
          color: const Color(0xFF0891B2),
          child: _CotizacionAdjuntosPanel(
            adjuntos: _adjuntos,
            loading: _loadingAdjuntos,
            uploading: _uploadingAdjunto,
            onPickFile: _pickAndUpload,
            onDropFile: (nombre, ct, bytes) =>
                _uploadAdjunto(nombre, ct, bytes),
            onDelete: _deleteAdjunto,
            canEdit: _canEdit,
          ),
        ),

        // Notas
        _PanelSection(
          icon: CupertinoIcons.chat_bubble_text_fill,
          label: 'Notas',
          color: _gold,
          trailing: _canEdit
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: _showAddNoteSheet,
                  child: const Icon(
                    CupertinoIcons.plus_circle_fill,
                    size: 20,
                    color: _blue,
                  ),
                )
              : null,
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

        // ¿La operación está protegida por un fabricante?
        _PanelSection(
          icon: CupertinoIcons.shield_fill,
          label: 'Protección de Fabricante (Global)',
          color: const Color(0xFFE11D48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '¿Operación protegida?',
                        style: TextStyle(
                          fontSize: 13,
                          color: _ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (!_canEdit)
                      Text(
                        _lic.fabricanteProteccion ? 'Sí' : 'No',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _navy,
                        ),
                      )
                    else
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: () async {
                          final picked = await showCupertinoModalPopup<bool>(
                            context: context,
                            builder: (ctx) => CupertinoActionSheet(
                              title: const Text(
                                '¿Está protegida por un fabricante?',
                              ),
                              actions: [
                                CupertinoActionSheetAction(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Sí'),
                                ),
                                CupertinoActionSheetAction(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('No'),
                                ),
                              ],
                              cancelButton: CupertinoActionSheetAction(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancelar'),
                              ),
                            ),
                          );
                          if (picked == null) return;
                          try {
                            await ApiClient().updateFabricante(
                              _lic.id,
                              fabricanteProteccion: picked,
                              fabricanteNombre: picked
                                  ? _lic.fabricanteNombre
                                  : null,
                            );
                            setState(() {
                              _lic = _lic.copyWith(
                                fabricanteProteccion: picked,
                                fabricanteNombre: picked
                                    ? () => _lic.fabricanteNombre
                                    : () => null,
                              );
                            });
                          } catch (e) {
                            _showError(e.toString());
                          }
                        },
                        child: Text(
                          _lic.fabricanteProteccion ? 'Sí' : 'No',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                if (_lic.fabricanteProteccion) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Fabricante:',
                    style: TextStyle(fontSize: 12, color: _muted),
                  ),
                  const SizedBox(height: 4),
                  if (!_canEdit)
                    Text(
                      _lic.fabricanteNombre ?? 'Sin nombre',
                      style: const TextStyle(fontSize: 13, color: _ink),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoTextField(
                            placeholder: 'Escribe el fabricante...',
                            controller: TextEditingController(
                              text: _lic.fabricanteNombre ?? '',
                            ),
                            style: const TextStyle(fontSize: 13),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _white,
                              border: Border.all(color: _border),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            onSubmitted: (val) async {
                              final name = val.trim();
                              try {
                                await ApiClient().updateFabricante(
                                  _lic.id,
                                  fabricanteProteccion: true,
                                  fabricanteNombre: name.isEmpty ? null : name,
                                );
                                setState(() {
                                  _lic = _lic.copyWith(
                                    fabricanteNombre: () =>
                                        name.isEmpty ? null : name,
                                  );
                                });
                                HapticFeedback.lightImpact();
                              } catch (e) {
                                _showError(e.toString());
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),

        // Historial de cambios de estado
        _PanelSection(
          icon: CupertinoIcons.clock,
          label: 'Historial de cambios',
          color: const Color(0xFF8B5CF6),
          child: _loadingHistory
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CupertinoActivityIndicator()),
                )
              : _stageHistory.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Sin cambios de estado registrados.',
                    style: TextStyle(fontSize: 13, color: _muted),
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: Scrollbar(
                    controller: _historialScrollCtrl,
                    thumbVisibility: true,
                    radius: const Radius.circular(4),
                    thickness: 3,
                    child: SingleChildScrollView(
                      controller: _historialScrollCtrl,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < _stageHistory.length; i++) ...[
                            if (i > 0) const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  CupertinoIcons.circle_fill,
                                  size: 8,
                                  color: Color(0xFF8B5CF6),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            _translateStage(
                                              _stageHistory[i].stage,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: _navy,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            _fmtHistoryDate(
                                              _stageHistory[i].changedAt,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: _muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_stageHistory[i].userNombre !=
                                          null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Por: ${_stageHistory[i].userNombre}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: _muted,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ), // SingleChildScrollView
                ), // Scrollbar
        ), // ConstrainedBox
        // Rechazado — at the very bottom; rejects the entire pliego
        _RechazadoSection(
          isRechazada: _lic.pipelineStage == 'rechazada',
          canEdit: _canEdit,
          onRechazar: _onRechazar,
        ),

        const SizedBox(height: 100),
      ],
    );

    if (!scroll) return content;
    return SingleChildScrollView(child: content);
  }

  String _fmtHistoryDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final day =
          '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      final hour =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      return '$day $hour';
    } catch (_) {
      return iso.length >= 10 ? iso.substring(0, 10) : iso;
    }
  }

  String _translateStage(String stage) {
    switch (stage) {
      case 'nueva':
        return 'Nueva';
      case 'asignada':
        return 'Asignada';
      case 'en_proceso':
        return 'En proceso';
      case 'cotizaciones_enviadas':
        return 'Cotización enviada';
      case 'presentada':
        return 'Presentada';
      case 'ganada':
        return 'Ganada';
      case 'perdida':
        return 'Perdida';
      case 'rechazada':
        return 'Rechazada';
      case 'desierta':
        return 'Desierta';
      default:
        return stage;
    }
  }

  // ── Unassign ──────────────────────────────────────────────────────────────

  Future<void> _unassign(int userId) async {
    try {
      await ApiClient().unassignLicitacion(_lic.id, userId);
      if (!mounted) return;
      setState(() {
        final updated = _lic.assignees.where((a) => a.id != userId).toList();
        _lic = _lic.copyWith(
          assignees: updated,
          pipelineStage: updated.isEmpty && _lic.pipelineStage == 'asignada'
              ? 'nueva'
              : null,
        );
      });
      _loadStageHistory();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  // ── Self-assign (vendedor) ────────────────────────────────────────────────

  Future<void> _selfAssign() async {
    final me = AuthService().currentUser;
    if (me == null) return;
    try {
      await ApiClient().assignLicitacion(_lic.id, me.id);
      if (!mounted) return;
      setState(() {
        final newAssignee = LicitacionAssignee(
          id: me.id,
          nombre: me.nombre ?? me.email,
        );
        final updated = [
          ..._lic.assignees.where((a) => a.id != me.id),
          newAssignee,
        ];
        _lic = _lic.copyWith(
          assignees: updated,
          pipelineStage: _lic.pipelineStage == 'nueva' ? 'asignada' : null,
        );
      });
      _loadStageHistory();
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
                      child: _lic.assignees.any((a) => a.id == v.id)
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
      final isAssigned = _lic.assignees.any((a) => a.id == picked.id);
      if (isAssigned) {
        await _unassign(picked.id);
      } else {
        await ApiClient().assignLicitacion(_lic.id, picked.id);
        setState(() {
          final newAssignee = LicitacionAssignee(
            id: picked.id,
            nombre: picked.displayName,
          );
          final updated = [
            ..._lic.assignees.where((a) => a.id != picked.id),
            newAssignee,
          ];
          _lic = _lic.copyWith(
            assignees: updated,
            pipelineStage: _lic.pipelineStage == 'nueva' ? 'asignada' : null,
          );
        });
        _loadStageHistory();
      }
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
  final AdjudicacionResumen? adjudicacion;

  const _LeftPanel({
    required this.lic,
    this.docs = const [],
    this.loadingDocs = false,
    this.adjudicacion,
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

          // ── Liti AI Summary ──────────────────────────────────────
          _LitiSummary(lic: lic),
          const SizedBox(height: 10),

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

          // ── Adjudicación ────────────────────────────────────────
          if (adjudicacion != null) ...[
            const SizedBox(height: 10),
            _DataCard(
              children: [
                _SectionHeader(label: 'ADJUDICADA'),
                if (adjudicacion!.adjudicatarioNombre != null) ...[
                  _divider(),
                  _DataRow(
                    label: 'Adjudicatario',
                    value: adjudicacion!.adjudicatarioNombre!,
                    icon: CupertinoIcons.building_2_fill,
                    iconColor: _green,
                  ),
                ],
                if (adjudicacion!.importeAdjudicado != null) ...[
                  _divider(),
                  _DataRow(
                    label: 'Importe adjudicado',
                    value: '${_fmtEurFull(adjudicacion!.importeAdjudicado!)}€',
                    icon: CupertinoIcons.money_euro_circle_fill,
                    iconColor: _green,
                  ),
                ],
                if (adjudicacion!.ratio != null) ...[
                  _divider(),
                  _DataRow(
                    label: 'Ratio adj./licit.',
                    value:
                        '${(adjudicacion!.ratio! * 100).toStringAsFixed(1)}%',
                    icon: CupertinoIcons.percent,
                    iconColor: _muted,
                  ),
                ],
                if (adjudicacion!.fechaAdjudicacion != null) ...[
                  _divider(),
                  _DataRow(
                    label: 'Fecha adjudicación',
                    value: adjudicacion!.fechaAdjudicacion!.substring(0, 10),
                    icon: CupertinoIcons.calendar_badge_plus,
                    iconColor: _muted,
                  ),
                ],
              ],
            ),
          ],

          // ── Documentos adjuntos ─────────────────────────────────
          if (loadingDocs || docs.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DataCard(
              children: [
                _SectionHeader(label: 'Archivos adjuntos'),
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

// ── Clientes table ────────────────────────────────────────────────────────────

String _shortDivision(String v) => v.replaceFirst('DIVISIÓN ', '');

String _shortEstadoCotiz(String v) {
  if (v.startsWith('PENDIENTE SOLICITUD')) return 'Pend. Solicitud';
  if (v.startsWith('COTIZACIÓN SOLICITADA')) return 'Cotiz. Solicitada';
  if (v.startsWith('PENDIENTE ENVÍO')) return 'Pend. Envío';
  if (v.startsWith('COTIZACIÓN ENVIADA')) return 'Enviada Cliente';
  if (v.startsWith('RECHAZADO')) return 'Rechazado';
  return v;
}

(Color, Color) _estadoColor(int i) {
  switch (i) {
    case 0:
      return (const Color(0xFFF1F4F9), const Color(0xFF6B7280));
    case 1:
      return (const Color(0xFFEFF6FF), const Color(0xFF2563EB));
    case 2:
      return (const Color(0xFFFFFBEB), const Color(0xFFD97706));
    case 3:
      return (const Color(0xFFECFDF5), const Color(0xFF059669));
    case 4:
      return (const Color(0xFFFEF2F2), const Color(0xFFDC2626));
    default:
      return (const Color(0xFFF1F4F9), const Color(0xFF6B7280));
  }
}

class _ClientesTable extends StatefulWidget {
  final List<String> clientes;
  final Map<String, ClienteCotizacion> cotizaciones;
  final List<LicitacionAssignee> assignees;
  final Future<void> Function(
    String cliente,
    String? xv,
    String? opp,
    String? cotizacionId,
    String? oportunidadId,
    String? estado,
    List<String> divisiones,
    bool fabricanteProteccion,
    String? fabricanteNombre,
    bool? vaConPliego,
  )
  onSave;
  final bool canEdit;
  final int licitacionId;
  final bool isRechazada;

  const _ClientesTable({
    required this.clientes,
    required this.cotizaciones,
    required this.assignees,
    required this.onSave,
    required this.canEdit,
    required this.licitacionId,
    required this.isRechazada,
  });

  @override
  State<_ClientesTable> createState() => _ClientesTableState();
}

class _ClientesTableState extends State<_ClientesTable> {
  final Set<String> _checked = {};
  final Map<
    String,
    (
      TextEditingController,
      TextEditingController,
      TextEditingController,
      TextEditingController,
    )
  >
  _ctrls = {};
  final Map<String, List<String>> _divisiones = {};
  final Map<String, String?> _estado = {};
  final Map<String, bool?> _vaConPliego = {};
  final Map<String, bool> _fabricanteProteccion = {};
  final Map<String, TextEditingController> _fabricanteNombreCtrls = {};
  final Set<String> _saving = {};
  final Set<String> _editing = {};
  final Set<int?> _expandedCompaneros = {};

  @override
  void initState() {
    super.initState();
    for (final c in widget.cotizaciones.keys) {
      final d = widget.cotizaciones[c]!;
      if ((d.cotizacionXv?.isNotEmpty ?? false) ||
          (d.oportunidad?.isNotEmpty ?? false) ||
          d.estado != null ||
          d.divisiones.isNotEmpty ||
          d.vaConPliego != null) {
        _checked.add(c);
        _ctrls[c] = (
          TextEditingController(text: d.cotizacionXv ?? ''),
          TextEditingController(text: d.oportunidad ?? ''),
          TextEditingController(text: d.cotizacionId ?? ''),
          TextEditingController(text: d.oportunidadId ?? ''),
        );
        _divisiones[c] = List<String>.from(d.divisiones);
        _estado[c] = d.estado;
        _vaConPliego[c] = d.vaConPliego;
      }
      _fabricanteProteccion[c] = d.fabricanteProteccion;
      _fabricanteNombreCtrls[c] = TextEditingController(
        text: d.fabricanteNombre ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final p in _ctrls.values) {
      p.$1.dispose();
      p.$2.dispose();
      p.$3.dispose();
      p.$4.dispose();
    }
    for (final c in _fabricanteNombreCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggle(String cliente) {
    if (!widget.canEdit) return;
    setState(() {
      if (_checked.contains(cliente)) {
        _checked.remove(cliente);
        _editing.remove(cliente);
        _divisiones.remove(cliente);
        _estado.remove(cliente);
        _vaConPliego.remove(cliente);
        _fabricanteProteccion.remove(cliente);
        _fabricanteNombreCtrls[cliente]?.dispose();
        _fabricanteNombreCtrls.remove(cliente);
        _ctrls[cliente]?.$1.dispose();
        _ctrls[cliente]?.$2.dispose();
        _ctrls[cliente]?.$3.dispose();
        _ctrls[cliente]?.$4.dispose();
        _ctrls.remove(cliente);
        widget.onSave(
          cliente,
          null,
          null,
          null,
          null,
          null,
          [],
          false,
          null,
          null,
        );
      } else {
        _checked.add(cliente);
        final d = widget.cotizaciones[cliente];
        _ctrls[cliente] = (
          TextEditingController(text: d?.cotizacionXv ?? ''),
          TextEditingController(text: d?.oportunidad ?? ''),
          TextEditingController(text: d?.cotizacionId ?? ''),
          TextEditingController(text: d?.oportunidadId ?? ''),
        );
        _divisiones[cliente] = d?.divisiones != null
            ? List<String>.from(d!.divisiones)
            : [];
        _estado[cliente] = d?.estado;
        _vaConPliego[cliente] = d?.vaConPliego;
        _fabricanteProteccion[cliente] = d?.fabricanteProteccion ?? false;
        _fabricanteNombreCtrls[cliente] = TextEditingController(
          text: d?.fabricanteNombre ?? '',
        );
      }
    });
  }

  Future<void> _save(String cliente) async {
    final p = _ctrls[cliente];
    if (p == null) return;
    setState(() => _saving.add(cliente));
    final fabProteccion = _fabricanteProteccion[cliente] ?? false;
    final fabNombre = _fabricanteNombreCtrls[cliente]?.text.trim();
    try {
      await widget.onSave(
        cliente,
        p.$1.text.trim().isEmpty ? null : p.$1.text.trim(),
        p.$2.text.trim().isEmpty ? null : p.$2.text.trim(),
        p.$3.text.trim().isEmpty ? null : p.$3.text.trim(),
        p.$4.text.trim().isEmpty ? null : p.$4.text.trim(),
        _estado[cliente],
        _divisiones[cliente] ?? [],
        fabProteccion,
        fabProteccion && (fabNombre?.isNotEmpty ?? false) ? fabNombre : null,
        _vaConPliego[cliente],
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving.remove(cliente);
          _editing.remove(cliente);
        });
      }
    }
  }

  Future<void> _showAddPicker(BuildContext context) async {
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

  // Steps 0-3 as numbered circles connected by lines; step 4 as a red pill
  Widget _buildEstadoStepper(String cliente, bool isLocked) {
    final current = _estado[cliente];
    final isRechazado = current != null && current.startsWith('RECHAZADO');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Rechazado',
                style: TextStyle(fontSize: 12, color: _ink),
              ),
            ),
            if (isLocked)
              Text(
                isRechazado ? 'Sí' : 'No',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isRechazado ? _red : _muted,
                ),
              )
            else
              CupertinoSwitch(
                value: isRechazado,
                activeTrackColor: _red,
                onChanged: (v) {
                  if (v) {
                    _showRejectionReasonDialog(cliente);
                  } else {
                    setState(() => _estado[cliente] = null);
                  }
                },
              ),
          ],
        ),
        if (isRechazado) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Motivo: ${_getRejectionReason(current)}',
              style: const TextStyle(
                fontSize: 11,
                color: _red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String? _getRejectionReason(String? val) {
    if (val == null || !val.startsWith('RECHAZADO')) return null;
    if (val.startsWith('RECHAZADO - ')) {
      return val.substring('RECHAZADO - '.length);
    }
    return 'Rechazado';
  }

  Future<void> _showRejectionReasonDialog(String cliente) async {
    final TextEditingController textCtrl = TextEditingController();
    int selectedOption = 0; // 0: None, 1: Ingram no trabaja..., 2: Otro

    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return CupertinoAlertDialog(
              title: const Text('Motivo de rechazo'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => setDialogState(() => selectedOption = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selectedOption == 1
                            ? const Color(0xFFEFF6FF)
                            : null,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: selectedOption == 1
                              ? _blue
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ingram no trabaja con este fabricante',
                              style: TextStyle(fontSize: 13, color: _ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setDialogState(() => selectedOption = 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selectedOption == 2
                            ? const Color(0xFFEFF6FF)
                            : null,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: selectedOption == 2
                              ? _blue
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Otro motivo',
                              style: TextStyle(fontSize: 13, color: _ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (selectedOption == 2) ...[
                    const SizedBox(height: 10),
                    CupertinoTextField(
                      controller: textCtrl,
                      placeholder: 'Escribe el motivo...',
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                    ),
                  ],
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('Cancelar'),
                  onPressed: () => Navigator.pop(ctx),
                ),
                CupertinoDialogAction(
                  child: const Text('Aceptar'),
                  onPressed: () {
                    if (selectedOption == 1) {
                      Navigator.pop(
                        ctx,
                        'RECHAZADO - Ingram no trabaja con este fabricante',
                      );
                    } else if (selectedOption == 2) {
                      final val = textCtrl.text.trim();
                      if (val.isEmpty) {
                        Navigator.pop(ctx, 'RECHAZADO - Otro');
                      } else {
                        Navigator.pop(ctx, 'RECHAZADO - Otro: $val');
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _estado[cliente] = result;
      });
    }
  }

  Widget _buildVaConPliegoToggle(String cliente, bool isLocked) {
    final val = _vaConPliego[cliente];
    return Row(
      children: [
        const Expanded(
          child: Text(
            '¿El cliente finalmente se presenta?',
            style: TextStyle(fontSize: 12, color: _ink),
          ),
        ),
        if (isLocked)
          Text(
            val == null ? 'Sin responder' : (val ? 'Sí' : 'No'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: val == null ? _muted : (val ? _green : _red),
            ),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => setState(() => _vaConPliego[cliente] = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: val == true ? _green : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: val == true ? _green : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Text(
                    'Sí',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: val == true ? _white : _muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _vaConPliego[cliente] = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: val == false ? _red : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: val == false ? _red : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Text(
                    'No',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: val == false ? _white : _muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildDivisionChips(String cliente, bool isLocked) {
    final selected = _divisiones[cliente] ?? [];

    if (isLocked) {
      if (selected.isEmpty) {
        return const Text(
          'Sin división asignada',
          style: TextStyle(
            fontSize: 11,
            color: _muted,
            fontStyle: FontStyle.italic,
          ),
        );
      }
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: selected.map((div) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(
              _shortDivision(div),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _navy,
              ),
            ),
          );
        }).toList(),
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: _cotizacionDivisiones.map((div) {
        final isSel = selected.contains(div);
        return GestureDetector(
          onTap: () {
            setState(() {
              final list = List<String>.from(_divisiones[cliente] ?? []);
              if (list.contains(div)) {
                list.remove(div);
              } else {
                list.add(div);
              }
              _divisiones[cliente] = list;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: isSel
                  ? _blue.withValues(alpha: 0.08)
                  : const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSel ? _blue : const Color(0xFFCBD5E1),
                width: isSel ? 1.2 : 1,
              ),
            ),
            child: Text(
              _shortDivision(div),
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                color: isSel ? _navy : _muted,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checked = [
      ...widget.clientes.where((c) => _checked.contains(c)),
      ..._checked.where((c) => !widget.clientes.contains(c)),
    ];

    final currentUserId = AuthService().currentUser?.id;

    // For legacy records with null userId: attribute to the sole assignee if
    // there is only one; otherwise the owner is unknown.
    final int? soloAssigneeId = widget.assignees.length == 1
        ? widget.assignees.first.id
        : null;

    String nameFor(int? uid) {
      if (uid == null) return 'Sin asignar';
      if (uid == currentUserId) {
        final u = AuthService().currentUser;
        return u?.nombre ?? u?.email.split('@').first ?? 'Yo';
      }
      final a = widget.assignees.firstWhere(
        (a) => a.id == uid,
        orElse: () => LicitacionAssignee(id: uid),
      );
      return a.displayName;
    }

    // Split into mine vs. compañeros.
    // Newly-checked entries not yet saved have no cotizacion record — treat as mine.
    // Saved records with null userId fall back to soloAssigneeId (legacy backfill).
    final myClients = <String>[];
    final Map<int?, List<String>> byCompanero = {};
    for (final c in checked) {
      final saved = widget.cotizaciones[c];
      final int? uid;
      if (saved == null) {
        uid = currentUserId;
      } else {
        uid = saved.userId ?? soloAssigneeId;
      }
      if (uid == currentUserId) {
        myClients.add(c);
      } else {
        byCompanero.putIfAbsent(uid, () => []).add(c);
      }
    }

    // Order compañeros deterministically: known users by name, null last
    final knownCompaneroIds =
        byCompanero.keys.where((id) => id != null).toList()
          ..sort((a, b) => nameFor(a).compareTo(nameFor(b)));
    final companeroIds = [
      ...knownCompaneroIds,
      if (byCompanero.containsKey(null)) null,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (myClients.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildSectionHeader(
            'MIS COTIZACIONES',
            accent: const Color(0xFF2563EB),
            bg: const Color(0xFFEFF6FF),
            icon: CupertinoIcons.person_fill,
          ),
          ...myClients.map(
            (c) => _buildCard(c, cardAccent: const Color(0xFF2563EB)),
          ),
          if (widget.canEdit && !widget.isRechazada)
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => _showAddPicker(context),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.plus_circle,
                        size: 15,
                        color: _blue,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Añadir otro cliente',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (myClients.isEmpty && widget.canEdit && !widget.isRechazada) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _showAddPicker(context),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.plus_circle,
                    size: 16,
                    color: _blue,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Añadir cliente',
                    style: TextStyle(
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
        if (companeroIds.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildSectionHeader(
            'COTIZACIONES DE MIS COMPAÑEROS',
            accent: const Color(0xFF7C3AED),
            bg: const Color(0xFFF5F3FF),
            icon: CupertinoIcons.person_2_fill,
          ),
          for (final uid in companeroIds) ...[
            _buildCompaneroHeader(uid, nameFor(uid), byCompanero[uid]!.length),
            if (_expandedCompaneros.contains(uid))
              ...byCompanero[uid]!.map(
                (c) => _buildCard(
                  c,
                  readOnly: true,
                  cardAccent: const Color(0xFF7C3AED),
                ),
              ),
          ],
        ],
      ],
    );
  }

  Widget _buildSectionHeader(
    String label, {
    Color? accent,
    Color? bg,
    IconData? icon,
  }) {
    if (accent != null && bg != null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: accent),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: accent,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _muted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: const Color(0xFFE5E7EB))),
        ],
      ),
    );
  }

  Widget _buildCompaneroHeader(int? uid, String name, int count) {
    final expanded = _expandedCompaneros.contains(uid);
    return GestureDetector(
      onTap: () => setState(() {
        if (expanded) {
          _expandedCompaneros.remove(uid);
        } else {
          _expandedCompaneros.add(uid);
        }
      }),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(CupertinoIcons.person_fill, size: 14, color: _muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ),
            Text('$count', style: const TextStyle(fontSize: 12, color: _muted)),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: _muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    String cliente, {
    bool readOnly = false,
    Color? cardAccent,
  }) {
    final isSaving = _saving.contains(cliente);
    final p = _ctrls[cliente];
    final d = widget.cotizaciones[cliente];
    final hasSaved =
        (d?.cotizacionXv?.isNotEmpty ?? false) ||
        (d?.oportunidad?.isNotEmpty ?? false) ||
        d?.estado != null ||
        (d?.divisiones.isNotEmpty ?? false) ||
        d?.vaConPliego != null;
    final isLocked =
        readOnly ||
        !widget.canEdit ||
        (hasSaved && !_editing.contains(cliente));
    final currentEstado = _estado[cliente];
    final isRechazado =
        currentEstado != null && currentEstado.startsWith('RECHAZADO');
    final accentColor = isRechazado
        ? const Color(0xFFDC2626)
        : (cardAccent ?? const Color(0xFFCBD5E1));
    final cardBg = isRechazado
        ? const Color(0xFFFFFAFA)
        : (cardAccent != null
              ? cardAccent.withValues(alpha: 0.04)
              : const Color(0xFFFFFFFF));
    final borderColor = isRechazado
        ? const Color(0xFFDC2626).withValues(alpha: 0.2)
        : (cardAccent != null
              ? cardAccent.withValues(alpha: 0.18)
              : const Color(0xFFE5E7EB));
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 4,
                color: accentColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row 1: name + actions
                      Row(
                        children: [
                          Text(
                            cliente,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _navy,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const Spacer(),
                          if (isSaving)
                            const CupertinoActivityIndicator(radius: 7)
                          else if (isLocked)
                            if (widget.canEdit)
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                onPressed: () =>
                                    setState(() => _editing.add(cliente)),
                                child: const Icon(
                                  CupertinoIcons.pencil_circle,
                                  size: 18,
                                  color: _muted,
                                ),
                              )
                            else
                              const SizedBox.shrink()
                          else
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              onPressed: () => _save(cliente),
                              child: const Icon(
                                CupertinoIcons.checkmark_circle_fill,
                                size: 18,
                                color: _green,
                              ),
                            ),
                          if (widget.canEdit) ...[
                            const SizedBox(width: 4),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              onPressed: () => _toggle(cliente),
                              child: const Icon(
                                CupertinoIcons.xmark_circle_fill,
                                size: 16,
                                color: _muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Row 2: division chips
                      const Text(
                        'Cotización enviada a las siguiente divisiones:',
                        style: TextStyle(fontSize: 12, color: _ink),
                      ),
                      const SizedBox(height: 4),
                      _buildDivisionChips(cliente, isLocked),
                      const SizedBox(height: 6),
                      // Oportunidad row: ID first, then link button
                      if (p != null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: _XvLinkField(
                                label: 'ID de la Oportunidad',
                                controller: p.$4,
                                isLocked: isLocked,
                                onSubmitted: () => _save(cliente),
                                placeholder: 'OPP-061715220929-42C2E',
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _XvLinkField(
                                label: 'Oportunidad',
                                controller: p.$2,
                                isLocked: isLocked,
                                onSubmitted: () => _save(cliente),
                                buttonLabel: 'Ver Oportunidad en XVantage',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Cotización row: ID first, then link button
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: _XvLinkField(
                                label: 'ID de la Cotización',
                                controller: p.$3,
                                isLocked: isLocked,
                                onSubmitted: () => _save(cliente),
                                placeholder: 'QUO-5246560-N3F6R9',
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _XvLinkField(
                                label: 'Cotización XV',
                                controller: p.$1,
                                isLocked: isLocked,
                                onSubmitted: () => _save(cliente),
                                buttonLabel: 'Ver Cotización en XVantage',
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Protección Fabricante per-client
                      _buildFabricante(cliente, isLocked),
                      const SizedBox(height: 6),
                      // ¿El cliente finalmente se presenta?
                      _buildVaConPliegoToggle(cliente, isLocked),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFabricante(String cliente, bool isLocked) {
    final isProtected = _fabricanteProteccion[cliente] ?? false;
    final ctrl = _fabricanteNombreCtrls[cliente];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isProtected ? const Color(0xFFFFF1F2) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isProtected
              ? const Color(0xFFFDA4AF)
              : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.shield_fill,
                size: 12,
                color: isProtected ? const Color(0xFFE11D48) : _muted,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Protección Fabricante',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ),
              if (isLocked)
                Text(
                  isProtected ? 'Sí' : 'No',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isProtected ? const Color(0xFFE11D48) : _muted,
                  ),
                )
              else
                CupertinoSwitch(
                  value: isProtected,
                  activeTrackColor: const Color(0xFFE11D48),
                  onChanged: (v) =>
                      setState(() => _fabricanteProteccion[cliente] = v),
                ),
            ],
          ),
          if (isProtected && ctrl != null) ...[
            const SizedBox(height: 6),
            CupertinoTextField(
              controller: ctrl,
              placeholder: 'Nombre del fabricante',
              readOnly: isLocked,
              style: TextStyle(fontSize: 11, color: isLocked ? _muted : _ink),
              placeholderStyle: const TextStyle(fontSize: 11, color: _muted),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isLocked ? const Color(0xFFF3F4F6) : _white,
                border: Border.all(
                  color: isLocked ? const Color(0xFFE5E7EB) : _border,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              onSubmitted: (_) => _save(cliente),
            ),
          ],
        ],
      ),
    );
  }
}

// ── XvLinkField — text field with copy button for XVantage links ──────────────

class _XvLinkField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool isLocked;
  final VoidCallback onSubmitted;
  final String? placeholder;
  final String? buttonLabel;

  const _XvLinkField({
    required this.label,
    required this.controller,
    required this.isLocked,
    required this.onSubmitted,
    this.placeholder,
    this.buttonLabel,
  });

  @override
  Widget build(BuildContext context) {
    final value = controller.text.trim();
    final hasValue = value.isNotEmpty;
    final isLink =
        hasValue &&
        (value.startsWith('http://') || value.startsWith('https://'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _muted,
          ),
        ),
        const SizedBox(height: 3),
        // Locked + has a URL → show as a labelled action button
        if (isLocked && isLink)
          GestureDetector(
            onTap: () => launchUrl(
              Uri.parse(value),
              mode: LaunchMode.externalApplication,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _blue,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.arrow_up_right_square,
                    size: 13,
                    color: Color(0xFFFFFFFF),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    buttonLabel ?? 'Ver ${label.toLowerCase()}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          )
        // Locked + plain text (IDs) or editing mode → standard text field + copy
        else
          Row(
            children: [
              Expanded(
                child: CupertinoTextField(
                  controller: controller,
                  placeholder: placeholder ?? 'Pegar enlace de XVantage...',
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
                    border: Border.all(
                      color: isLocked ? const Color(0xFFE5E7EB) : _border,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  onSubmitted: (_) => onSubmitted(),
                ),
              ),
              if (hasValue) ...[
                const SizedBox(width: 4),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: value));
                  },
                  child: const Icon(
                    CupertinoIcons.doc_on_doc,
                    size: 16,
                    color: _blue,
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

// ── Assignee row ──────────────────────────────────────────────────────────────

class _AssigneeRow extends StatelessWidget {
  final String name;
  final bool isAdmin;
  final bool canUnassign;
  final void Function(BuildContext)? onReassign;
  final VoidCallback? onUnassign;

  const _AssigneeRow({
    required this.name,
    required this.isAdmin,
    this.canUnassign = false,
    this.onReassign,
    this.onUnassign,
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
          if (canUnassign)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: onUnassign,
              child: const Icon(
                CupertinoIcons.xmark_circle,
                size: 18,
                color: _muted,
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
  final bool canEdit;

  const _CotizacionAdjuntosPanel({
    required this.adjuntos,
    required this.loading,
    required this.uploading,
    required this.onPickFile,
    required this.onDropFile,
    required this.onDelete,
    required this.canEdit,
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
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
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
        if (widget.canEdit)
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
                            color: _dragging ? const Color(0xFF0891B2) : _muted,
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
              canEdit: widget.canEdit,
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
  final bool canEdit;

  const _AdjuntoRow({
    required this.adjunto,
    required this.fmtSize,
    required this.onDelete,
    required this.canEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.doc_fill,
            size: 16,
            color: Color(0xFF0891B2),
          ),
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
                  builder: (_) =>
                      PdfPreviewScreen(url: adjunto.url, title: adjunto.nombre),
                ),
              ),
              child: const Icon(CupertinoIcons.eye, size: 16, color: _muted),
            ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => launchUrl(Uri.parse(adjunto.url)),
            child: const Icon(
              CupertinoIcons.arrow_down_to_line,
              size: 16,
              color: _muted,
            ),
          ),
          if (canEdit) ...[
            const SizedBox(width: 2),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: onDelete,
              child: const Icon(CupertinoIcons.trash, size: 15, color: _red),
            ),
          ],
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

// ── Motivo pérdida popup ──────────────────────────────────────────────────────

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

// ── Liti AI Summary ───────────────────────────────────────────────────────────
// Auto-streams an analysis of the licitacion + documents on load.
// A small "Preguntar a Liti" link at the bottom opens the chat overlay
// reusing the same session so Liti already has full context.

class _LitiSummary extends StatefulWidget {
  final Licitacion lic;
  const _LitiSummary({required this.lic});

  @override
  State<_LitiSummary> createState() => _LitiSummaryState();
}

class _LitiSummaryState extends State<_LitiSummary> {
  final _api = ApiClient();
  String _text = '';
  bool _loading = true;
  bool _expanded = false;
  String? _error;
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _text = '';
      _sessionId = null;
    });
    try {
      // Try cache first (unless the user explicitly asked for a refresh)
      if (!forceRefresh) {
        final cached = await _api.getLicitacionSummary(widget.lic.id);
        if (cached != null && cached.isNotEmpty) {
          if (mounted)
            setState(() {
              _text = cached;
              _loading = false;
            });
          return;
        }
      }

      // Stream from the dedicated Haiku summarize Lambda (auto-saves on completion)
      await _api
          .summarizeStream(widget.lic.id)
          .timeout(
            const Duration(seconds: 90),
            onTimeout: (sink) => sink.close(),
          )
          .forEach((event) {
            if (!mounted) return;
            if (event.containsKey('token')) {
              setState(() => _text += (event['token'] as String? ?? ''));
            } else if (event.containsKey('error')) {
              setState(() => _error = event['error'] as String?);
            }
          });
      if (mounted && _text.isEmpty && _error == null) {
        setState(
          () => _error = 'Sin respuesta del servidor. Pulsa ↺ para reintentar.',
        );
      }
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openChat() {
    final l = widget.lic;
    litiChat.setScreenContext(
      'Licitación: ${l.titulo}\nExpediente: ${l.numeroExpediente}',
      licitacionId: l.id,
    );
    // Reuse the summary session so Liti already has full document context
    if (_sessionId != null) litiChat.sessionId = _sessionId;
    litiChat.open();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6D28D9).withValues(alpha: 0.08),
            const Color(0xFF4F46E5).withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6D28D9), Color(0xFF4F46E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  CupertinoIcons.sparkles,
                  size: 12,
                  color: Color(0xFFFFFFFF),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Resumen Liti',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4C1D95),
                  ),
                ),
              ),
              if (_loading)
                const CupertinoActivityIndicator(
                  radius: 6,
                  color: Color(0xFF7C3AED),
                )
              else
                GestureDetector(
                  onTap: () => _loadSummary(forceRefresh: true),
                  child: const Icon(
                    CupertinoIcons.refresh,
                    size: 13,
                    color: Color(0xFF7C3AED),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Content
          if (_error != null)
            Text(_error!, style: const TextStyle(fontSize: 12, color: _red))
          else if (_text.isEmpty && _loading)
            _buildSkeleton()
          else ...[
            _MarkdownPreview(
              text: _text,
              expanded: _expanded,
              loading: _loading,
              onToggle: () => setState(() => _expanded = !_expanded),
            ),
          ],

          // "Preguntar a Liti" link
          if (!_loading && _text.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: const Color(0xFFE9D5FF)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _openChat,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    CupertinoIcons.chat_bubble_text,
                    size: 12,
                    color: Color(0xFF7C3AED),
                  ),
                  SizedBox(width: 5),
                  Text(
                    'Preguntar a Liti',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7C3AED),
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

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _skeletonBar(0.95),
        const SizedBox(height: 7),
        _skeletonBar(0.80),
        const SizedBox(height: 7),
        _skeletonBar(0.90),
        const SizedBox(height: 7),
        _skeletonBar(0.55),
        const SizedBox(height: 12),
        _skeletonBar(0.70),
        const SizedBox(height: 7),
        _skeletonBar(0.85),
        const SizedBox(height: 7),
        _skeletonBar(0.60),
      ],
    );
  }

  Widget _skeletonBar(double widthFactor) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 11,
        decoration: BoxDecoration(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

// ── Markdown preview with expand/collapse ─────────────────────────────────────

class _MarkdownPreview extends StatelessWidget {
  final String text;
  final bool expanded;
  final bool loading;
  final VoidCallback onToggle;

  const _MarkdownPreview({
    required this.text,
    required this.expanded,
    required this.loading,
    required this.onToggle,
  });

  static final _sheet = MarkdownStyleSheet(
    p: const TextStyle(fontSize: 12.5, color: _ink, height: 1.6),
    h1: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: _navy,
    ),
    h2: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: _navy,
    ),
    h3: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: _navy,
    ),
    strong: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: _ink,
    ),
    listBullet: const TextStyle(fontSize: 12.5, color: Color(0xFF6D28D9)),
    blockquotePadding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
    blockquoteDecoration: BoxDecoration(
      color: const Color(0xFFF3F0FF),
      border: const Border(
        left: BorderSide(color: Color(0xFF7C3AED), width: 3),
      ),
      borderRadius: BorderRadius.circular(2),
    ),
  );

  String get _previewText {
    // Keep taking blocks until we have at least 500 chars of real content, max 7 blocks
    final blocks = text.split(RegExp(r'\n{2,}'));
    if (blocks.length <= 7) return text;
    var count = 0;
    var chars = 0;
    for (final b in blocks) {
      count++;
      chars += b.length;
      if (count >= 4 && chars >= 500) break;
      if (count >= 7) break;
    }
    return blocks.take(count).join('\n\n');
  }

  bool get _hasMore {
    final blocks = text.split(RegExp(r'\n{2,}'));
    if (blocks.length <= 7) return false;
    var count = 0;
    var chars = 0;
    for (final b in blocks) {
      count++;
      chars += b.length;
      if (count >= 4 && chars >= 500) break;
      if (count >= 7) break;
    }
    return blocks.length > count;
  }

  @override
  Widget build(BuildContext context) {
    final displayText = expanded ? text : _previewText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownBody(
          data: displayText,
          styleSheet: _sheet,
          softLineBreak: true,
        ),

        // Toggle button — only show when there's more content and not mid-stream
        if (!loading && _hasMore) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onToggle,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  expanded ? 'Ver menos' : 'Ver resumen completo',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7C3AED),
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 11,
                  color: const Color(0xFF7C3AED),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RechazadoSection extends StatefulWidget {
  final bool isRechazada;
  final bool canEdit;
  final Future<void> Function(bool rechazada, String? motivo) onRechazar;

  const _RechazadoSection({
    required this.isRechazada,
    required this.canEdit,
    required this.onRechazar,
  });

  @override
  State<_RechazadoSection> createState() => _RechazadoSectionState();
}

class _RechazadoSectionState extends State<_RechazadoSection> {
  late bool _isRechazada;

  @override
  void initState() {
    super.initState();
    _isRechazada = widget.isRechazada;
  }

  @override
  void didUpdateWidget(_RechazadoSection old) {
    super.didUpdateWidget(old);
    if (old.isRechazada != widget.isRechazada) {
      _isRechazada = widget.isRechazada;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _isRechazada
              ? const Color(0xFFFEF2F2)
              : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isRechazada
                ? const Color(0xFFDC2626).withValues(alpha: 0.4)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                _isRechazada
                    ? CupertinoIcons.xmark_circle_fill
                    : CupertinoIcons.xmark_circle,
                size: 18,
                color: _isRechazada ? const Color(0xFFDC2626) : _muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rechazado',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _isRechazada ? const Color(0xFFDC2626) : _ink,
                      ),
                    ),
                    Text(
                      _isRechazada
                          ? 'El pliego ha sido rechazado'
                          : 'Marcar el pliego completo como rechazado',
                      style: TextStyle(
                        fontSize: 11,
                        color: _isRechazada
                            ? const Color(0xFFDC2626).withValues(alpha: 0.8)
                            : _muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.canEdit)
                CupertinoSwitch(
                  value: _isRechazada,
                  activeTrackColor: const Color(0xFFDC2626),
                  onChanged: (v) {
                    if (v) {
                      _showRejectionDialog(context);
                    } else {
                      setState(() => _isRechazada = false);
                      widget.onRechazar(false, null);
                    }
                  },
                )
              else if (_isRechazada)
                const Text(
                  'Sí',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRejectionDialog(BuildContext context) async {
    final textCtrl = TextEditingController();
    int selectedOption = 0;
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => CupertinoAlertDialog(
          title: const Text('Motivo de rechazo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setDialogState(() => selectedOption = 1),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selectedOption == 1 ? const Color(0xFFEFF6FF) : null,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: selectedOption == 1
                          ? _blue
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ingram no trabaja con este fabricante',
                          style: TextStyle(fontSize: 13, color: _ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setDialogState(() => selectedOption = 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selectedOption == 2 ? const Color(0xFFEFF6FF) : null,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: selectedOption == 2
                          ? _blue
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Otro motivo',
                          style: TextStyle(fontSize: 13, color: _ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (selectedOption == 2) ...[
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: textCtrl,
                  placeholder: 'Escribe el motivo...',
                  style: const TextStyle(fontSize: 13),
                  maxLines: 2,
                ),
              ],
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                if (selectedOption == 1) {
                  Navigator.pop(
                    ctx,
                    'RECHAZADO - Ingram no trabaja con este fabricante',
                  );
                } else if (selectedOption == 2) {
                  final val = textCtrl.text.trim();
                  Navigator.pop(
                    ctx,
                    val.isEmpty ? 'RECHAZADO - Otro' : 'RECHAZADO - Otro: $val',
                  );
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() => _isRechazada = true);
      await widget.onRechazar(true, result);
    }
  }
}
