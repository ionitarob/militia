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
  final String? assigneeUserIds;
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
    this.assigneeUserIds,
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
    if (assigneeUserIds != null) 'assignee_user_ids': assigneeUserIds!,
  };
}

// ── Adjudicacion ──────────────────────────────────────────────────────────────

class Adjudicacion {
  final int id;
  final String? externalId;
  final String titulo;
  final String numeroExpediente;
  final String? fechaAdjudicacion;
  final String? fechaVencimientoContrato;
  final double? importe;
  final double? importeAdjudicado;
  final double? valorEstimado;
  final double? ratio;
  final String? comunidadAutonoma;
  final String? provincia;
  final String? ambitoGeografico;
  final String? mercadoVertical;
  final String? tipoProcedimiento;
  final String? tipoTramitacion;
  final int? duracionMeses;
  final int? prorrogasMeses;
  final int? puntosPrecio;
  final int? puntosMejoras;
  final int? puntosSubjetivos;
  final String? organismoNombre;
  final String? adjudicatarioNombre;
  final int? licitacionId;
  final String? cpvLabel;
  final List<ClienteCotizacion> cotizaciones;
  final String createdAt;

  const Adjudicacion({
    required this.id,
    this.externalId,
    required this.titulo,
    required this.numeroExpediente,
    this.fechaAdjudicacion,
    this.fechaVencimientoContrato,
    this.importe,
    this.importeAdjudicado,
    this.valorEstimado,
    this.ratio,
    this.comunidadAutonoma,
    this.provincia,
    this.ambitoGeografico,
    this.mercadoVertical,
    this.tipoProcedimiento,
    this.tipoTramitacion,
    this.duracionMeses,
    this.prorrogasMeses,
    this.puntosPrecio,
    this.puntosMejoras,
    this.puntosSubjetivos,
    this.organismoNombre,
    this.adjudicatarioNombre,
    this.licitacionId,
    this.cpvLabel,
    this.cotizaciones = const [],
    required this.createdAt,
  });

  factory Adjudicacion.fromJson(Map<String, dynamic> j) => Adjudicacion(
    id:                        j['id'] as int,
    externalId:                j['external_id'] as String?,
    titulo:                    j['titulo'] as String? ?? '',
    numeroExpediente:          j['numero_expediente'] as String? ?? '',
    fechaAdjudicacion:         j['fecha_adjudicacion'] as String?,
    fechaVencimientoContrato:  j['fecha_vencimiento_contrato'] as String?,
    importe:                   (j['importe'] as num?)?.toDouble(),
    importeAdjudicado:         (j['importe_adjudicado'] as num?)?.toDouble(),
    valorEstimado:             (j['valor_estimado'] as num?)?.toDouble(),
    ratio:                     (j['ratio_adjudicacion_vs_licitacion'] as num?)?.toDouble(),
    comunidadAutonoma:         j['comunidad_autonoma'] as String?,
    provincia:                 j['provincia'] as String?,
    ambitoGeografico:          j['ambito_geografico'] as String?,
    mercadoVertical:           j['mercado_vertical'] as String?,
    tipoProcedimiento:         j['tipo_procedimiento'] as String?,
    tipoTramitacion:           j['tipo_tramitacion'] as String?,
    duracionMeses:             j['duracion_meses'] as int?,
    prorrogasMeses:            j['prorrogas_meses'] as int?,
    puntosPrecio:              j['puntos_precio'] as int?,
    puntosMejoras:             j['puntos_mejoras'] as int?,
    puntosSubjetivos:          j['puntos_subjetivos'] as int?,
    organismoNombre:           j['organismo_nombre'] as String?,
    adjudicatarioNombre:       j['adjudicatario_nombre'] as String?,
    licitacionId:              j['licitacion_id'] as int?,
    cpvLabel:                  j['cpv_label'] as String?,
    cotizaciones:              (j['cotizaciones'] as List<dynamic>?)
                                   ?.map((e) => ClienteCotizacion.fromJson(e as Map<String, dynamic>))
                                   .toList() ?? [],
    createdAt:                 j['created_at'] as String? ?? '',
  );
}

// ── Alerta ────────────────────────────────────────────────────────────────────

class Alerta {
  final int id;
  final int adjudicacionId;
  final int? licitacionId;
  final String mensaje;
  final bool leida;
  final String createdAt;
  final String adjTitulo;

  const Alerta({
    required this.id,
    required this.adjudicacionId,
    this.licitacionId,
    required this.mensaje,
    required this.leida,
    required this.createdAt,
    required this.adjTitulo,
  });

