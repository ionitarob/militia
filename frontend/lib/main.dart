import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:intl/date_symbol_data_local.dart';
import 'package:window_manager/window_manager.dart';
import 'screens/licitaciones_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/admin/dashboard_screen.dart';
import 'screens/admin/equipo_screen.dart';
import 'screens/admin/mi_panel_admin_screen.dart';
import 'screens/vendedor/mi_panel_screen.dart';
import 'services/auth_service.dart';

// Minimum window dimensions — sidebar (168) + content minimum (632) × header + charts
const _kMinSize  = Size(900, 660);
const _kInitSize = Size(1280, 800);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  await _configureWindow();
  runApp(const IMLitiApp());
}

Future<void> _configureWindow() async {
  try {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size:        _kInitSize,
        minimumSize: _kMinSize,
        center:      true,
        title:       'IMLiti — Ingram Micro Licitaciones',
        titleBarStyle: TitleBarStyle.normal,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  } catch (_) {
    // Non-desktop platform — window_manager is a no-op
  }
}

class IMLitiApp extends StatelessWidget {
  const IMLitiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'IMLiti',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      theme: const CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: Color(0xFF2563EB),
        scaffoldBackgroundColor: Color(0xFFF1F4F9),
        textTheme: CupertinoTextThemeData(
          primaryColor: Color(0xFF0F1F3D),
        ),
      ),
      home: SplashScreen(),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = AuthService().currentUser?.isAdmin ?? false;
    return isAdmin ? const _AdminShell() : const _VendedorShell();
  }
}

// ── Admin shell: side navigation ──────────────────────────────────────────────

class _AdminShell extends StatefulWidget {
  const _AdminShell();
  @override
  State<_AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<_AdminShell> with SingleTickerProviderStateMixin {
  int _tab = 0;

  static const _items = [
    (CupertinoIcons.chart_bar_square_fill,      'Dashboard'),
    (CupertinoIcons.doc_text_search,            'Licitaciones'),
    (CupertinoIcons.person_crop_rectangle_fill, 'Mi Panel'),
    (CupertinoIcons.person_2_fill,              'Equipo'),
  ];

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF1F4F9),
      child: Row(
        children: [
          _Sidebar(
            selected: _tab,
            items: _items,
            onTap: (i) => setState(() => _tab = i),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [
                AdminDashboardScreen(),
                LicitacionesScreen(),
                MiPanelAdminScreen(),
                AdminEquipoScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar ───────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final int selected;
  final List<(IconData, String)> items;
  final void Function(int) onTap;

  const _Sidebar({
    required this.selected,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      width: 168,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1A2E), Color(0xFF0D2040)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: top + 20),

          // ── App icon + name ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset('assets/icon/icon.png', width: 38, height: 38, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                const Text(
                  'IMLiti',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE2E8F0),
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),

          // ── Nav items ─────────────────────────────────────────────
          ...List.generate(items.length, (i) => _NavItem(
            icon:     items[i].$1,
            label:    items[i].$2,
            selected: selected == i,
            onTap:    () => onTap(i),
          )),

          const Spacer(),
          SizedBox(height: bottom + 16),
        ],
      ),
    );
  }
}

// ── Nav item ──────────────────────────────────────────────────────────────────

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  static const _teal   = Color(0xFF2DD4BF);
  static const _dim    = Color(0xFF4B6380);
  static const _active = Color(0xFF1A3A5C);

  @override
  Widget build(BuildContext context) {
    final isActive = widget.selected;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _hovered = true),
        onTapUp:     (_) { setState(() => _hovered = false); widget.onTap(); },
        onTapCancel: ()  => setState(() => _hovered = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? _active
                : _hovered
                    ? const Color(0xFF0F2540)
                    : const Color(0x00000000),
            borderRadius: BorderRadius.circular(10),
            border: isActive
                ? Border.all(color: _teal.withValues(alpha: 0.18))
                : null,
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 3, height: 18,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: isActive ? _teal : const Color(0x00000000),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(
              widget.icon,
              size: 16,
              color: isActive ? _teal : _dim,
            ),
            const SizedBox(width: 10),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? _teal : _dim,
                letterSpacing: -0.1,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Vendedor shell: same sidebar as admin, read-only equipo ──────────────────

class _VendedorShell extends StatefulWidget {
  const _VendedorShell();
  @override
  State<_VendedorShell> createState() => _VendedorShellState();
}

class _VendedorShellState extends State<_VendedorShell> {
  int _tab = 0;

  static const _items = [
    (CupertinoIcons.chart_bar_square_fill, 'Dashboard'),
    (CupertinoIcons.doc_text_search,       'Licitaciones'),
    (CupertinoIcons.person_crop_rectangle_fill, 'Mi Panel'),
  ];

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF1F4F9),
      child: Row(
        children: [
          _Sidebar(
            selected: _tab,
            items: _items,
            onTap: (i) => setState(() => _tab = i),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [
                AdminDashboardScreen(),
                LicitacionesScreen(),
                MiPanelScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
