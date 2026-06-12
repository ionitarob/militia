String _sub10(String s) => s.length >= 10 ? s.substring(0, 10) : s;

// ── Licitacion filter ─────────────────────────────────────────────────────────

class LicitacionFilter {
  final String? deadlineRange;
  final String? importeRange;
  final String? cat1;
  final String? cat2;
  final String? cat3;
  final String? comunidad;
  final String? mercado;
  final String? tipoProcedimiento;
  final String? duracionRange;
  final String? ingramEstado;
  final String? competencia;
  final String? pipelineStage;
  final String? reciente;
  final String? division;
  final String? asignada;
  final String label;

  const LicitacionFilter({
    this.deadlineRange,
    this.importeRange,
    this.cat1,
    this.cat2,
    this.cat3,
    this.comunidad,
    this.mercado,
    this.tipoProcedimiento,
    this.duracionRange,
    this.ingramEstado,
    this.competencia,
    this.pipelineStage,
    this.reciente,
    this.division,
    this.asignada,
    required this.label,
  });

  Map<String, String> toQueryParams() => {
    'deadline_range':           ?deadlineRange,
    'importe_range':            ?importeRange,
    'cat1':                     ?cat1,
    'cat2':                     ?cat2,
    'cat3':                     ?cat3,
    'comunidad':                ?comunidad,
    'mercado':                  ?mercado,
    'tipo_procedimiento':       ?tipoProcedimiento,
    'duracion_range':           ?duracionRange,
    'ingram_estado':            ?ingramEstado,
    'competencia':              ?competencia,
    'pipeline_stage':           ?pipelineStage,
    'reciente':                 ?reciente,
    'cotizacion_solicitada_a':  ?division,
    'asignada':                 ?asignada,
  };
}

// ── Licitacion ────────────────────────────────────────────────────────────────

class Licitacion {
  final int id;
  final String fecha;
  final String titulo;
  final String numeroExpediente;
  final double? importeLicitacion;
  final double? valorEstimado;
  final String? estado;
  final String pipelineStage;
  final String? tipoProcedimiento;
  final String? tipoTramitacion;
  final String? comunidadAutonoma;
  final String? provincia;
  final String? mercadoVertical;
  final String? plazoOfertaEstado;
  final String? fechaLimiteOferta;
  final int? duracionMeses;
  final int? prorrogasMeses;
  final int? puntosPrecio;
  final int? puntosMejoras;
  final int? puntosSubjetivos;
  final String? cpvLabel;
  final int? assigneeId;
  final String? assigneeNombre;
  final String? ingramEstado;
  final String? ingramOwner;
  final String? cotizacionSolicitadaA;
  final String? organismoNombre;

  const Licitacion({
    required this.id,
    required this.fecha,
    required this.titulo,
    required this.numeroExpediente,
    this.importeLicitacion,
    this.valorEstimado,
    this.estado,
    this.pipelineStage = 'nueva',
    this.tipoProcedimiento,
    this.tipoTramitacion,
    this.comunidadAutonoma,
    this.provincia,
    this.mercadoVertical,
    this.plazoOfertaEstado,
    this.fechaLimiteOferta,
    this.duracionMeses,
    this.prorrogasMeses,
    this.puntosPrecio,
    this.puntosMejoras,
    this.puntosSubjetivos,
    this.cpvLabel,
    this.assigneeId,
    this.assigneeNombre,
    this.ingramEstado,
    this.ingramOwner,
    this.cotizacionSolicitadaA,
    this.organismoNombre,
  });