  factory Alerta.fromJson(Map<String, dynamic> j) => Alerta(
    id:             j['id'] as int,
    adjudicacionId: j['adjudicacion_id'] as int,
    licitacionId:   j['licitacion_id'] as int?,
    mensaje:        j['mensaje'] as String,
    leida:          j['leida'] as bool,
    createdAt:      j['created_at'] as String,
    adjTitulo:      j['adj_titulo'] as String? ?? '',
  );
}

class AdjudicacionResumen {
  final int id;
  final String? fechaAdjudicacion;
  final double? importeAdjudicado;
  final double? importe;
  final double? ratio;
  final String? tipoProcedimiento;
  final String? adjudicatarioNombre;
  final String? organismoNombre;

  const AdjudicacionResumen({
    required this.id,
    this.fechaAdjudicacion,
    this.importeAdjudicado,
    this.importe,
    this.ratio,
    this.tipoProcedimiento,
    this.adjudicatarioNombre,
    this.organismoNombre,
  });

  factory AdjudicacionResumen.fromJson(Map<String, dynamic> j) => AdjudicacionResumen(
    id:                  j['id'] as int,
    fechaAdjudicacion:   j['fecha_adjudicacion'] as String?,
    importeAdjudicado:   (j['importe_adjudicado'] as num?)?.toDouble(),
    importe:             (j['importe'] as num?)?.toDouble(),
    ratio:               (j['ratio'] as num?)?.toDouble(),
    tipoProcedimiento:   j['tipo_procedimiento'] as String?,
    adjudicatarioNombre: j['adjudicatario_nombre'] as String?,
    organismoNombre:     j['organismo_nombre'] as String?,
  );
}

class AdjudicacionPage {
  final List<Adjudicacion> data;
  final int total;
  final int page;
  final int perPage;

  const AdjudicacionPage({required this.data, required this.total, required this.page, required this.perPage});

  factory AdjudicacionPage.fromJson(Map<String, dynamic> j) => AdjudicacionPage(
    data:    (j['data'] as List).map((e) => Adjudicacion.fromJson(e as Map<String, dynamic>)).toList(),
    total:   j['total'] as int? ?? 0,
    page:    j['page'] as int? ?? 1,
    perPage: j['per_page'] as int? ?? 25,
  );
}

// ── Licitacion ────────────────────────────────────────────────────────────────

class LicitacionAssignee {
  final int id;
  final String? nombre;

  const LicitacionAssignee({required this.id, this.nombre});

  factory LicitacionAssignee.fromJson(Map<String, dynamic> j) =>
      LicitacionAssignee(id: j['id'] as int, nombre: j['nombre'] as String?);

