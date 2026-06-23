import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import 'models.dart';

const _base = 'https://rm0vk0iw4f.execute-api.eu-west-3.amazonaws.com/prod';

const chatStreamBase = 'https://n52c2kqdmznr5vlqkgiiuufk6e0qjubr.lambda-url.eu-west-3.on.aws';

const summarizeBase = 'https://aqwv7iupruihcwhswkuzp45jsm0anhvi.lambda-url.eu-west-3.on.aws';

class ApiClient {
  static final ApiClient _instance = ApiClient._();
  factory ApiClient() => _instance;
  ApiClient._();

  final _http = http.Client();

  Future<Map<String, String>> _headers() async {
    final token = await AuthService().accessToken;
    return {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  // ── Licitaciones ────────────────────────────────────────────────────────────

  Future<LicitacionPage> getLicitaciones({
    int page = 1,
    int perPage = 25,
    LicitacionFilter? filter,
    String? orderBy,
  }) async {
    final uri = Uri.parse('$_base/licitaciones').replace(
      queryParameters: {
        'page': '$page',
        'per_page': '$perPage',
        if (orderBy != null) 'order_by': orderBy,
        ...?filter?.toQueryParams(),
      },
    );
    final res = await _http.get(uri, headers: await _headers());
    _check(res);
    return LicitacionPage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<AdjudicacionPage> getAdjudicaciones({
    int page = 1,
    int perPage = 25,
    String? recientes,
    String? mercado,
  }) async {
    final uri = Uri.parse('$_base/adjudicaciones').replace(queryParameters: {
      'page': '$page',
      'per_page': '$perPage',
      'recientes': ?recientes,
      'mercado':   ?mercado,
    });
    final res = await _http.get(uri, headers: await _headers());
    _check(res);
    return AdjudicacionPage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Adjudicacion> getAdjudicacion(int id) async {
    final res = await _http.get(
      Uri.parse('$_base/adjudicaciones/$id'),
      headers: await _headers(),
    );
    _check(res);
    return Adjudicacion.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<Licitacion>> getMyLicitaciones() async {
    final res = await _http.get(
      Uri.parse('$_base/licitaciones/mine'),
      headers: await _headers(),
    );
    _check(res);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return (j['data'] as List)
        .map((e) => Licitacion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Ingram workflow ──────────────────────────────────────────────────────────


  Future<void> unassignLicitacion(int licitacionId, int assigneeId) async {
    final res = await _http.post(
      Uri.parse('$_base/licitaciones/$licitacionId/unassign'),
      headers: await _headers(),
      body: jsonEncode({'assignee_id': assigneeId}),
    );
    _check(res);
  }

  // ── Client cotizaciones ──────────────────────────────────────────────────────

  Future<List<ClienteCotizacion>> getClienteCotizaciones(int licitacionId) async {
    final res = await _http.get(
      Uri.parse('$_base/licitaciones/$licitacionId/client-cotizaciones'),
      headers: await _headers(),
    );
    _check(res);
    return (jsonDecode(res.body) as List)
        .map((e) => ClienteCotizacion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> upsertClienteCotizacion(
    int licitacionId,
    String clienteNombre, {
    String? cotizacionXv,
    String? oportunidad,
    String? cotizacionId,
    String? oportunidadId,
    String? estado,
    List<String> divisiones = const [],
    bool fabricanteProteccion = false,
    String? fabricanteNombre,
    bool sePresenta = false,
    int? userId,
    bool? vaConPliego,
  }) async {
    final encoded = Uri.encodeComponent(clienteNombre);
    final res = await _http.put(
      Uri.parse('$_base/licitaciones/$licitacionId/client-cotizaciones/$encoded'),
      headers: await _headers(),
      body: jsonEncode({
        'cotizacion_xv': cotizacionXv,
        'oportunidad': oportunidad,
        'cotizacion_id': cotizacionId,
        'oportunidad_id': oportunidadId,
        'estado': estado,
        'divisiones': divisiones,
        'fabricante_proteccion': fabricanteProteccion,
        'fabricante_nombre': fabricanteNombre,
        'se_presenta': sePresenta,
        'user_id': userId,
        'va_con_pliego': vaConPliego,
      }),
    );
    _check(res);
  }

  Future<List<WorkloadUser>> getTeamWorkload() async {
    final res = await _http.get(
      Uri.parse('$_base/team/workload'),
      headers: await _headers(),
    );
    _check(res);
    return (jsonDecode(res.body) as List)
        .map((e) => WorkloadUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Dashboard ────────────────────────────────────────────────────────────────

  Future<DashboardStats> getDashboardStats() async {
    final res = await _http.get(
      Uri.parse('$_base/dashboard/stats'),
      headers: await _headers(),
    );
    _check(res);
    return DashboardStats.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ── Users ────────────────────────────────────────────────────────────────────

  Future<List<AppUser>> getUsers() async {
    final res = await _http.get(
      Uri.parse('$_base/users'),
      headers: await _headers(),
    );
    _check(res);
    return (jsonDecode(res.body) as List)
        .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Teams ────────────────────────────────────────────────────────────────────

  Future<List<Team>> getTeams() async {
    final res = await _http.get(
      Uri.parse('$_base/teams'),
      headers: await _headers(),
    );
    _check(res);
    return (jsonDecode(res.body) as List)
        .map((e) => Team.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> createTeam(String nombre) async {
    final res = await _http.post(
      Uri.parse('$_base/teams'),
      headers: await _headers(),
      body: jsonEncode({'nombre': nombre}),
    );
    _check(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as int;
  }

  Future<void> addTeamMember(int teamId, int userId) async {
    final res = await _http.post(
      Uri.parse('$_base/teams/$teamId/members'),
      headers: await _headers(),
      body: jsonEncode({'user_id': userId}),
    );
    _check(res);
  }

  Future<void> removeTeamMember(int teamId, int userId) async {
    final res = await _http.delete(
      Uri.parse('$_base/teams/$teamId/members/$userId'),
      headers: await _headers(),
    );
    _check(res);
  }

  // ── Pipeline ─────────────────────────────────────────────────────────────────

  Future<void> assignLicitacion(int licitacionId, int assigneeId) async {
    final res = await _http.post(
      Uri.parse('$_base/licitaciones/$licitacionId/assign'),
      headers: await _headers(),
      body: jsonEncode({'assignee_id': assigneeId}),
    );
    _check(res);
  }

  Future<void> declineLicitacion(int licitacionId, {String? reason}) async {
    final res = await _http.post(
      Uri.parse('$_base/licitaciones/$licitacionId/decline'),
      headers: await _headers(),
      body: jsonEncode({'reason': reason}),
    );
    _check(res);
  }

  Future<void> forceAssign(int licitacionId, int assigneeId) async {
    final res = await _http.post(
      Uri.parse('$_base/licitaciones/$licitacionId/force-assign'),
      headers: await _headers(),
      body: jsonEncode({'assignee_id': assigneeId}),
    );
    _check(res);
  }

  Future<void> updateStage(
    int licitacionId,
    String stage, {
    String? motivoPerdida,
    String? motivoPerdidaTexto,
  }) async {
    final res = await _http.patch(
      Uri.parse('$_base/licitaciones/$licitacionId/stage'),
      headers: await _headers(),
      body: jsonEncode({
        'stage': stage,
        'motivo_perdida': ?motivoPerdida,
        'motivo_perdida_texto': ?motivoPerdidaTexto,
      }),
    );
    _check(res);
  }

  // ── Quotes ───────────────────────────────────────────────────────────────────

  Future<List<Quote>> getQuotes(int licitacionId) async {
    final res = await _http.get(
      Uri.parse('$_base/licitaciones/$licitacionId/quotes'),
      headers: await _headers(),
    );
    _check(res);
    return (jsonDecode(res.body) as List)
        .map((e) => Quote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Quote> createQuote(
    int licitacionId, {
    required String resellerName,
    String? dateSent,
    double? amount,
    String status = 'pendiente',
    String? notes,
  }) async {
    final res = await _http.post(
      Uri.parse('$_base/licitaciones/$licitacionId/quotes'),
      headers: await _headers(),
      body: jsonEncode({
        'reseller_name': resellerName,
        if (dateSent != null) 'date_sent': dateSent,
        if (amount != null) 'amount': amount,
        'status': status,
        if (notes != null) 'notes': notes,
      }),
    );
    _check(res);
    final id = (jsonDecode(res.body) as Map<String, dynamic>)['id'] as int;
    final user = AuthService().currentUser;
    return Quote(
      id: id,
      licitacionId: licitacionId,
      vendedorId: user?.id ?? 0,
      vendedorNombre: user?.nombre,
      resellerName: resellerName,
      dateSent: dateSent,
      amount: amount,
      status: status,
      notes: notes,
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  Future<Quote> updateQuote(
    int licitacionId,
    Quote existing, {
    required String resellerName,
    String? dateSent,
    double? amount,
    required String status,
    String? notes,
  }) async {
    final res = await _http.patch(
      Uri.parse('$_base/licitaciones/$licitacionId/quotes/${existing.id}'),
      headers: await _headers(),
      body: jsonEncode({
        'reseller_name': resellerName,
        if (dateSent != null) 'date_sent': dateSent,
        if (amount != null) 'amount': amount,
        'status': status,
        if (notes != null) 'notes': notes,
      }),
    );
    _check(res);
    return Quote(
      id: existing.id,
      licitacionId: licitacionId,
      vendedorId: existing.vendedorId,
      vendedorNombre: existing.vendedorNombre,
      resellerName: resellerName,
      dateSent: dateSent,
      amount: amount,
      status: status,
      notes: notes,
      createdAt: existing.createdAt,
    );
  }

  Future<void> deleteQuote(int licitacionId, int quoteId) async {
    final res = await _http.delete(
      Uri.parse('$_base/licitaciones/$licitacionId/quotes/$quoteId'),
      headers: await _headers(),
    );
    _check(res);
  }

  // ── AI Summary ───────────────────────────────────────────────────────────────

  /// Streams Resumen Liti tokens from the dedicated Haiku summarize Lambda.
  /// Yields {"token":"..."} events then terminates (no session_id, no save needed
  /// — the Lambda auto-saves on completion).
  Stream<Map<String, dynamic>> summarizeStream(int licitacionId) async* {
    final uri = Uri.parse(summarizeBase);
    final headers = await _headers();
    final request = http.Request('POST', uri);
    request.headers.addAll(headers);
    request.body = jsonEncode({'licitacion_id': licitacionId});

    final streamed = await _http.send(request);
    if (streamed.statusCode >= 400) throw Exception('Error ${streamed.statusCode}');

    final pending = StringBuffer();
    await for (final chunk in streamed.stream.transform(Utf8Decoder(allowMalformed: true))) {
      pending.write(chunk);
      var buf = pending.toString();
      pending.clear();
      final parts = buf.split('\n\n');
      for (var i = 0; i < parts.length - 1; i++) {
        for (final line in parts[i].split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          if (data == '[DONE]') return;
          try { yield jsonDecode(data) as Map<String, dynamic>; } catch (_) {}
        }
      }
      pending.write(parts.last);
    }
  }

  Future<String?> getLicitacionSummary(int licitacionId) async {
    final res = await _http.get(
      Uri.parse('$_base/licitaciones/$licitacionId/summary'),
      headers: await _headers(),
    );
    if (res.statusCode == 404) return null;
    _check(res);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['summary'] as String?;
  }

  Future<void> saveLicitacionSummary(int licitacionId, String summary) async {
    final res = await _http.post(
      Uri.parse('$_base/licitaciones/$licitacionId/summary'),
      headers: {...await _headers(), 'content-type': 'application/json'},
      body: jsonEncode({'summary': summary}),
    );
    _check(res);
  }

  // ── Notes ────────────────────────────────────────────────────────────────────

  Future<AdjudicacionResumen?> getAdjudicacionResumen(int licitacionId) async {
    final res = await _http.get(
      Uri.parse('$_base/licitaciones/$licitacionId/adjudicacion'),
      headers: await _headers(),
    );
    if (res.statusCode == 404) return null;
    _check(res);
    return AdjudicacionResumen.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<LicitacionNote>> getNotes(int licitacionId) async {
    final res = await _http.get(
      Uri.parse('$_base/licitaciones/$licitacionId/notes'),
      headers: await _headers(),
    );
    _check(res);
    return (jsonDecode(res.body) as List)
        .map((e) => LicitacionNote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<LicitacionNote> createNote(int licitacionId, String content) async {
    final res = await _http.post(
      Uri.parse('$_base/licitaciones/$licitacionId/notes'),
      headers: await _headers(),
      body: jsonEncode({'content': content}),
    );
    _check(res);
    final id = (jsonDecode(res.body) as Map<String, dynamic>)['id'] as int;
    final user = AuthService().currentUser;
    return LicitacionNote(
      id: id,
      userId: user?.id ?? 0,
      userNombre: user?.nombre,
      content: content,
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  // ── Cotizacion adjuntos ───────────────────────────────────────────────────────

  Future<List<CotizacionAdjunto>> getAdjuntos(int licitacionId) async {
    final res = await _http.get(
      Uri.parse('$_base/licitaciones/$licitacionId/cotizacion-adjuntos'),
      headers: await _headers(),
    );
    _check(res);
    return (jsonDecode(res.body) as List)
        .map((e) => CotizacionAdjunto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns {id, upload_url} after inserting the DB record.
  Future<Map<String, dynamic>> createAdjunto(
    int licitacionId, {
    required String nombre,
    required String contentType,
    required int sizeBytes,
  }) async {
    final res = await _http.post(
      Uri.parse('$_base/licitaciones/$licitacionId/cotizacion-adjuntos'),
      headers: {
        ...await _headers(),
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'nombre': nombre,
        'content_type': contentType,
        'size_bytes': sizeBytes,
      }),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deleteAdjunto(int licitacionId, int adjuntoId) async {
    final res = await _http.delete(
      Uri.parse(
          '$_base/licitaciones/$licitacionId/cotizacion-adjuntos/$adjuntoId'),
      headers: await _headers(),
    );
    _check(res);
  }

  // ── Documents ────────────────────────────────────────────────────────────────

  Future<List<LicitacionDocumento>> getDocumentos(int licitacionId) async {
    final res = await _http.get(
      Uri.parse('$_base/licitaciones/$licitacionId/documentos'),
      headers: await _headers(),
    );
    _check(res);
    return (jsonDecode(res.body) as List)
        .map((e) => LicitacionDocumento.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Registration ─────────────────────────────────────────────────────────────

  Future<int> registerRequest({
    required String email,
    required String nombre,
    required String password,
    required String role,
  }) async {
    final res = await _http.post(
      Uri.parse('$_base/auth/register'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'nombre': nombre,
        'password': password,
        'role': role,
      }),
    );
    _check(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['request_id'] as int;
  }

  /// Returns a map with keys: status, access_token?, refresh_token?, user?
  Future<Map<String, dynamic>> verifyOtp({
    required int requestId,
    required String otpCode,
  }) async {
    final res = await _http.post(
      Uri.parse('$_base/auth/register/verify'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'request_id': requestId, 'otp_code': otpCode}),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getPendingRegistrations() async {
    final res = await _http.get(
      Uri.parse('$_base/admin/pending-registrations'),
      headers: await _headers(),
    );
    _check(res);
    return (jsonDecode(res.body) as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  Future<void> approveRegistration(int requestId) async {
    final res = await _http.post(
      Uri.parse('$_base/admin/pending-registrations/$requestId/approve'),
      headers: await _headers(),
    );
    _check(res);
  }

  Future<void> rejectRegistration(int requestId) async {
    final res = await _http.post(
      Uri.parse('$_base/admin/pending-registrations/$requestId/reject'),
      headers: await _headers(),
    );
    _check(res);
  }

  Future<List<StageHistoryItem>> getStageHistory(int licitacionId) async {
    final res = await _http.get(
      Uri.parse('$_base/licitaciones/$licitacionId/stage-history'),
      headers: await _headers(),
    );
    _check(res);
    return (jsonDecode(res.body) as List)
        .map((e) => StageHistoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateFabricante(
    int licitacionId, {
    required bool fabricanteProteccion,
    String? fabricanteNombre,
  }) async {
    final res = await _http.patch(
      Uri.parse('$_base/licitaciones/$licitacionId/fabricante'),
      headers: await _headers(),
      body: jsonEncode({
        'fabricante_proteccion': fabricanteProteccion,
        'fabricante_nombre': fabricanteNombre,
      }),
    );
    _check(res);
  }

  // ── Chat ─────────────────────────────────────────────────────────────────────

  /// Streaming chat via Lambda Function URL (RESPONSE_STREAM).
  /// Yields raw SSE event payloads: {"session_id":"..."}, {"token":"..."}, then [DONE].
  /// Falls back to the buffered REST endpoint when [chatStreamBase] is not configured.
  Stream<Map<String, dynamic>> chatStream({
    required String message,
    String? sessionId,
    int? licitacionId,
  }) async* {
    if (chatStreamBase.isEmpty) {
      // Fallback: call buffered endpoint and yield the full reply as a single token
      final resp = await chat(message: message, sessionId: sessionId, licitacionId: licitacionId);
      yield {'session_id': resp.sessionId};
      yield {'token': resp.reply};
      return;
    }

    final uri = Uri.parse(chatStreamBase);
    final headers = await _headers();
    final request = http.Request('POST', uri);
    request.headers.addAll(headers);
    request.body = jsonEncode({
      'message': message,
      if (sessionId != null) 'session_id': sessionId,
      if (licitacionId != null) 'licitacion_id': licitacionId,
    });

    final streamed = await _http.send(request);
    if (streamed.statusCode >= 400) {
      throw Exception('Error ${streamed.statusCode}');
    }

    // SSE parsing: accumulate bytes → split on \n\n → extract data: lines
    final pending = StringBuffer();
    await for (final chunk in streamed.stream.transform(Utf8Decoder(allowMalformed: true))) {
      pending.write(chunk);
      var buf = pending.toString();
      pending.clear();

      // Split on double-newline (SSE event boundary)
      final parts = buf.split('\n\n');
      for (var i = 0; i < parts.length - 1; i++) {
        for (final line in parts[i].split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          if (data == '[DONE]') return;
          try {
            yield jsonDecode(data) as Map<String, dynamic>;
          } catch (_) {}
        }
      }
      // Keep the incomplete trailing fragment
      pending.write(parts.last);
    }
  }

  Future<ChatResponse> chat({
    required String message,
    String? sessionId,
    int? licitacionId,
  }) async {
    final res = await _http.post(
      Uri.parse('$_base/chat'),
      headers: await _headers(),
      body: jsonEncode({
        'message': message,
        if (sessionId != null) 'session_id': sessionId,
        if (licitacionId != null) 'licitacion_id': licitacionId,
      }),
    );
    _check(res);
    return ChatResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<ChatSession>> getChatSessions() async {
    final res = await _http.get(
      Uri.parse('$_base/chat/sessions'),
      headers: await _headers(),
    );
    _check(res);
    return (jsonDecode(res.body) as List)
        .map((j) => ChatSession.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<ChatSessionDetail> getChatSession(String sessionId) async {
    final res = await _http.get(
      Uri.parse('$_base/chat/sessions/$sessionId'),
      headers: await _headers(),
    );
    _check(res);
    return ChatSessionDetail.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ── Helper ───────────────────────────────────────────────────────────────────

  void _check(http.Response res) {
    if (res.statusCode >= 400) {
      String msg = 'Error ${res.statusCode}';
      try {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        msg = j['error'] as String? ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }
}