  factory Licitacion.fromJson(Map<String, dynamic> j) => Licitacion(
        id: j['id'] as int,
        fecha: _sub10(j['fecha'] as String? ?? ''),
        titulo: j['titulo'] as String? ?? '',
        numeroExpediente: j['numero_expediente'] as String? ?? '',
        importeLicitacion: (j['importe_licitacion'] as num?)?.toDouble(),
        valorEstimado: (j['valor_estimado'] as num?)?.toDouble(),
        estado: j['estado'] as String?,
        pipelineStage: j['pipeline_stage'] as String? ?? 'nueva',
        tipoProcedimiento: j['tipo_procedimiento'] as String?,
        tipoTramitacion: j['tipo_tramitacion'] as String?,
        comunidadAutonoma: j['comunidad_autonoma'] as String?,
        provincia: j['provincia'] as String?,
        mercadoVertical: j['mercado_vertical'] as String?,
        plazoOfertaEstado: j['plazo_oferta_estado'] as String?,
        fechaLimiteOferta: j['fecha_limite_oferta'] == null
            ? null
            : _sub10(j['fecha_limite_oferta'] as String),
        duracionMeses: j['duracion_meses'] as int?,
        prorrogasMeses: j['prorrogas_meses'] as int?,
        puntosPrecio: j['puntos_precio'] as int?,
        puntosMejoras: j['puntos_mejoras'] as int?,
        puntosSubjetivos: j['puntos_subjetivos'] as int?,
        cpvLabel: j['cpv_label'] as String?,
        assigneeId: j['assignee_id'] as int?,
        assigneeNombre: j['assignee_nombre'] as String?,
        ingramEstado: j['ingram_estado'] as String?,
        ingramOwner: j['ingram_owner'] as String?,
        cotizacionSolicitadaA: j['cotizacion_solicitada_a'] as String?,
        organismoNombre: j['organismo_nombre'] as String?,
      );

  Licitacion copyWith({
    String? pipelineStage,
    int? Function()? assigneeId,
    String? Function()? assigneeNombre,
    String? Function()? ingramEstado,
    String? Function()? ingramOwner,
    String? Function()? cotizacionSolicitadaA,
  }) => Licitacion(
        id: id,
        fecha: fecha,
        titulo: titulo,
        numeroExpediente: numeroExpediente,
        importeLicitacion: importeLicitacion,
        valorEstimado: valorEstimado,
        estado: estado,
        pipelineStage: pipelineStage ?? this.pipelineStage,
        tipoProcedimiento: tipoProcedimiento,
        tipoTramitacion: tipoTramitacion,
        comunidadAutonoma: comunidadAutonoma,
        provincia: provincia,
        mercadoVertical: mercadoVertical,
        plazoOfertaEstado: plazoOfertaEstado,
        fechaLimiteOferta: fechaLimiteOferta,
        duracionMeses: duracionMeses,
        prorrogasMeses: prorrogasMeses,
        puntosPrecio: puntosPrecio,
        puntosMejoras: puntosMejoras,
        puntosSubjetivos: puntosSubjetivos,
        cpvLabel: cpvLabel,
        assigneeId: assigneeId != null ? assigneeId() : this.assigneeId,
        assigneeNombre: assigneeNombre != null ? assigneeNombre() : this.assigneeNombre,
        ingramEstado: ingramEstado != null ? ingramEstado() : this.ingramEstado,
        ingramOwner: ingramOwner != null ? ingramOwner() : this.ingramOwner,
        cotizacionSolicitadaA: cotizacionSolicitadaA != null
            ? cotizacionSolicitadaA()
            : this.cotizacionSolicitadaA,
        organismoNombre: organismoNombre,
      );
}

class LicitacionPage {
  final List<Licitacion> data;
  final int total;
  final int page;
  final int perPage;

  const LicitacionPage({
    required this.data,
    required this.total,
    required this.page,
    required this.perPage,
  });

  factory LicitacionPage.fromJson(Map<String, dynamic> j) => LicitacionPage(
        data: (j['data'] as List)
            .map((e) => Licitacion.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: j['total'] as int,
        page: j['page'] as int,
        perPage: j['per_page'] as int,
      );
}

// ── ClienteCotizacion ─────────────────────────────────────────────────────────

class ClienteCotizacion {
  final String clienteNombre;
  final String? cotizacionXv;
  final String? oportunidad;