  String get displayName => nombre ?? 'Usuario $id';
}

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
  final List<LicitacionAssignee> assignees;
  final String? ingramEstado;
  final String? ingramOwner;
  final String? cotizacionSolicitadaA;
  final bool fabricanteProteccion;
  final String? fabricanteNombre;
  final String? motivoPerdida;
  final String? motivoPerdidaTexto;
  final String? organismoNombre;
  final String? cat1;
  final String? cat2;
  final String? cat3;

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
    this.assignees = const [],
    this.ingramEstado,
    this.ingramOwner,
    this.cotizacionSolicitadaA,
    this.fabricanteProteccion = false,
    this.fabricanteNombre,
    this.motivoPerdida,
    this.motivoPerdidaTexto,
    this.organismoNombre,
    this.cat1,
    this.cat2,
    this.cat3,
  });

  // Convenience: first assignee's name (for list display)
  String? get assigneeNombre =>
      assignees.isEmpty ? null : assignees.first.displayName;
  int? get assigneeId => assignees.isEmpty ? null : assignees.first.id;

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
        assignees: (j['assignees'] as List? ?? [])
            .map((e) => LicitacionAssignee.fromJson(e as Map<String, dynamic>))
            .toList(),
        ingramEstado: j['ingram_estado'] as String?,
        ingramOwner: j['ingram_owner'] as String?,
        cotizacionSolicitadaA: j['cotizacion_solicitada_a'] as String?,
        fabricanteProteccion: j['fabricante_proteccion'] as bool? ?? false,
        fabricanteNombre: j['fabricante_nombre'] as String?,
        motivoPerdida: j['motivo_perdida'] as String?,
        motivoPerdidaTexto: j['motivo_perdida_texto'] as String?,
        organismoNombre: j['organismo_nombre'] as String?,
        cat1: j['cat1'] as String?,
        cat2: j['cat2'] as String?,
        cat3: j['cat3'] as String?,
      );

  Licitacion copyWith({
    String? pipelineStage,
    List<LicitacionAssignee>? assignees,
    String? Function()? ingramEstado,
    String? Function()? ingramOwner,
    String? Function()? cotizacionSolicitadaA,
    bool? fabricanteProteccion,
    String? Function()? fabricanteNombre,
    String? Function()? motivoPerdida,
    String? Function()? motivoPerdidaTexto,
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
        assignees: assignees ?? this.assignees,
        ingramEstado: ingramEstado != null ? ingramEstado() : this.ingramEstado,
        ingramOwner: ingramOwner != null ? ingramOwner() : this.ingramOwner,
        cotizacionSolicitadaA: cotizacionSolicitadaA != null
            ? cotizacionSolicitadaA()
            : this.cotizacionSolicitadaA,
        fabricanteProteccion: fabricanteProteccion ?? this.fabricanteProteccion,
        fabricanteNombre: fabricanteNombre != null ? fabricanteNombre() : this.fabricanteNombre,
        motivoPerdida: motivoPerdida != null ? motivoPerdida() : this.motivoPerdida,
        motivoPerdidaTexto: motivoPerdidaTexto != null ? motivoPerdidaTexto() : this.motivoPerdidaTexto,
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
  final String? cotizacionId;
  final String? oportunidadId;
  final String? estado;
  final List<String> divisiones;
  final bool fabricanteProteccion;
  final String? fabricanteNombre;
  final bool sePresenta;
  final int? userId;
  final bool? vaConPliego;

  const ClienteCotizacion({
    required this.clienteNombre,
    this.cotizacionXv,
    this.oportunidad,
    this.cotizacionId,
    this.oportunidadId,
    this.estado,
    this.divisiones = const [],
    this.fabricanteProteccion = false,
    this.fabricanteNombre,
    this.sePresenta = false,
    this.userId,
    this.vaConPliego,
  });

  factory ClienteCotizacion.fromJson(Map<String, dynamic> j) => ClienteCotizacion(
        clienteNombre:        j['cliente_nombre'] as String,
        cotizacionXv:         j['cotizacion_xv'] as String?,
        oportunidad:          j['oportunidad'] as String?,
        cotizacionId:         j['cotizacion_id'] as String?,
        oportunidadId:        j['oportunidad_id'] as String?,
        estado:               j['estado'] as String?,
        divisiones:           (j['divisiones'] as List<dynamic>?)
                                  ?.map((e) => e as String).toList() ?? [],
        fabricanteProteccion: j['fabricante_proteccion'] as bool? ?? false,
        fabricanteNombre:     j['fabricante_nombre'] as String?,
        sePresenta:           j['se_presenta'] as bool? ?? false,
        userId:               j['user_id'] as int?,
        vaConPliego:          j['va_con_pliego'] as bool?,
      );

  ClienteCotizacion copyWith({
    String? cotizacionXv,
    String? oportunidad,
    String? cotizacionId,
    String? oportunidadId,
    String? estado,
    List<String>? divisiones,
    bool? fabricanteProteccion,
    String? fabricanteNombre,
    bool? sePresenta,
    int? userId,
    bool? Function()? vaConPliego,
  }) => ClienteCotizacion(
        clienteNombre:        clienteNombre,
        cotizacionXv:         cotizacionXv ?? this.cotizacionXv,
        oportunidad:          oportunidad ?? this.oportunidad,
        cotizacionId:         cotizacionId ?? this.cotizacionId,
        oportunidadId:        oportunidadId ?? this.oportunidadId,
        estado:               estado ?? this.estado,
        divisiones:           divisiones ?? this.divisiones,
        fabricanteProteccion: fabricanteProteccion ?? this.fabricanteProteccion,
        fabricanteNombre:     fabricanteNombre ?? this.fabricanteNombre,
        sePresenta:           sePresenta ?? this.sePresenta,
        userId:               userId ?? this.userId,
        vaConPliego:          vaConPliego != null ? vaConPliego() : this.vaConPliego,
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
  final int total;
  final int activas;
  final int activasAsignadas;
  final int activasSinAsignar;
  final int inactivas;
  final int inactivasAdjudicadas;
  final int inactivasNoAdjudicadas;
  final int caducadas;
  final int adjudicacionesTotal;
  final int adjudicacionesRecientes;
  final int sinAsignar;
  final int declivesPendientes;
  final int nuevasRecientes;
  final List<TeamActivity> teamActivity;
  final List<PendingDecline> pendingDeclines;
  final DashboardBreakdown breakdown;

  const DashboardStats({
    required this.total,
    required this.activas,
    required this.activasAsignadas,
    required this.activasSinAsignar,
    required this.inactivas,
    required this.inactivasAdjudicadas,
    required this.inactivasNoAdjudicadas,
    required this.caducadas,
    required this.adjudicacionesTotal,
    required this.adjudicacionesRecientes,
    required this.sinAsignar,
    required this.declivesPendientes,
    required this.nuevasRecientes,
    required this.teamActivity,
    required this.pendingDeclines,
    required this.breakdown,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> j) => DashboardStats(
        total:                    j['total'] as int? ?? 0,
        activas:                  j['activas'] as int? ?? 0,
        activasAsignadas:         j['activas_asignadas'] as int? ?? 0,
        activasSinAsignar:        j['activas_sin_asignar'] as int? ?? 0,
        inactivas:                j['inactivas'] as int? ?? 0,
        inactivasAdjudicadas:     j['inactivas_adjudicadas'] as int? ?? 0,
        inactivasNoAdjudicadas:   j['inactivas_no_adjudicadas'] as int? ?? 0,
        caducadas:                j['caducadas'] as int? ?? 0,
        adjudicacionesTotal:      j['adjudicaciones_total'] as int? ?? 0,
        adjudicacionesRecientes:  j['adjudicaciones_recientes'] as int? ?? 0,
        sinAsignar:               j['sin_asignar'] as int? ?? 0,
        declivesPendientes:       j['declives_pendientes'] as int? ?? 0,
        nuevasRecientes:          j['nuevas_recientes'] as int? ?? 0,
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
  final bool isManual;

  const LicitacionDocumento({
    required this.id,
    required this.nombre,
    required this.url,
    this.contentType,
    this.sizeBytes,
    this.isManual = false,
  });

  factory LicitacionDocumento.fromJson(Map<String, dynamic> j) =>
      LicitacionDocumento(
        id:          j['id'] as int,
        nombre:      j['nombre'] as String,
        url:         j['url'] as String,
        contentType: j['content_type'] as String?,
        sizeBytes:   j['size_bytes'] as int?,
        isManual:    j['is_manual'] as bool? ?? false,
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

class StageHistoryItem {
  final int id;
  final String stage;
  final String changedAt;
  final String? userNombre;
  final String? motivoPerdida;
  final String? motivoPerdidaTexto;

  const StageHistoryItem({
    required this.id,
    required this.stage,
    required this.changedAt,
    this.userNombre,
    this.motivoPerdida,
    this.motivoPerdidaTexto,
  });

  factory StageHistoryItem.fromJson(Map<String, dynamic> j) => StageHistoryItem(
        id: j['id'] as int,
        stage: j['stage'] as String,
        changedAt: j['changed_at'] as String,
        userNombre: j['user_nombre'] as String?,
        motivoPerdida: j['motivo_perdida'] as String?,
        motivoPerdidaTexto: j['motivo_perdida_texto'] as String?,
      );
}

// ── Chat ──────────────────────────────────────────────────────────────────────

enum ChatRole { user, assistant }

class ChatMessage {
  final ChatRole role;
  final String content;
  final DateTime timestamp;

  const ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });
}

class ChatResponse {
  final String sessionId;
  final String reply;

  const ChatResponse({required this.sessionId, required this.reply});

  factory ChatResponse.fromJson(Map<String, dynamic> j) => ChatResponse(
        sessionId: j['session_id'] as String,
        reply:     j['reply']      as String,
      );
}

class ChatSession {
  final String id;
  final String preview;
  final String updatedAt;
  final int messageCount;

  const ChatSession({
    required this.id,
    required this.preview,
    required this.updatedAt,
    required this.messageCount,
  });

  factory ChatSession.fromJson(Map<String, dynamic> j) => ChatSession(
        id:           j['id'] as String,
        preview:      j['preview'] as String,
        updatedAt:    j['updated_at'] as String,
        messageCount: (j['message_count'] as num).toInt(),
      );
}

class ChatSessionDetail {
  final String id;
  final List<ChatMessage> messages;

  const ChatSessionDetail({required this.id, required this.messages});

  factory ChatSessionDetail.fromJson(Map<String, dynamic> j) {
    final msgs = (j['messages'] as List).map((m) {
      final role = (m['role'] as String) == 'user' ? ChatRole.user : ChatRole.assistant;
      return ChatMessage(
        role: role,
        content: m['content'] as String,
        timestamp: DateTime.tryParse(m['created_at'] as String) ?? DateTime.now(),
      );
    }).toList();
    return ChatSessionDetail(id: j['id'] as String, messages: msgs);
  }
}

