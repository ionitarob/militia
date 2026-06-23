import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/client.dart';
import '../api/models.dart';
import '../screens/chat_screen.dart';
import '../services/auth_service.dart';

// ── Global controller ─────────────────────────────────────────────────────────

class LitiChatController extends ChangeNotifier {
  static const _keySessionId = 'liti_chat_session_id';
  final _storage = const FlutterSecureStorage();

  bool _isOpen = false;
  bool get isOpen => _isOpen;

  String? _sessionId;
  String? get sessionId => _sessionId;
  set sessionId(String? v) {
    _sessionId = v;
    if (v != null) {
      _storage.write(key: _keySessionId, value: v);
    } else {
      _storage.delete(key: _keySessionId);
    }
  }

  final List<ChatMessage> messages = [];
  bool loading = false;
  String? contextTitle;

  // Silent screen context — injected into the first API message but never shown in UI
  String? _screenContext;
  int? _licitacionId;
  bool _contextChanged = false;

  final _api = ApiClient();

  void open()        { _isOpen = true;  notifyListeners(); }
  void close()       { _isOpen = false; notifyListeners(); }
  void toggle()      { _isOpen = !_isOpen; notifyListeners(); }
  void authChanged() { notifyListeners(); }

  /// Called by each screen so Liti always knows what the user is looking at.
  /// If the licitacion changes mid-session, a context update is silently injected
  /// into the next user message so the AI always knows what is on screen.
  void setScreenContext(String? ctx, {int? licitacionId}) {
    final changedLic = licitacionId != _licitacionId && sessionId != null && messages.isNotEmpty;
    _screenContext = ctx;
    _licitacionId = licitacionId;
    if (changedLic) _contextChanged = true;
  }

  void openWithContext(String contextMessage, String? title) {
    contextTitle = title;
    _isOpen = true;
    if (messages.isEmpty) {
      sendMessage(contextMessage, auto: true);
    }
    notifyListeners();
  }

  /// Restores the last session ID from secure storage and loads its messages.
  /// Call once at app startup after auth is confirmed.
  Future<void> restoreSession() async {
    final saved = await _storage.read(key: _keySessionId);
    if (saved == null || saved.isEmpty) return;
    try {
      final detail = await _api.getChatSession(saved);
      if (detail.messages.isNotEmpty) {
        _sessionId = saved;
        messages.addAll(detail.messages);
        notifyListeners();
      }
    } catch (_) {
      // Session no longer exists — discard it
      await _storage.delete(key: _keySessionId);
    }
  }

  void newSession() {
    sessionId = null;  // also clears persisted key via setter
    messages.clear();
    contextTitle = null;
    loading = false;
    _licitacionId = null;
    _contextChanged = false;
    notifyListeners();
  }