  const ClienteCotizacion({
    required this.clienteNombre,
    this.cotizacionXv,
    this.oportunidad,
  });

  factory ClienteCotizacion.fromJson(Map<String, dynamic> j) => ClienteCotizacion(
        clienteNombre: j['cliente_nombre'] as String,
        cotizacionXv:  j['cotizacion_xv'] as String?,
        oportunidad:   j['oportunidad'] as String?,
      );

  ClienteCotizacion copyWith({String? cotizacionXv, String? oportunidad}) =>
      ClienteCotizacion(
        clienteNombre: clienteNombre,
        cotizacionXv: cotizacionXv ?? this.cotizacionXv,
        oportunidad: oportunidad ?? this.oportunidad,
      );
}

// ── AppUser ───────────────────────────────────────────────────────────────────

class AppUser {
  final int id;
  final String email;
  final String role;
  final String? nombre;

  const AppUser({
    required this.id,
    required this.email,
    required this.role,
    this.nombre,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id:     j['id'] as int,
        email:  j['email'] as String,
        role:   j['role'] as String? ?? 'ventas',
        nombre: j['nombre'] as String?,
      );

  String get displayName => nombre ?? email.split('@').first;
}

// ── Team ──────────────────────────────────────────────────────────────────────

class TeamMember {
  final int userId;
  final String email;
  final String role;
  final String? nombre;

  const TeamMember({
    required this.userId,
    required this.email,
    required this.role,
    this.nombre,
  });

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        userId: j['user_id'] as int,
        email:  j['email'] as String,
        role:   j['role'] as String? ?? 'ventas',
        nombre: j['nombre'] as String?,
      );

  String get displayName => nombre ?? email.split('@').first;
}

class Team {
  final int id;
  final String nombre;
  final int createdBy;
  final List<TeamMember> members;

  const Team({
    required this.id,
    required this.nombre,
    required this.createdBy,
    required this.members,
  });

