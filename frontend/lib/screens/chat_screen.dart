import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../api/client.dart';
import '../api/models.dart';
import '../services/auth_service.dart';
import 'chat_history_screen.dart';

// ── Palette ───────────────────────────────────────────────────────────────────

const _bg0      = Color(0xFF0A0A14);   // near-black
const _surface  = Color(0xFF1A1830);   // card surface
const _surface2 = Color(0xFF221F3D);   // slightly lighter
const _accent   = Color(0xFF8B5CF6);   // purple
const _accentLo = Color(0xFF6D28D9);   // darker purple
const _accentHi = Color(0xFFA78BFA);   // light purple
const _white    = Color(0xFFFFFFFF);
const _text     = Color(0xFFE8E6F0);
const _muted    = Color(0xFF9490AD);
const _divider  = Color(0xFF2A2845);

class ChatScreen extends StatefulWidget {
  final String? initialContext;
  final String? sessionId;        // resume a specific past session
  final String? contextTitle;     // shown in nav subtitle when context provided

  const ChatScreen({
    super.key,
    this.initialContext,
    this.sessionId,
    this.contextTitle,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _api             = ApiClient();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode       = FocusNode();

  String? _sessionId;
  final List<ChatMessage> _messages = [];
  bool _loading = false;
  bool _loadingSession = false;

  String? get _userName {
    final email = AuthService().currentUser?.email;
    if (email == null) return null;
    final prefix = email.split('@').first;
    return prefix[0].toUpperCase() + prefix.substring(1);
  }

  @override
  void initState() {
    super.initState();
    if (widget.sessionId != null) {
      _loadSession(widget.sessionId!);
    } else if (widget.initialContext != null) {
      _sendMessage(widget.initialContext!, auto: true);
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSession(String sid) async {
    setState(() => _loadingSession = true);
    try {
      final detail = await _api.getChatSession(sid);
      if (mounted) {
        setState(() {
          _sessionId = sid;
          _messages.addAll(detail.messages);
          _loadingSession = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSession = false);
    }
  }

  Future<void> _sendMessage(String text, {bool auto = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _loading) return;

    if (!auto) _inputController.clear();

    setState(() {
      _messages.add(ChatMessage(role: ChatRole.user, content: trimmed, timestamp: DateTime.now()));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final resp = await _api.chat(message: trimmed, sessionId: _sessionId);
      if (mounted) {
        setState(() {
          _sessionId = resp.sessionId;
          _messages.add(ChatMessage(role: ChatRole.assistant, content: resp.reply, timestamp: DateTime.now()));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            role: ChatRole.assistant,
            content: 'Lo siento, hubo un error: ${e.toString().replaceAll("Exception: ", "")}',
            timestamp: DateTime.now(),
          ));
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _newSession() {
    setState(() {
      _sessionId = null;
      _messages.clear();
    });
  }

  void _openHistory() {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => const ChatHistoryScreen()),
    ).then((result) {
      if (result is String && mounted) {
        // Returned a session ID to resume
        _newSession();
        _loadSession(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: _bg0,
      child: Stack(
        children: [
          // Radial gradient background
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.6),
                  radius: 1.2,
                  colors: [
                    const Color(0xFF1E1640).withValues(alpha: 0.9),
                    _bg0,
                  ],
                ),
              ),
            ),
          ),

          Column(
            children: [
              _buildNavBar(),
              Expanded(
                child: _loadingSession
                    ? const Center(child: CupertinoActivityIndicator(color: _accentHi, radius: 14))
                    : _messages.isEmpty && !_loading
                        ? _GreetingView(
                            userName: _userName,
                            contextTitle: widget.contextTitle,
                            onSuggestion: _sendMessage,
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            itemCount: _messages.length + (_loading ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (i == _messages.length) return const _TypingIndicator();
                              return _MessageBubble(message: _messages[i]);
                            },
                          ),
              ),
              _InputBar(
                controller: _inputController,
                focusNode: _focusNode,
                loading: _loading,
                onSend: () => _sendMessage(_inputController.text),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavBar() {
    final bottom = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(4, bottom + 4, 4, 4),
      decoration: BoxDecoration(
        color: _bg0.withValues(alpha: 0.85),
        border: Border(bottom: BorderSide(color: _divider, width: 0.5)),
      ),
      child: Row(
        children: [
          CupertinoButton(
            padding: const EdgeInsets.all(12),
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(CupertinoIcons.back, color: _accentHi, size: 22),
          ),
          const Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LitiLogo(size: 22),
                SizedBox(width: 8),
                Text(
                  'Liti',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _white,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              if (_messages.isNotEmpty)
                CupertinoButton(
                  padding: const EdgeInsets.all(12),
                  onPressed: _newSession,
                  child: const Icon(CupertinoIcons.square_pencil, color: _muted, size: 20),
                ),
              CupertinoButton(
                padding: const EdgeInsets.all(12),
                onPressed: _openHistory,
                child: const Icon(CupertinoIcons.clock, color: _muted, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Greeting / empty state ─────────────────────────────────────────────────────

class _GreetingView extends StatelessWidget {
  final String? userName;
  final String? contextTitle;
  final void Function(String) onSuggestion;

  const _GreetingView({
    required this.userName,
    required this.contextTitle,
    required this.onSuggestion,
  });

  static const _globalSuggestions = [
    '¿Cuántas licitaciones activas hay?',
    'Busca licitaciones de telecomunicaciones en Madrid',
    '¿Adjudicaciones de los últimos 2 días?',
    'Estadísticas del pipeline comercial',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const _LitiLogo(size: 52),
          const SizedBox(height: 24),
          Text(
            userName != null ? 'Hola $userName,' : 'Hola,',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: _white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            contextTitle != null
                ? '¿Qué quieres saber sobre\n"$contextTitle"?'
                : '¿En qué puedo ayudarte?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: contextTitle != null ? 16 : 22,
              fontWeight: FontWeight.w400,
              color: _muted,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 36),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: (contextTitle != null
                    ? [
                        'Resume esta licitación',
                        'Analiza los documentos',
                        '¿Cuáles son los criterios?',
                        '¿Vale la pena presentarse?',
                      ]
                    : _globalSuggestions)
                .map((s) => _SuggestionChip(label: s, onTap: () => onSuggestion(s)))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _divider, width: 1),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: _text, height: 1.3),
          ),
        ),
      );
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const SizedBox(width: 56),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_accentLo, _accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  message.content,
                  style: const TextStyle(fontSize: 14, color: _white, height: 1.5),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // AI message — full width, no bubble
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LitiLogo(size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: MarkdownBody(
                data: message.content,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(fontSize: 14, color: _text, height: 1.65),
                  h1: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _white),
                  h2: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _white),
                  h3: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _white),
                  strong: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _white),
                  em: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: _text),
                  listBullet: const TextStyle(fontSize: 14, color: _accentHi),
                  tableHead: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _white),
                  tableBody: const TextStyle(fontSize: 13, color: _text),
                  tableBorder: TableBorder.all(color: const Color(0xFF2A2845), width: 1),
                  tableHeadAlign: TextAlign.left,
                  tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  blockquoteDecoration: const BoxDecoration(
                    color: Color(0xFF1E1C35),
                    border: Border(left: BorderSide(color: _accentHi, width: 3)),
                  ),
                  code: const TextStyle(fontSize: 13, color: _accentHi, fontFamily: 'monospace'),
                  codeblockDecoration: BoxDecoration(
                    color: const Color(0xFF1E1C35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  horizontalRuleDecoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFF2A2845))),
                  ),
                ),
                softLineBreak: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _LitiLogo(size: 28),
          const SizedBox(width: 10),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
                final opacity = t * (1 - (_ctrl.value * 3 - i - 1).clamp(0.0, 1.0));
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _accentHi.withValues(alpha: 0.3 + opacity * 0.7),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom
        + MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottom),
      decoration: BoxDecoration(
        color: _bg0.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: _divider, width: 0.5)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _surface2,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _divider, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 5,
                placeholder: 'Pregunta a Liti...',
                placeholderStyle: const TextStyle(color: _muted, fontSize: 15),
                style: const TextStyle(color: _text, fontSize: 15),
                decoration: const BoxDecoration(color: CupertinoColors.transparent),
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 6),
              child: GestureDetector(
                onTap: loading ? null : onSend,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: loading
                        ? null
                        : const LinearGradient(
                            colors: [_accentLo, _accent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    color: loading ? _surface2 : null,
                    shape: BoxShape.circle,
                  ),
                  child: loading
                      ? const CupertinoActivityIndicator(color: _accentHi, radius: 8)
                      : const Icon(CupertinoIcons.arrow_up, size: 17, color: _white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Liti logo (multi-tone sparkle) ────────────────────────────────────────────

class _LitiLogo extends StatelessWidget {
  final double size;
  const _LitiLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6D28D9), Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(
        CupertinoIcons.sparkles,
        size: size * 0.52,
        color: _white,
      ),
    );
  }
}