  Future<void> sendMessage(String text, {bool auto = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || loading) return;

    messages.add(ChatMessage(role: ChatRole.user, content: trimmed, timestamp: DateTime.now()));
    loading = true;
    notifyListeners();

    final isContextChange = _contextChanged;
    String apiMessage = trimmed;
    if (isContextChange && _screenContext != null) {
      apiMessage = '[NUEVA LICITACIÓN: El usuario ha navegado a otra licitación. Ahora está viendo — $_screenContext]\n\n$trimmed';
      _contextChanged = false;
    } else if (sessionId == null && _screenContext != null && messages.length == 1) {
      apiMessage = '[Contexto: el usuario está viendo — $_screenContext]\n\n$trimmed';
    }

    final licId = (messages.length == 1 || isContextChange) ? _licitacionId : null;

    // Placeholder assistant bubble that we fill in as tokens arrive
    final assistantIdx = messages.length;
    messages.add(ChatMessage(role: ChatRole.assistant, content: '', timestamp: DateTime.now()));
    notifyListeners();

    try {
      await for (final event in _api.chatStream(
        message: apiMessage,
        sessionId: sessionId,
        licitacionId: licId,
      )) {
        if (event.containsKey('session_id')) {
          sessionId = event['session_id'] as String?;
        } else if (event.containsKey('token')) {
          final token = event['token'] as String? ?? '';
          messages[assistantIdx] = ChatMessage(
            role: ChatRole.assistant,
            content: messages[assistantIdx].content + token,
            timestamp: messages[assistantIdx].timestamp,
          );
          notifyListeners();
        } else if (event.containsKey('error')) {
          messages[assistantIdx] = ChatMessage(
            role: ChatRole.assistant,
            content: 'Error: ${event['error']}',
            timestamp: messages[assistantIdx].timestamp,
          );
          notifyListeners();
        }
      }

      // If the stream ended with no content (shouldn't happen), show fallback
      if (messages[assistantIdx].content.isEmpty) {
        messages[assistantIdx] = ChatMessage(
          role: ChatRole.assistant,
          content: 'Sin respuesta disponible.',
          timestamp: messages[assistantIdx].timestamp,
        );
      }
    } catch (e) {
      messages[assistantIdx] = ChatMessage(
        role: ChatRole.assistant,
        content: 'Error: ${e.toString().replaceAll("Exception: ", "")}',
        timestamp: messages[assistantIdx].timestamp,
      );
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

final litiChat = LitiChatController();

// ── Overlay widget (inserted via CupertinoApp.builder) ────────────────────────

class LitiChatOverlay extends StatelessWidget {
  const LitiChatOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: bottom + 20,
      right: 20,
      child: ListenableBuilder(
        listenable: litiChat,
        builder: (ctx, _) {
          if (AuthService().currentUser == null) return const SizedBox.shrink();
          return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
              child: child,
            ),
          ),
          child: litiChat.isOpen
              ? const _ChatPanel(key: ValueKey('panel'))
              : const _ChatFab(key: ValueKey('fab')),
          );
        },
      ),
    );
  }
}

// ── Palette ───────────────────────────────────────────────────────────────────

const _bg      = Color(0xFF0C0C18);
const _surface = Color(0xFF161528);
const _surface2 = Color(0xFF1E1C35);
const _accent  = Color(0xFF8B5CF6);
const _accentHi = Color(0xFFA78BFA);
const _white   = Color(0xFFFFFFFF);
const _text    = Color(0xFFE2DEEF);
const _muted   = Color(0xFF857FAA);
const _border  = Color(0xFF252340);

// ── FAB ───────────────────────────────────────────────────────────────────────

class _ChatFab extends StatelessWidget {
  const _ChatFab({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: litiChat.toggle,
      child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6D28D9), Color(0xFF4F46E5), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.50),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(CupertinoIcons.sparkles, size: 22, color: _white),
        ),
    );
  }
}

// ── Compact chat panel ────────────────────────────────────────────────────────

class _ChatPanel extends StatefulWidget {
  const _ChatPanel({super.key});

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final _inputCtrl   = TextEditingController();
  final _scrollCtrl  = ScrollController();
  final _focusNode   = FocusNode();

