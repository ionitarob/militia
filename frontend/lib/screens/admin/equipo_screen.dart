import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show PopupMenuItem, RelativeRect, showMenu;
import 'package:flutter/services.dart';
import '../../api/client.dart';
import '../../api/models.dart';

const _navy  = Color(0xFF0F1F3D);
const _blue  = Color(0xFF2563EB);
const _ink   = Color(0xFF111827);
const _muted = Color(0xFF6B7280);
const _bg    = Color(0xFFF1F4F9);
const _white = Color(0xFFFFFFFF);
const _border = Color(0xFFE5E7EB);

class AdminEquipoScreen extends StatefulWidget {
  final bool readOnly;
  const AdminEquipoScreen({super.key, this.readOnly = false});

  @override
  State<AdminEquipoScreen> createState() => _AdminEquipoScreenState();
}

class _AdminEquipoScreenState extends State<AdminEquipoScreen> {
  List<Team> _teams = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final teams = await ApiClient().getTeams();
      if (mounted) {
        setState(() { _teams = teams; _loading = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _createTeam() async {
    final ctrl = TextEditingController();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Nuevo equipo'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: ctrl,
            placeholder: 'Nombre del equipo',
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    try {
      await ApiClient().createTeam(ctrl.text.trim());
      await _load();
    } catch (e) {
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Error'),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          actions: [
            CupertinoDialogAction(child: const Text('OK'), onPressed: () => Navigator.pop(context)),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: _bg,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            backgroundColor: _bg,
            border: null,
            largeTitle: const Text(
              'Equipo',
              style: TextStyle(
                color: _navy,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            trailing: widget.readOnly ? null : CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _createTeam,
              child: const Icon(CupertinoIcons.plus_circle_fill, color: _blue, size: 24),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_circle, color: _muted, size: 32),
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: _muted, fontSize: 14)),
                    const SizedBox(height: 16),
                    CupertinoButton(onPressed: _load, child: const Text('Reintentar')),
                  ],
                ),
              ),
            )
          else if (_teams.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(CupertinoIcons.person_2_fill, color: _blue, size: 28),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Sin equipos todavía',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _navy),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Toca + para crear tu primer equipo.',
                      style: TextStyle(fontSize: 14, color: _muted),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _TeamSection(
                  team: _teams[i],
                  onChanged: _load,
                  readOnly: widget.readOnly,
                ),
                childCount: _teams.length,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Team section ──────────────────────────────────────────────────────────────

class _TeamSection extends StatelessWidget {
  final Team team;
  final VoidCallback onChanged;
  final bool readOnly;

  const _TeamSection({required this.team, required this.onChanged, this.readOnly = false});

  Future<void> _addMember(BuildContext context) async {
    try {
      final all     = await ApiClient().getUsers();
      final current = team.members.map((m) => m.userId).toSet();
      final avail   = all.where((u) => !current.contains(u.id)).toList();

      if (!context.mounted) return;
      if (avail.isEmpty) {
        showCupertinoDialog(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Sin usuarios disponibles'),
            content: const Text('Todos los usuarios ya pertenecen a este equipo.'),
            actions: [
              CupertinoDialogAction(child: const Text('OK'), onPressed: () => Navigator.pop(context)),
            ],
          ),
        );
        return;
      }

      if (!context.mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) return;
      final overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
      final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
      final picked = await showMenu<AppUser>(
        context: context,
        position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
        color: const Color(0xFFFFFFFF),
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
        items: avail.map((u) => PopupMenuItem<AppUser>(
          value: u,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(u.displayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
              Text(u.email, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
            ],
          ),
        )).toList(),
      );
      if (picked != null && context.mounted) {
        await ApiClient().addTeamMember(team.id, picked.id);
        onChanged();
      }
    } catch (e) {
      if (!context.mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Error'),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          actions: [
            CupertinoDialogAction(child: const Text('OK'), onPressed: () => Navigator.pop(context)),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                team.nombre,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _navy,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              if (!readOnly) CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () => _addMember(context),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.person_badge_plus, size: 16, color: _blue),
                    const SizedBox(width: 4),
                    const Text(
                      'Añadir',
                      style: TextStyle(fontSize: 13, color: _blue, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _navy.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: team.members.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Este equipo no tiene miembros todavía.',
                      style: TextStyle(fontSize: 14, color: _muted),
                    ),
                  )
                : Column(
                    children: List.generate(team.members.length, (i) {
                      final m = team.members[i];
                      return Column(
                        children: [
                          _MemberRow(
                            member: m,
                            readOnly: readOnly,
                            onRemove: () async {
                              HapticFeedback.lightImpact();
                              await ApiClient().removeTeamMember(team.id, m.userId);
                              onChanged();
                            },
                          ),
                          if (i < team.members.length - 1)
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
        ],
      ),
    );
  }
}

// ── Member row ────────────────────────────────────────────────────────────────

class _MemberRow extends StatelessWidget {
  final TeamMember member;
  final VoidCallback onRemove;
  final bool readOnly;

  const _MemberRow({required this.member, required this.onRemove, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    final initials = member.displayName
        .split(' ')
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 13,
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
                Text(
                  member.displayName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _ink),
                ),
                Text(
                  member.email,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: member.role == 'admin'
                  ? _navy.withValues(alpha: 0.08)
                  : _blue.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              member.role == 'admin' ? 'Admin' : 'Ventas',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: member.role == 'admin' ? _navy : _blue,
              ),
            ),
          ),
          if (!readOnly) ...[
            const SizedBox(width: 6),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: onRemove,
              child: const Icon(CupertinoIcons.minus_circle, size: 20, color: Color(0xFFDC2626)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── User picker sheet ─────────────────────────────────────────────────────────

