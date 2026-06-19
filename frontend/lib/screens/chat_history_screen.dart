import 'package:flutter/cupertino.dart';
import '../api/client.dart';
import '../api/models.dart';
import 'chat_screen.dart';

const _bg0     = Color(0xFF0A0A14);
const _accent  = Color(0xFF8B5CF6);
const _accentHi = Color(0xFFA78BFA);
const _white   = Color(0xFFFFFFFF);
const _text    = Color(0xFFE8E6F0);
const _muted   = Color(0xFF9490AD);
const _divider = Color(0xFF2A2845);

class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({super.key});

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  List<ChatSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ApiClient().getChatSessions();
      if (mounted) setState(() { _sessions = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _relativeDate(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays}d';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return CupertinoPageScaffold(
      backgroundColor: _bg0,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(4, topPad + 4, 16, 4),
            decoration: BoxDecoration(
              color: _bg0,
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
                  child: Text(
                    'Historial',
                    style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700,
                      color: _white, letterSpacing: -0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      CupertinoPageRoute(builder: (_) => const ChatScreen()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.square_pencil, size: 14, color: _accentHi),
                        SizedBox(width: 5),
                        Text('Nueva', style: TextStyle(fontSize: 13, color: _accentHi, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CupertinoActivityIndicator(color: _accentHi, radius: 14))
                : _sessions.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.chat_bubble_2, size: 48, color: _muted),
                            SizedBox(height: 12),
                            Text('No hay conversaciones aún', style: TextStyle(color: _muted, fontSize: 15)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _sessions.length,
                        separatorBuilder: (_, i) => Container(height: 0.5, color: _divider, margin: const EdgeInsets.only(left: 64, right: 16)),
                        itemBuilder: (ctx, i) {
                          final s = _sessions[i];
                          return CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.of(context).pop(s.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF6D28D9), Color(0xFF4F46E5)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(CupertinoIcons.sparkles, size: 18, color: _white),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.preview,
                                          style: const TextStyle(fontSize: 14, color: _text, fontWeight: FontWeight.w500),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${s.messageCount} mensajes · ${_relativeDate(s.updatedAt)}',
                                          style: const TextStyle(fontSize: 12, color: _muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(CupertinoIcons.chevron_forward, size: 14, color: _muted),
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