  @override
  void initState() {
    super.initState();
    litiChat.addListener(_onUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    litiChat.removeListener(_onUpdate);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() => litiChat.sendMessage(_inputCtrl.text).then((_) {
        if (mounted) _inputCtrl.clear();
      });

  @override
  Widget build(BuildContext context) {
    return Container(
        width: 380,
        height: 520,
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 32,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: _accent.withValues(alpha: 0.08),
              blurRadius: 40,
              offset: const Offset(0, 0),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(child: _buildMessages()),
              _buildInput(),
            ],
          ),
        ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6D28D9), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(CupertinoIcons.sparkles, size: 13, color: _white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Liti', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _white)),
                if (litiChat.contextTitle != null)
                  Text(
                    litiChat.contextTitle!,
                    style: const TextStyle(fontSize: 10, color: _muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // New session
          _HeaderBtn(
            icon: CupertinoIcons.square_pencil,
            onTap: litiChat.newSession,
          ),
          // Full screen
          _HeaderBtn(
            icon: CupertinoIcons.arrow_up_left_arrow_down_right,
            onTap: () {
              litiChat.close();
              Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(builder: (_) => const ChatScreen()),
              );
            },
          ),
          // Close
          _HeaderBtn(
            icon: CupertinoIcons.xmark,
            onTap: litiChat.close,
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    final msgs = litiChat.messages;
    if (msgs.isEmpty && !litiChat.loading) {
      return _EmptyPanel();
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      itemCount: msgs.length + (litiChat.loading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == msgs.length) return const _MiniTyping();
        final m = msgs[i];
        final isUser = m.role == ChatRole.user;
        if (isUser) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const SizedBox(width: 40),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6D28D9), Color(0xFF7C3AED)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(3),
                      ),
                    ),
                    child: Text(m.content, style: const TextStyle(fontSize: 13, color: _white, height: 1.45)),
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6D28D9), Color(0xFF4F46E5)]),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(CupertinoIcons.sparkles, size: 10, color: _white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MarkdownBody(
                  data: m.content,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 13, color: _text, height: 1.55),
                    h1: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _white),
                    h2: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _white),
                    h3: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _white),
                    strong: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _white),
                    em: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: _text),
                    listBullet: const TextStyle(fontSize: 13, color: _accentHi),
                    tableHead: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _white),
                    tableBody: const TextStyle(fontSize: 12, color: _text),
                    tableBorder: TableBorder.all(color: _border, width: 1),
                    tableHeadAlign: TextAlign.left,
                    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    blockquotePadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    blockquoteDecoration: BoxDecoration(
                      color: _surface2,
                      border: Border(left: BorderSide(color: _accentHi, width: 3)),
                    ),
                    code: const TextStyle(fontSize: 12, color: _accentHi, fontFamily: 'monospace'),
                    codeblockDecoration: BoxDecoration(color: _surface2, borderRadius: BorderRadius.circular(6)),
                    horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: _border))),
                  ),
                  softLineBreak: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border, width: 0.5)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _surface2,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _inputCtrl,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 4,
                placeholder: 'Pregunta a Liti...',
                placeholderStyle: const TextStyle(color: _muted, fontSize: 13),
                style: const TextStyle(color: _text, fontSize: 13),
                decoration: const BoxDecoration(color: CupertinoColors.transparent),
                padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 5, bottom: 5),
              child: GestureDetector(
                onTap: litiChat.loading ? null : _send,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: litiChat.loading
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFF6D28D9), Color(0xFF7C3AED)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    color: litiChat.loading ? _surface2 : null,
                    shape: BoxShape.circle,
                  ),
                  child: litiChat.loading
                      ? const CupertinoActivityIndicator(color: _accentHi, radius: 7)
                      : const Icon(CupertinoIcons.arrow_up, size: 14, color: _white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header icon button ────────────────────────────────────────────────────────

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: const EdgeInsets.all(7),
        minimumSize: Size.zero,
        onPressed: onTap,
        child: Icon(icon, size: 15, color: _muted),
      );
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6D28D9), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(CupertinoIcons.sparkles, size: 20, color: _white),
          ),
          const SizedBox(height: 12),
          const Text('Hola, soy Liti', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _white)),
          const SizedBox(height: 6),
          const Text(
            'Pregúntame sobre cualquier licitación,\nadjudicación o estadística.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _muted, height: 1.5),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              '¿Qué licitaciones hay activas?',
              'Pipeline de hoy',
              'Adjudicaciones recientes',
            ].map((s) => GestureDetector(
              onTap: () => litiChat.sendMessage(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _surface2,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
                child: Text(s, style: const TextStyle(fontSize: 11, color: _text)),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Mini typing indicator ─────────────────────────────────────────────────────

class _MiniTyping extends StatefulWidget {
  const _MiniTyping();

  @override
  State<_MiniTyping> createState() => _MiniTypingState();
}

class _MiniTypingState extends State<_MiniTyping> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6D28D9), Color(0xFF4F46E5)]),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(CupertinoIcons.sparkles, size: 10, color: _white),
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
                final opacity = t * (1.0 - (_ctrl.value * 3 - i - 1).clamp(0.0, 1.0));
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 5, height: 5,
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

// ── Colors import shim ────────────────────────────────────────────────────────

// ignore: avoid_classes_with_only_static_members
class Colors {
  static const black = Color(0xFF000000);
}