  factory Team.fromJson(Map<String, dynamic> j) => Team(
        id:        j['id'] as int,
        nombre:    j['nombre'] as String,
        createdBy: j['created_by'] as int,
        members:   (j['members'] as List? ?? [])
            .map((e) => TeamMember.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Quote ─────────────────────────────────────────────────────────────────────

class Quote {
  final int id;
  final int licitacionId;
  final int vendedorId;
  final String? vendedorNombre;
  final String resellerName;
  final String? dateSent;
  final double? amount;
  final String status;
  final String? notes;
  final String createdAt;

  const Quote({
    required this.id,
    required this.licitacionId,
    required this.vendedorId,
    this.vendedorNombre,
    required this.resellerName,
    this.dateSent,
    this.amount,
    required this.status,
    this.notes,
    required this.createdAt,
  });

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
        id:              j['id'] as int,
        licitacionId:    j['licitacion_id'] as int,
        vendedorId:      j['vendedor_id'] as int,
        vendedorNombre:  j['vendedor_nombre'] as String?,
        resellerName:    j['reseller_name'] as String,
        dateSent:        j['date_sent'] as String?,
        amount:          (j['amount'] as num?)?.toDouble(),
        status:          j['status'] as String? ?? 'pendiente',
        notes:           j['notes'] as String?,
        createdAt:       j['created_at'] as String,
      );
}

// ── Note ──────────────────────────────────────────────────────────────────────

class LicitacionNote {
  final int id;
  final int userId;
  final String? userNombre;
  final String content;
  final String createdAt;

  const LicitacionNote({
    required this.id,
    required this.userId,
    this.userNombre,
    required this.content,
    required this.createdAt,
  });

  factory LicitacionNote.fromJson(Map<String, dynamic> j) => LicitacionNote(
        id:          j['id'] as int,
        userId:      j['user_id'] as int,
        userNombre:  j['user_nombre'] as String?,
        content:     j['content'] as String,
        createdAt:   j['created_at'] as String,
      );
}

// ── Dashboard stats ───────────────────────────────────────────────────────────

class TeamActivity {
  final int userId;
  final String? nombre;
  final String email;
  final int assignedCount;
  final String? latestTitulo;

  const TeamActivity({
    required this.userId,
    this.nombre,
    required this.email,
    required this.assignedCount,
    this.latestTitulo,
  });

  factory TeamActivity.fromJson(Map<String, dynamic> j) => TeamActivity(
        userId:         j['user_id'] as int,
        nombre:         j['nombre'] as String?,
        email:          j['email'] as String,
        assignedCount:  j['assigned_count'] as int? ?? 0,
        latestTitulo:   j['latest_titulo'] as String?,
      );

  String get displayName => nombre ?? email.split('@').first;
}

class PendingDecline {
  final int id;
  final int licitacionId;
  final String titulo;
  final String? userNombre;
  final String? reason;
  final String createdAt;

  const PendingDecline({
    required this.id,
    required this.licitacionId,
    required this.titulo,
    this.userNombre,
    this.reason,
    required this.createdAt,
  });

  factory PendingDecline.fromJson(Map<String, dynamic> j) => PendingDecline(
        id:            j['id'] as int,
        licitacionId:  j['licitacion_id'] as int,
        titulo:        j['titulo'] as String,
        userNombre:    j['user_nombre'] as String?,
        reason:        j['reason'] as String?,
        createdAt:     j['created_at'] as String,
      );
}

class BreakdownItem {
  final String label;
  final String value;
  final int count;

  const BreakdownItem({required this.label, required this.value, required this.count});

  factory BreakdownItem.fromJson(Map<String, dynamic> j) => BreakdownItem(
        label: j['label'] as String,
        value: j['value'] as String? ?? '',
        count: j['count'] as int? ?? 0,
      );
}

class DashboardBreakdown {
  final List<BreakdownItem> plazo;
  final List<BreakdownItem> importe;
  final List<BreakdownItem> ingramEstado;
  final List<BreakdownItem> pipelineStage;
  final List<BreakdownItem> comunidad;
  final List<BreakdownItem> mercado;
  final List<BreakdownItem> cat1;
  final List<BreakdownItem> cat2;
  final List<BreakdownItem> cat3;
  final List<BreakdownItem> tipoProcedimiento;
  final List<BreakdownItem> duracion;

  const DashboardBreakdown({
    required this.plazo,
    required this.importe,
    required this.ingramEstado,
    required this.pipelineStage,
    required this.comunidad,
    required this.mercado,
    required this.cat1,
    required this.cat2,
    required this.cat3,
    required this.tipoProcedimiento,
    required this.duracion,
  });

  factory DashboardBreakdown.fromJson(Map<String, dynamic> j) {
    List<BreakdownItem> parse(String key) =>
        ((j[key] as List?) ?? []).map((e) => BreakdownItem.fromJson(e as Map<String, dynamic>)).toList();
    return DashboardBreakdown(
      plazo:             parse('plazo'),
      importe:           parse('importe'),
      ingramEstado:      parse('ingram_estado'),
      pipelineStage:     parse('pipeline_stage'),
      comunidad:         parse('comunidad'),
      mercado:           parse('mercado'),
      cat1:              parse('cat1'),
      cat2:              parse('cat2'),
      cat3:              parse('cat3'),
      tipoProcedimiento: parse('tipo_procedimiento'),
      duracion:          parse('duracion'),
    );
  }

  static DashboardBreakdown empty() => const DashboardBreakdown(
    plazo: [], importe: [], ingramEstado: [], pipelineStage: [], comunidad: [], mercado: [],
    cat1: [], cat2: [], cat3: [], tipoProcedimiento: [], duracion: [],
  );
}

class DashboardStats {
  final int activas;
  final int sinAsignar;
  final int declivesPendientes;
  final int nuevasRecientes;
  final List<TeamActivity> teamActivity;
  final List<PendingDecline> pendingDeclines;
  final DashboardBreakdown breakdown;

  const DashboardStats({
    required this.activas,
    required this.sinAsignar,
    required this.declivesPendientes,
    required this.nuevasRecientes,
    required this.teamActivity,
    required this.pendingDeclines,
    required this.breakdown,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> j) => DashboardStats(
        activas:            j['activas'] as int? ?? 0,
        sinAsignar:         j['sin_asignar'] as int? ?? 0,
        declivesPendientes: j['declives_pendientes'] as int? ?? 0,
        nuevasRecientes:    j['nuevas_recientes'] as int? ?? 0,
        teamActivity:        (j['team_activity'] as List? ?? [])
            .map((e) => TeamActivity.fromJson(e as Map<String, dynamic>))
            .toList(),
        pendingDeclines:     (j['pending_declines'] as List? ?? [])
            .map((e) => PendingDecline.fromJson(e as Map<String, dynamic>))
            .toList(),
        breakdown: j['breakdown'] != null
            ? DashboardBreakdown.fromJson(j['breakdown'] as Map<String, dynamic>)
            : DashboardBreakdown.empty(),
      );
}

// ── Licitacion documento ─────────────────────────────────────────────────────

class CotizacionAdjunto {
  final int id;
  final String nombre;
  final String url;
  final String? contentType;
  final int? sizeBytes;

  const CotizacionAdjunto({
    required this.id,
    required this.nombre,
    required this.url,
    this.contentType,
    this.sizeBytes,
  });

  factory CotizacionAdjunto.fromJson(Map<String, dynamic> j) =>
      CotizacionAdjunto(
        id:          j['id'] as int,
        nombre:      j['nombre'] as String,
        url:         j['url'] as String,
        contentType: j['content_type'] as String?,
        sizeBytes:   j['size_bytes'] as int?,
      );
}

class LicitacionDocumento {
  final int id;
  final String nombre;
  final String url;
  final String? contentType;
  final int? sizeBytes;

  const LicitacionDocumento({
    required this.id,
    required this.nombre,
    required this.url,
    this.contentType,
    this.sizeBytes,
  });

  factory LicitacionDocumento.fromJson(Map<String, dynamic> j) =>
      LicitacionDocumento(
        id:          j['id'] as int,
        nombre:      j['nombre'] as String,
        url:         j['url'] as String,
        contentType: j['content_type'] as String?,
        sizeBytes:   j['size_bytes'] as int?,
      );
}

// ── Team workload ─────────────────────────────────────────────────────────────

class WorkloadLic {
  final int id;
  final String titulo;
  final double? importe;
  final String pipelineStage;
  final String? ingramEstado;
  final String? fechaLimiteOferta;

  const WorkloadLic({
    required this.id,
    required this.titulo,
    this.importe,
    required this.pipelineStage,
    this.ingramEstado,
    this.fechaLimiteOferta,
  });

  factory WorkloadLic.fromJson(Map<String, dynamic> j) => WorkloadLic(
        id:                 (j['id'] as num).toInt(),
        titulo:             j['titulo'] as String,
        importe:            (j['importe'] as num?)?.toDouble(),
        pipelineStage:      j['pipeline_stage'] as String? ?? 'nueva',
        ingramEstado:       j['ingram_estado'] as String?,
        fechaLimiteOferta:  j['fecha_limite_oferta'] as String?,
      );
}

class WorkloadUser {
  final int userId;
  final String? nombre;
  final String email;
  final List<WorkloadLic> licitaciones;

  const WorkloadUser({
    required this.userId,
    this.nombre,
    required this.email,
    required this.licitaciones,
  });

  String get displayName => nombre ?? email.split('@').first;

  factory WorkloadUser.fromJson(Map<String, dynamic> j) => WorkloadUser(
        userId:       j['user_id'] as int,
        nombre:       j['nombre'] as String?,
        email:        j['email'] as String,
        licitaciones: (j['licitaciones'] as List)
            .map((e) => WorkloadLic.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
