import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'auth/auth_service.dart';
import 'core/device_role.dart';
import 'core/permissions.dart';
import 'data/finance_exchange.dart';
import 'database/app_database.dart';

const navy = Color(0xFF17365D);
const teal = Color(0xFF16A6A1);
final money = NumberFormat.currency(locale: 'fr_FR', symbol: 'HTG ', decimalDigits: 2);
String nowIso() => DateTime.now().toIso8601String();
String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

final messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeviceRoleStore.load();
  await AppDatabase.instance.database;
  // Une écriture refusée sur un appareil en consultation ne doit jamais échouer en silence.
  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is ReadOnlyDeviceException) {
      messengerKey.currentState?.showSnackBar(SnackBar(content: Text(error.message)));
      return true;
    }
    return false;
  };
  runApp(const MBBApp());
}

class MBBApp extends StatelessWidget {
  const MBBApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
      title: 'MBB',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: navy),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        appBarTheme: const AppBarTheme(backgroundColor: navy, foregroundColor: Colors.white),
        cardTheme: CardThemeData(elevation: 1, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: const AuthGate(),
    );
  }
}


class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Principal? currentUser;
  @override
  Widget build(BuildContext context) {
    if (currentUser != null) return HomeShell(principal: currentUser!, onLogout: () => setState(() => currentUser = null));
    return LoginPage(onLogin: (user) => setState(() => currentUser = user));
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin});
  final ValueChanged<Principal> onLogin;
  @override State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;
  List<Bureau> bureausWithoutAdmin = const [];
  @override void initState() { super.initState(); _loadSetup(); }
  Future<void> _loadSetup() async {
    final list = await AuthService.bureausWithoutAdmin();
    if (mounted) setState(() => bureausWithoutAdmin = list);
  }
  Future<void> login() async {
    setState(() { busy = true; error = null; });
    try {
      final principal = await AuthService.login(username.text, password.text);
      if (principal == null) {
        setState(() => error = 'Identifiant ou mot de passe incorrect.');
      } else {
        widget.onLogin(principal);
      }
    } catch (_) { setState(() => error = 'Impossible de se connecter. Vérifiez les données locales.'); }
    if (mounted) setState(() => busy = false);
  }
  @override void dispose() { username.dispose(); password.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.asset('assets/mbb_icon.png', width: 84, height: 84)),
      const SizedBox(height: 12), const Text('MBB', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: navy)),
      const Text('Mission Baptiste Béraca', textAlign: TextAlign.center), const SizedBox(height: 24),
      TextField(controller: username, decoration: const InputDecoration(labelText: 'Identifiant', prefixIcon: Icon(Icons.person_outline))),
      const SizedBox(height: 12), TextField(controller: password, obscureText: true, onSubmitted: (_) => login(), decoration: const InputDecoration(labelText: 'Mot de passe', prefixIcon: Icon(Icons.lock_outline))),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 18), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: busy ? null : login, icon: const Icon(Icons.login), label: Text(busy ? 'Connexion…' : 'Se connecter'))),
      if (bureausWithoutAdmin.isNotEmpty) TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SetupPage(bureaus: bureausWithoutAdmin, onCreated: (user) { Navigator.of(context).pop(); widget.onLogin(user); }))), child: const Text('Première configuration d’un bureau')),
      const SizedBox(height: 4),
      const Text('Les comptes sont créés par l’administrateur de chaque bureau.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
    ])))))),
  );
}

/// Création du PREMIER administrateur d'un bureau qui n'en a pas encore.
/// Une fois l'administrateur créé, ce chemin se referme pour ce bureau.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.bureaus, required this.onCreated});
  final List<Bureau> bureaus;
  final ValueChanged<Principal> onCreated;
  @override State<SetupPage> createState() => _SetupPageState();
}
class _SetupPageState extends State<SetupPage> {
  final username = TextEditingController(); final password = TextEditingController(); final confirm = TextEditingController();
  late Bureau bureau = widget.bureaus.first; String? error; bool busy = false;
  Future<void> create() async {
    if (password.text != confirm.text) { setState(() => error = 'Les deux mots de passe ne sont pas identiques.'); return; }
    setState(() { busy = true; error = null; });
    try {
      final principal = await AuthService.bootstrapAdmin(bureau, username.text, password.text);
      if (!mounted) return;
      widget.onCreated(principal);
      return;
    } on ArgumentError catch (e) { error = '${e.message}'; }
    on AuthorizationException catch (e) { error = e.message; }
    catch (_) { error = 'Cet identifiant existe déjà ou le compte n’a pas pu être créé.'; }
    if (mounted) setState(() => busy = false);
  }
  @override void dispose() { username.dispose(); password.dispose(); confirm.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Première configuration')), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: ListView(padding: const EdgeInsets.all(20), children: [
    const Icon(Icons.admin_panel_settings_outlined, size: 52, color: navy), const SizedBox(height: 12),
    const Text('Créez l’administrateur d’un bureau qui n’en possède pas encore. Cet administrateur n’aura accès qu’à son propre bureau.'),
    const SizedBox(height: 16),
    DropdownButtonFormField<Bureau>(initialValue: bureau, decoration: const InputDecoration(labelText: 'Bureau', prefixIcon: Icon(Icons.work_outline)), items: [for (final b in widget.bureaus) DropdownMenuItem(value: b, child: Text(b.label))], onChanged: (v) { if (v != null) setState(() => bureau = v); }),
    const SizedBox(height: 12), TextField(controller: username, decoration: const InputDecoration(labelText: 'Identifiant', prefixIcon: Icon(Icons.person_outline))),
    const SizedBox(height: 12), TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe (8 caractères minimum)', prefixIcon: Icon(Icons.lock_outline))),
    const SizedBox(height: 12), TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmer le mot de passe', prefixIcon: Icon(Icons.lock_reset))),
    if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Colors.red))),
    const SizedBox(height: 16), FilledButton.icon(onPressed: busy ? null : create, icon: const Icon(Icons.check), label: Text(busy ? 'Création…' : 'Créer l’administrateur')),
  ]))));
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.principal, required this.onLogout});
  final Principal principal;
  final VoidCallback onLogout;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.page);
  final String label; final IconData icon; final Widget page;
}

class _HomeShellState extends State<HomeShell> {
  int selected = 0;
  String churchName = 'Mission Baptiste Béraca';
  late final List<_NavItem> items;
  Principal get me => widget.principal;
  bool get isAdmin => me.role == BureauRole.administrateur;

  @override void initState() { super.initState();
    final dash = _NavItem('Tableau de bord', Icons.dashboard_outlined, DashboardPage(bureau: me.bureau));
    final extra = <_NavItem>[
      if (AccessPolicy.can(me, Permission.usersManage)) _NavItem('Comptes', Icons.manage_accounts_outlined, AccountsPage(principal: me)),
      if (isAdmin) const _NavItem('Paramètres', Icons.settings_outlined, SettingsPage()),
      if (AccessPolicy.can(me, Permission.backupManage)) _NavItem('Sauvegarde', Icons.backup_outlined, BackupPage(principal: me)),
    ];
    if (me.bureau == Bureau.comptabilite) {
      items = [dash, _NavItem('Comptabilité', Icons.account_balance_wallet_outlined, FinancePage(principal: me)), ...extra];
    } else {
      items = [dash,
        _NavItem('Membres', Icons.people_alt_outlined, MembersPage(principal: me)),
        const _NavItem('Familles', Icons.family_restroom, FamiliesPage()),
        const _NavItem('Cultes et réunions', Icons.church_outlined, ServicesPage()),
        const _NavItem('Présences', Icons.fact_check_outlined, AttendancePage()),
        const _NavItem('Classes et groupes', Icons.groups_outlined, GroupsPage()),
        const _NavItem('Annonces', Icons.campaign_outlined, AnnouncementsPage()),
        ...extra];
    }
  }

  Future<void> loadChurchName() async {
    final rows = await AppDatabase.instance.query('app_settings', where: 'key = ?', whereArgs: ['church_name']);
    if (rows.isNotEmpty && mounted) setState(() => churchName = rows.first['value'] as String);
  }
  @override
  void didChangeDependencies() { super.didChangeDependencies(); loadChurchName(); }

  void _openMenu() {
    showModalBottomSheet<void>(context: context, builder: (sheet) => SafeArea(child: ListView(shrinkWrap: true, children: [
      for (var i = 0; i < items.length; i++) ListTile(leading: Icon(items[i].icon), title: Text(items[i].label), selected: i == selected, onTap: () { Navigator.pop(sheet); setState(() => selected = i); }),
    ])));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 850;
      final compactNav = items.length > 5;
      final barItems = compactNav ? items.take(4).toList() : items;
      return Scaffold(
        appBar: AppBar(
          actions: [Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Center(child: Text('${me.bureau.label} · ${isAdmin ? 'Administrateur' : 'Employé'}', style: const TextStyle(fontSize: 12)))), IconButton(tooltip: 'Déconnexion', onPressed: widget.onLogout, icon: const Icon(Icons.logout))],
          title: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(9), child: Image.asset('assets/mbb_icon.png', width: 36, height: 36)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('MBB', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(churchName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal), overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),
        body: Column(children: [
          ValueListenableBuilder<DeviceRole>(valueListenable: DeviceRoleStore.notifier, builder: (_, role, __) => role == DeviceRole.principal ? const SizedBox.shrink() : Container(width: double.infinity, color: Colors.orange.shade100, padding: const EdgeInsets.all(8), child: const Text('Mode consultation : cet appareil est en lecture seule. Les données ne s’enregistrent que sur l’appareil principal.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)))),
          Expanded(child: Row(children: [
          if (wide) NavigationRail(
            selectedIndex: selected, onDestinationSelected: (v) => setState(() => selected = v),
            labelType: NavigationRailLabelType.all,
            destinations: [for (final it in items) NavigationRailDestination(icon: Icon(it.icon), label: Text(it.label))],
          ),
          Expanded(child: IndexedStack(index: selected, children: [for (final it in items) it.page])),
        ])),
        ]),
        bottomNavigationBar: wide ? null : NavigationBar(
          selectedIndex: compactNav ? (selected < 4 ? selected : 4) : selected,
          onDestinationSelected: (v) { if (compactNav && v == 4) { _openMenu(); } else { setState(() => selected = v); } },
          destinations: [
            for (final it in barItems) NavigationDestination(icon: Icon(it.icon), label: it.label.length > 12 ? it.label.split(' ').first : it.label),
            if (compactNav) const NavigationDestination(icon: Icon(Icons.menu), label: 'Menu'),
          ],
        ),
      );
    });
  }
}

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key, required this.principal});
  final Principal principal;
  @override State<AccountsPage> createState() => _AccountsPageState();
}
class _AccountsPageState extends State<AccountsPage> {
  Future<void> _guard(Future<void> Function() action) async {
    try { await action(); }
    on ArgumentError catch (e) { if (mounted) showMessage(context, '${e.message}'); }
    on AuthorizationException catch (e) { if (mounted) showMessage(context, e.message); }
    catch (_) { if (mounted) showMessage(context, 'Opération impossible (identifiant déjà utilisé ?).'); }
    if (mounted) setState(() {});
  }
  Future<void> _create() async {
    final user = TextEditingController(); final pass = TextEditingController(); bool admin = false;
    final ok = await showDialog<bool>(context: context, builder: (d) => StatefulBuilder(builder: (c, refresh) => AlertDialog(
      title: Text('Nouveau compte — ${widget.principal.bureau.label}'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: user, decoration: const InputDecoration(labelText: 'Identifiant')), const SizedBox(height: 10),
        TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe initial (8 caractères min.)')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Administrateur de ce bureau'), value: admin, onChanged: (v) => refresh(() => admin = v)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Créer'))],
    )));
    if (ok == true) { await _guard(() => AuthService.createUser(widget.principal, user.text, pass.text, admin: admin)); }
    user.dispose(); pass.dispose();
  }
  Future<void> _reset(Map<String, Object?> u) async {
    final pass = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: Text('Nouveau mot de passe — ${u['username']}'),
      content: TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe (8 caractères min.)')),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Changer'))],
    ));
    if (ok == true) { await _guard(() => AuthService.resetPassword(widget.principal, u['id'] as int, pass.text)); }
    pass.dispose();
  }
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.transparent,
    floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.person_add_alt_1), label: const Text('Nouveau compte')),
    body: FutureBuilder<List<Map<String, Object?>>>(future: AuthService.listUsers(widget.principal), builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      return ListView(padding: const EdgeInsets.all(12), children: [
        Padding(padding: const EdgeInsets.all(8), child: Text('Comptes du bureau « ${widget.principal.bureau.label} »', style: Theme.of(context).textTheme.titleLarge)),
        ...snap.data!.map((u) => Card(child: ListTile(
          leading: Icon(u['role'] == 'ADM' ? Icons.admin_panel_settings_outlined : Icons.person_outline, color: u['active'] == 1 ? navy : Colors.grey),
          title: Text('${u['username']}'), subtitle: Text('${u['role'] == 'ADM' ? 'Administrateur' : 'Employé'}${u['active'] == 1 ? '' : ' · désactivé'}'),
          trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'pwd') _reset(u); if (v == 'toggle') _guard(() => AuthService.setActive(widget.principal, u['id'] as int, u['active'] != 1)); },
            itemBuilder: (_) => [const PopupMenuItem(value: 'pwd', child: Text('Changer le mot de passe')), PopupMenuItem(value: 'toggle', child: Text(u['active'] == 1 ? 'Désactiver' : 'Réactiver'))]),
        ))),
      ]);
    }));
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.bureau});
  final Bureau bureau;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}
class _DashboardPageState extends State<DashboardPage> {
  bool get finance => widget.bureau == Bureau.comptabilite;
  // Seules les données du bureau de l'utilisateur sont lues.
  Future<Map<String, dynamic>> stats() async {
    final db = AppDatabase.instance;
    if (finance) {
      return {'income': await db.financeTotal('Recette'), 'expenses': await db.financeTotal('Dépense'), 'count': await db.count('transactions')};
    }
    return {'members': await db.count('members'), 'families': await db.count('families'), 'services': await db.count('services'), 'announcements': await db.count('announcements')};
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: stats(), builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final s = snap.data!;
      return RefreshIndicator(onRefresh: () async { setState(() {}); }, child: ListView(
        padding: const EdgeInsets.all(18), children: [
          Text(widget.bureau.label, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const Text('Fonctionne sans internet : les données restent sur cet appareil.'),
          const SizedBox(height: 18),
          if (finance) ...[
            Builder(builder: (context) {
              final income = s['income'] as double; final expenses = s['expenses'] as double;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 12, runSpacing: 12, children: [
                  StatCard(title: 'Opérations', value: '${s['count']}', icon: Icons.receipt_long, color: teal),
                  StatCard(title: 'Solde', value: money.format(income - expenses), icon: Icons.account_balance_wallet, color: Colors.green),
                ]),
                const SizedBox(height: 18),
                Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Résumé financier', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  _moneyLine('Recettes', income, Colors.green),
                  _moneyLine('Dépenses', expenses, Colors.red),
                  const Divider(),
                  _moneyLine('Solde', income - expenses, navy),
                ]))),
              ]);
            }),
          ] else
            Wrap(spacing: 12, runSpacing: 12, children: [
              StatCard(title: 'Membres', value: '${s['members']}', icon: Icons.people, color: navy),
              StatCard(title: 'Familles', value: '${s['families']}', icon: Icons.family_restroom, color: teal),
              StatCard(title: 'Cultes / réunions', value: '${s['services']}', icon: Icons.church, color: Colors.deepPurple),
              StatCard(title: 'Annonces', value: '${s['announcements']}', icon: Icons.campaign, color: Colors.orange),
            ]),
        ],
      ));
    });
}
Widget _moneyLine(String label, double value, Color color) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: Row(children: [Expanded(child: Text(label)), Text(money.format(value), style: TextStyle(fontWeight: FontWeight.bold, color: color))]),
);

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.title, required this.value, required this.icon, required this.color});
  final String title, value; final IconData icon; final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(width: 230, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
    CircleAvatar(backgroundColor: color.withValues(alpha: .12), child: Icon(icon, color: color)),
    const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: Colors.black54)), const SizedBox(height: 5), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
    ])),
  ]))));
}

Future<void> showMessage(BuildContext context, String message) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> showFormDialog(BuildContext context, String title, List<FieldSpec> fields, Future<void> Function(Map<String, String>) save) async {
  final controllers = <String, TextEditingController>{};
  for (final f in fields) { controllers[f.key] = TextEditingController(text: f.initial); }
  final formKey = GlobalKey<FormState>();
  await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
    title: Text(title),
    content: SizedBox(width: 420, child: SingleChildScrollView(child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: fields.map((f) => Padding(
      padding: const EdgeInsets.only(bottom: 12), child: TextFormField(
        controller: controllers[f.key], keyboardType: f.numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        decoration: InputDecoration(labelText: f.label), validator: f.required ? (v) => (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null : null,
      ),
    )).toList())))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
      FilledButton(onPressed: () async {
        if (!(formKey.currentState?.validate() ?? false)) return;
        final values = {for (final e in controllers.entries) e.key: e.value.text.trim()};
        Navigator.pop(dialogContext);
        await save(values);
      }, child: const Text('Enregistrer')),
    ],
  ));
  for (final c in controllers.values) { c.dispose(); }
}
class FieldSpec {
  const FieldSpec(this.key, this.label, {this.required = false, this.numeric = false, this.initial = ''});
  final String key, label; final bool required, numeric; final String initial;
}

class MembersPage extends StatefulWidget {
  const MembersPage({super.key, required this.principal});
  final Principal principal;
  @override State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  String search = '';
  Future<List<Map<String, Object?>>> load() async {
    final rows = await AppDatabase.instance.query('members', orderBy: 'last_name COLLATE NOCASE');
    return rows.where((r) => '${r['first_name']} ${r['last_name']} ${r['phone']}'.toLowerCase().contains(search.toLowerCase())).toList();
  }

  Future<String?> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, withData: false);
    if (result == null || result.files.single.path == null) return null;
    final source = File(result.files.single.path!);
    final dir = await getApplicationSupportDirectory();
    final photoDir = Directory(p.join(dir.path, 'member_photos'));
    await photoDir.create(recursive: true);
    final ext = p.extension(source.path).toLowerCase();
    final destination = p.join(photoDir.path, 'member_${DateTime.now().microsecondsSinceEpoch}${ext.isEmpty ? '.jpg' : ext}');
    await source.copy(destination);
    return destination;
  }

  Future<void> _memberForm({Map<String, Object?>? member}) async {
    final db = AppDatabase.instance;
    final families = await db.query('families', orderBy: 'name COLLATE NOCASE');
    final groups = await db.query('groups_classes', where: 'active = 1', orderBy: 'name COLLATE NOCASE');
    if (!mounted) return;
    final formKey = GlobalKey<FormState>();
    final first = TextEditingController(text: '${member?['first_name'] ?? ''}');
    final last = TextEditingController(text: '${member?['last_name'] ?? ''}');
    final phone = TextEditingController(text: '${member?['phone'] ?? ''}');
    final email = TextEditingController(text: '${member?['email'] ?? ''}');
    final address = TextEditingController(text: '${member?['address'] ?? ''}');
    final birth = TextEditingController(text: '${member?['birth_date'] ?? ''}');
    final notes = TextEditingController(text: '${member?['notes'] ?? ''}');
    String photo = '${member?['photo_path'] ?? ''}';
    String role = '${member?['church_role'] ?? ''}';
    String gender = '${member?['gender'] ?? ''}';
    int? familyId = member?['family_id'] as int?;
    int? sundayClassId = member?['sunday_school_class_id'] as int?;
    bool baptized = member?['baptized'] == 1;
    final selectedGroups = <int>{};
    if (member != null) {
      final links = await db.query('member_groups', where: 'member_id = ?', whereArgs: [member['id']]);
      selectedGroups.addAll(links.map((r) => r['group_id'] as int));
    }
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
      title: Text(member == null ? 'Ajouter un membre' : 'Modifier le membre'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [CircleAvatar(radius: 32, backgroundImage: photo.isNotEmpty && File(photo).existsSync() ? FileImage(File(photo)) : null, child: photo.isEmpty ? const Icon(Icons.person_outline, size: 32) : null), const SizedBox(width: 12), OutlinedButton.icon(onPressed: () async { final picked = await _pickPhoto(); if (picked != null) refresh(() => photo = picked); }, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Ajouter une photo'))]),
        const SizedBox(height: 14),
        TextFormField(controller: first, decoration: const InputDecoration(labelText: 'Prénom'), validator: (v) => v == null || v.trim().isEmpty ? 'Champ obligatoire' : null),
        const SizedBox(height: 10), TextFormField(controller: last, decoration: const InputDecoration(labelText: 'Nom'), validator: (v) => v == null || v.trim().isEmpty ? 'Champ obligatoire' : null),
        const SizedBox(height: 10), TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone_outlined))),
        const SizedBox(height: 10), TextFormField(controller: email, decoration: const InputDecoration(labelText: 'Courriel', prefixIcon: Icon(Icons.mail_outline))),
        const SizedBox(height: 10), TextFormField(controller: address, decoration: const InputDecoration(labelText: 'Adresse', prefixIcon: Icon(Icons.location_on_outlined))),
        const SizedBox(height: 10), TextFormField(controller: birth, decoration: const InputDecoration(labelText: 'Date de naissance (AAAA-MM-JJ)', prefixIcon: Icon(Icons.calendar_month_outlined))),
        const SizedBox(height: 10), DropdownButtonFormField<String>(initialValue: gender.isEmpty ? null : gender, decoration: const InputDecoration(labelText: 'Sexe'), items: const [DropdownMenuItem(value: 'Femme', child: Text('Femme')), DropdownMenuItem(value: 'Homme', child: Text('Homme')), DropdownMenuItem(value: 'Autre', child: Text('Autre'))], onChanged: (v) => refresh(() => gender = v ?? '')),
        const SizedBox(height: 10), DropdownButtonFormField<int?>(initialValue: familyId, decoration: const InputDecoration(labelText: 'Famille'), items: [const DropdownMenuItem<int?>(value: null, child: Text('Aucune famille')), ...families.map((f) => DropdownMenuItem<int?>(value: f['id'] as int, child: Text('${f['name']}')))], onChanged: (v) => refresh(() => familyId = v)),
        const SizedBox(height: 10), DropdownButtonFormField<int?>(initialValue: sundayClassId, decoration: const InputDecoration(labelText: 'Classe d’école du dimanche'), items: [const DropdownMenuItem<int?>(value: null, child: Text('Aucune classe sélectionnée')), ...groups.where((g) => '${g['item_type']}'.toLowerCase().contains('classe') || '${g['item_type']}'.toLowerCase().contains('école')).map((g) => DropdownMenuItem<int?>(value: g['id'] as int, child: Text('${g['name']}')))], onChanged: (v) => refresh(() => sundayClassId = v)),
        const SizedBox(height: 10), DropdownButtonFormField<String>(initialValue: role.isEmpty ? null : role, decoration: const InputDecoration(labelText: 'Rôle dans l’église'), items: const [DropdownMenuItem(value: 'Pasteur', child: Text('Pasteur')), DropdownMenuItem(value: 'Diacre', child: Text('Diacre')), DropdownMenuItem(value: 'Responsable', child: Text('Responsable')), DropdownMenuItem(value: 'Membre', child: Text('Membre')), DropdownMenuItem(value: 'Autre', child: Text('Autre'))], onChanged: (v) => refresh(() => role = v ?? '')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Membre baptisé'), value: baptized, onChanged: (v) => refresh(() => baptized = v)),
        if (groups.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Text('Groupes et équipes', style: Theme.of(context).textTheme.titleSmall)),
        ...groups.where((g) => !('${g['item_type']}'.toLowerCase().contains('classe') || '${g['item_type']}'.toLowerCase().contains('école'))).map((g) => CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text('${g['name']}'), value: selectedGroups.contains(g['id']), onChanged: (v) => refresh(() { if (v == true) { selectedGroups.add(g['id'] as int); } else { selectedGroups.remove(g['id']); } }))),
        const SizedBox(height: 10), TextFormField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
      ])))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')), FilledButton.icon(icon: const Icon(Icons.save_outlined), label: const Text('Enregistrer'), onPressed: () async {
        if (!(formKey.currentState?.validate() ?? false)) return;
        final values = <String, Object?>{'first_name': first.text.trim(), 'last_name': last.text.trim(), 'phone': phone.text.trim(), 'email': email.text.trim(), 'address': address.text.trim(), 'birth_date': birth.text.trim(), 'gender': gender, 'family_id': familyId, 'photo_path': photo, 'baptized': baptized ? 1 : 0, 'church_role': role, 'sunday_school_class_id': sundayClassId, 'notes': notes.text.trim(), 'status': 'Actif'};
        if (member == null) { values['created_at'] = nowIso(); final id = await db.insert('members', values); for (final groupId in selectedGroups) { await db.insert('member_groups', {'member_id': id, 'group_id': groupId}); } await db.log('CREATE_MEMBER', '${first.text.trim()} ${last.text.trim()}'); }
        else { await db.update('members', values, where: 'id = ?', whereArgs: [member['id']]); await db.delete('member_groups', where: 'member_id = ?', whereArgs: [member['id']]); for (final groupId in selectedGroups) { await db.insert('member_groups', {'member_id': member['id'], 'group_id': groupId}); } await db.log('UPDATE_MEMBER', '${member['id']}'); }
        if (dialogContext.mounted) Navigator.pop(dialogContext);
        if (mounted) setState(() {});
      })],
    )));
    for (final c in [first, last, phone, email, address, birth, notes]) { c.dispose(); }
  }

  Future<void> remove(Map<String, Object?> r) async {
    if (!AccessPolicy.can(widget.principal, Permission.membersDelete)) { showMessage(context, 'Suppression réservée à l’administrateur du bureau.'); return; }
    final yes = await confirmDelete(context, '${r['first_name']} ${r['last_name']}');
    if (yes) { await AppDatabase.instance.delete('members', where: 'id = ?', whereArgs: [r['id']]); await AppDatabase.instance.log('DELETE_MEMBER', '${r['id']}'); if (mounted) setState(() {}); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    floatingActionButton: FloatingActionButton.extended(onPressed: () => _memberForm(), icon: const Icon(Icons.person_add_alt_1), label: const Text('Ajouter un membre')),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un membre'), onChanged: (v) => setState(() => search = v)),
      const SizedBox(height: 10),
      Expanded(child: FutureBuilder<List<Map<String, Object?>>>(future: load(), builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const Center(child: Text('Aucun membre. Appuyez sur Ajouter pour commencer.'));
        return ListView.builder(itemCount: rows.length, itemBuilder: (context, i) {
          final r = rows[i]; final photo = '${r['photo_path'] ?? ''}';
          return Card(child: ListTile(leading: CircleAvatar(backgroundColor: navy, backgroundImage: photo.isNotEmpty && File(photo).existsSync() ? FileImage(File(photo)) : null, child: photo.isEmpty ? Text('${r['first_name']}'.isNotEmpty ? '${r['first_name']}'.substring(0, 1).toUpperCase() : '?', style: const TextStyle(color: Colors.white)) : null),
            title: Text('${r['first_name']} ${r['last_name']}'), subtitle: Text('${r['phone'] ?? ''}  ${r['email'] ?? ''}\n${r['baptized'] == 1 ? 'Baptisé' : 'Non baptisé'} · ${r['church_role'] ?? 'Rôle non défini'}'), isThreeLine: true,
            trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'edit') _memberForm(member: r); if (v == 'delete') remove(r); }, itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Modifier')), if (AccessPolicy.can(widget.principal, Permission.membersDelete)) const PopupMenuItem(value: 'delete', child: Text('Supprimer'))])));
        });
      })),
    ])),
  );
}

class GroupsPage extends StatefulWidget { const GroupsPage({super.key}); @override State<GroupsPage> createState() => _GroupsPageState(); }
class _GroupsPageState extends State<GroupsPage> {
  Future<void> add() async => showFormDialog(context, 'Créer une classe ou un groupe', const [
    FieldSpec('name', 'Nom de la classe ou du groupe', required: true),
    FieldSpec('item_type', 'Type (Groupe, Classe dominicale, Pastorat…)', required: true, initial: 'Groupe'),
    FieldSpec('description', 'Description'), FieldSpec('leader_name', 'Responsable'),
    FieldSpec('monthly_contribution', 'Contribution mensuelle HTG', numeric: true, initial: '0'),
  ], (v) async {
    final amount = double.tryParse((v['monthly_contribution'] ?? '0').replaceAll(',', '.')) ?? 0;
    await AppDatabase.instance.insert('groups_classes', {...v, 'monthly_contribution': amount, 'active': 1, 'created_at': nowIso()});
    await AppDatabase.instance.log('CREATE_GROUP_CLASS', '${v['name']}'); if (mounted) setState(() {});
  });
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.transparent, floatingActionButton: FloatingActionButton.extended(onPressed: add, icon: const Icon(Icons.add), label: const Text('Ajouter')), body: FutureBuilder<List<Map<String,Object?>>>(future: AppDatabase.instance.query('groups_classes', where: 'active = ?', whereArgs: [1], orderBy: 'name COLLATE NOCASE'), builder: (context,snap) {
    if (!snap.hasData) return const Center(child: CircularProgressIndicator()); final rows = snap.data!;
    return ListView(padding: const EdgeInsets.all(12), children: [const Padding(padding: EdgeInsets.all(8), child: Text('Créez librement les groupes et classes de votre église. Aucun groupe n’est imposé.', style: TextStyle(color: Colors.black54))), if (rows.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Aucune classe ni aucun groupe. Utilisez Ajouter pour en créer un.')), ...rows.map((r) => Card(child: ListTile(leading: const Icon(Icons.groups_outlined, color: navy), title: Text('${r['name']}'), subtitle: Text('${r['item_type']} · Responsable : ${r['leader_name']}\nContribution mensuelle : ${money.format((r['monthly_contribution'] as num?)?.toDouble() ?? 0)}'), isThreeLine: true, trailing: IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline), onPressed: () async { if (await confirmDelete(context, '${r['name']}')) { await AppDatabase.instance.delete('groups_classes', where: 'id = ?', whereArgs: [r['id']]); if (mounted) setState(() {}); } }))))]);
  }));
}

class AnnouncementsPage extends StatefulWidget { const AnnouncementsPage({super.key}); @override State<AnnouncementsPage> createState() => _AnnouncementsPageState(); }
class _AnnouncementsPageState extends State<AnnouncementsPage> {
  Future<void> add() async => showFormDialog(context, 'Créer une annonce', [const FieldSpec('title','Titre',required:true), const FieldSpec('target_group','Groupe concerné',required:true,initial:'Tous les membres'), const FieldSpec('description','Description',required:true), FieldSpec('announcement_date','Date (AAAA-MM-JJ)',required:true,initial:today()), const FieldSpec('signature','Signature du responsable',required:true)], (v) async { await AppDatabase.instance.insert('announcements',{...v,'status':'Publié','created_at':nowIso()}); await AppDatabase.instance.log('CREATE_ANNOUNCEMENT',v['title'] ?? ''); if(mounted) setState((){}); });
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.transparent, floatingActionButton: FloatingActionButton.extended(onPressed: add, icon: const Icon(Icons.add), label: const Text('Nouvelle annonce')), body: FutureBuilder<List<Map<String,Object?>>>(future: AppDatabase.instance.query('announcements',orderBy:'announcement_date DESC'), builder:(context,snap){ if(!snap.hasData) return const Center(child:CircularProgressIndicator()); final rows=snap.data!; if(rows.isEmpty) return const Center(child:Text('Aucune annonce enregistrée.')); return ListView(padding:const EdgeInsets.all(12),children:rows.map((r)=>Card(child:ListTile(leading:const Icon(Icons.campaign_outlined,color:navy),title:Text('${r['title']}'),subtitle:Text('${r['announcement_date']} · ${r['target_group']}\n${r['description']}\nSignature : ${r['signature']}'),isThreeLine:true))).toList()); }));
}

class FamiliesPage extends StatefulWidget { const FamiliesPage({super.key}); @override State<FamiliesPage> createState() => _FamiliesPageState(); }
class _FamiliesPageState extends State<FamiliesPage> {
  Future<void> add() async => showFormDialog(context, 'Ajouter une famille', const [
    FieldSpec('name', 'Nom de la famille', required: true), FieldSpec('address', 'Adresse'), FieldSpec('notes', 'Notes'),
  ], (v) async { await AppDatabase.instance.insert('families', {...v, 'created_at': nowIso()}); await AppDatabase.instance.log('CREATE_FAMILY', v['name'] ?? ''); if (mounted) setState(() {}); });
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.transparent, floatingActionButton: FloatingActionButton.extended(onPressed: add, icon: const Icon(Icons.add), label: const Text('Ajouter famille')),
    body: FutureBuilder<List<Map<String, Object?>>>(future: AppDatabase.instance.query('families', orderBy: 'name'), builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (snap.data!.isEmpty) return const Center(child: Text('Aucune famille enregistrée.'));
      return ListView(
        padding: const EdgeInsets.all(12),
        children: snap.data!.map((r) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.family_restroom, color: teal),
              title: Text('${r['name']}'),
              subtitle: Text('${r['address']}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirmDelete(context, '${r['name']}')) {
                    await AppDatabase.instance.delete(
                      'families', where: 'id = ?', whereArgs: [r['id']],
                    );
                    if (mounted) setState(() {});
                  }
                },
              ),
            ),
          );
        }).toList(),
      );
    }));
}

class ServicesPage extends StatefulWidget { const ServicesPage({super.key}); @override State<ServicesPage> createState() => _ServicesPageState(); }
class _ServicesPageState extends State<ServicesPage> {
  Future<void> add() async => showFormDialog(context, 'Ajouter un culte ou une réunion', [
    const FieldSpec('title', 'Nom du service', required: true), FieldSpec('service_date', 'Date (AAAA-MM-JJ)', required: true, initial: today()), const FieldSpec('notes', 'Notes'),
  ], (v) async { await AppDatabase.instance.insert('services', v); await AppDatabase.instance.log('CREATE_SERVICE', v['title'] ?? ''); if (mounted) setState(() {}); });
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.transparent, floatingActionButton: FloatingActionButton.extended(onPressed: add, icon: const Icon(Icons.add), label: const Text('Ajouter service')),
    body: FutureBuilder<List<Map<String, Object?>>>(future: AppDatabase.instance.query('services', orderBy: 'service_date DESC'), builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (snap.data!.isEmpty) return const Center(child: Text('Aucun culte ou réunion enregistré.'));
      return ListView(
        padding: const EdgeInsets.all(12),
        children: snap.data!.map((r) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.church, color: navy),
              title: Text('${r['title']}'),
              subtitle: Text('${r['service_date']} — ${r['notes']}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirmDelete(context, '${r['title']}')) {
                    await AppDatabase.instance.delete(
                      'services', where: 'id = ?', whereArgs: [r['id']],
                    );
                    if (mounted) setState(() {});
                  }
                },
              ),
            ),
          );
        }).toList(),
      );
    }));
}

class AttendancePage extends StatefulWidget { const AttendancePage({super.key}); @override State<AttendancePage> createState() => _AttendancePageState(); }
class _AttendancePageState extends State<AttendancePage> {
  String selectedDate = today();
  Future<void> mark(Map<String, Object?> member, String status) async {
    final db = AppDatabase.instance;
    final existing = await db.query('attendance', where: 'member_id = ? AND service_date = ?', whereArgs: [member['id'], selectedDate]);
    final values = {'member_id': member['id'], 'service_date': selectedDate, 'status': status, 'created_at': nowIso()};
    if (existing.isEmpty) { await db.insert('attendance', values); } else { await db.update('attendance', values, where: 'id = ?', whereArgs: [existing.first['id']]); }
    await db.log('MARK_ATTENDANCE', '${member['id']} $status $selectedDate');
    if (mounted) setState(() {});
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(16), child: TextFormField(initialValue: selectedDate, decoration: const InputDecoration(labelText: 'Date du culte (AAAA-MM-JJ)', prefixIcon: Icon(Icons.calendar_month)), onChanged: (v) => setState(() => selectedDate = v.trim()))),
    Expanded(child: FutureBuilder<List<Map<String, Object?>>>(future: AppDatabase.instance.query('members', where: 'status = ?', whereArgs: ['Actif'], orderBy: 'last_name'), builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (snap.data!.isEmpty) return const Center(child: Text('Ajoutez d’abord des membres.'));
      return ListView(children: snap.data!.map((m) => FutureBuilder<List<Map<String, Object?>>>(future: AppDatabase.instance.query('attendance', where: 'member_id = ? AND service_date = ?', whereArgs: [m['id'], selectedDate]), builder: (context, aSnap) {
        final current = aSnap.data?.isNotEmpty == true ? '${aSnap.data!.first['status']}' : 'Non marqué';
        return Card(child: ListTile(title: Text('${m['first_name']} ${m['last_name']}'), subtitle: Text('Statut : $current'), trailing: PopupMenuButton<String>(tooltip: 'Enregistrer présence', onSelected: (v) => mark(m, v), itemBuilder: (_) => const [
          PopupMenuItem(value: 'Présent', child: Text('Présent')), PopupMenuItem(value: 'Absent', child: Text('Absent')), PopupMenuItem(value: 'Retard', child: Text('Retard')),
        ])));
      })).toList());
    })),
  ]);
}

class FinancePage extends StatefulWidget { const FinancePage({super.key, required this.principal}); final Principal principal; @override State<FinancePage> createState() => _FinancePageState(); }
class _FinancePageState extends State<FinancePage> {
  Future<void> add(String kind) async { if (!AccessPolicy.can(widget.principal, Permission.financeRecord)) { showMessage(context, 'Action non autorisée.'); return; } await _addForm(kind); }
  Future<void> _addForm(String kind) async => showFormDialog(context, kind == 'Recette' ? 'Ajouter une recette' : 'Ajouter une dépense', [
    const FieldSpec('category', 'Catégorie', required: true), FieldSpec('amount', 'Montant HTG', required: true, numeric: true),
    FieldSpec('transaction_date', 'Date (AAAA-MM-JJ)', required: true, initial: today()), const FieldSpec('description', 'Description'),
  ], (v) async {
    final amount = double.tryParse(v['amount']!.replaceAll(',', '.'));
    if (amount == null || amount <= 0) { if (mounted) showMessage(context, 'Entrez un montant positif valide.'); return; }
    await AppDatabase.instance.insert('transactions', {...v, 'amount': amount, 'kind': kind, 'created_at': nowIso()});
    await AppDatabase.instance.log('CREATE_TRANSACTION', '$kind ${v['category']} $amount', username: widget.principal.username);
    if (mounted) setState(() {});
  });
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, children: [
      FilledButton.icon(onPressed: () => add('Recette'), icon: const Icon(Icons.add), label: const Text('Recette')),
      FilledButton.tonalIcon(onPressed: () => add('Dépense'), icon: const Icon(Icons.remove), label: const Text('Dépense')),
    ])),
    Expanded(child: FutureBuilder<List<Map<String, Object?>>>(future: AppDatabase.instance.query('transactions', orderBy: 'transaction_date DESC, id DESC'), builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snap.data!;
      if (rows.isEmpty) return const Center(child: Text('Aucune opération financière enregistrée.'));
      return ListView(padding: const EdgeInsets.all(12), children: rows.map((r) {
        final isIncome = r['kind'] == 'Recette'; final amount = (r['amount'] as num).toDouble();
        return Card(child: ListTile(leading: CircleAvatar(backgroundColor: (isIncome ? Colors.green : Colors.red).withValues(alpha: .12), child: Icon(isIncome ? Icons.arrow_downward : Icons.arrow_upward, color: isIncome ? Colors.green : Colors.red)),
          title: Text('${r['category']} — ${money.format(amount)}'), subtitle: Text('${r['transaction_date']} · ${r['description']}'), trailing: AccessPolicy.can(widget.principal, Permission.financeVoid) ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { if (await confirmDelete(context, 'cette opération')) { AccessPolicy.require(widget.principal, Permission.financeVoid); await AppDatabase.instance.delete('transactions', where: 'id = ?', whereArgs: [r['id']]); await AppDatabase.instance.log('DELETE_TRANSACTION', '${r['id']}', username: widget.principal.username); if (mounted) setState(() {}); } }) : null));
      }).toList());
    })),
  ]);
}

class SettingsPage extends StatefulWidget { const SettingsPage({super.key}); @override State<SettingsPage> createState() => _SettingsPageState(); }
class _SettingsPageState extends State<SettingsPage> {
  final church = TextEditingController(); final app = TextEditingController(); String language = 'Français';
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final rows = await AppDatabase.instance.query('app_settings');
    final values = {for (final r in rows) '${r['key']}': '${r['value']}'};
    church.text = values['church_name'] ?? 'Mission Baptiste Béraca'; app.text = values['app_name'] ?? 'MBB'; language = values['language'] ?? 'Français';
    if (mounted) setState(() {});
  }
  Future<void> _save() async {
    final db = AppDatabase.instance;
    for (final entry in {'church_name': church.text.trim(), 'app_name': app.text.trim(), 'language': language}.entries) {
      final rows = await db.query('app_settings', where: 'key = ?', whereArgs: [entry.key]);
      if (rows.isEmpty) { await db.insert('app_settings', {'key': entry.key, 'value': entry.value}); }
      else { await db.update('app_settings', {'value': entry.value}, where: 'key = ?', whereArgs: [entry.key]); }
    }
    await db.log('UPDATE_SETTINGS', 'Configuration générale modifiée');
    if (mounted) showMessage(context, 'Paramètres enregistrés. Le titre affiché dans l’en-tête sera actualisé au prochain lancement.');
  }
  @override
  void dispose() { church.dispose(); app.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    Text('Configuration', style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 16),
    const DeviceRoleCard(),
    const SizedBox(height: 16),
    TextField(controller: church, decoration: const InputDecoration(labelText: 'Nom de l’église')),
    const SizedBox(height: 12), TextField(controller: app, decoration: const InputDecoration(labelText: 'Nom de l’application affiché dans les paramètres')),
    const SizedBox(height: 12), DropdownButtonFormField<String>(initialValue: language, decoration: const InputDecoration(labelText: 'Langue de l’interface'), items: const [DropdownMenuItem(value: 'Français', child: Text('Français')), DropdownMenuItem(value: 'Kreyòl ayisyen', child: Text('Kreyòl ayisyen'))], onChanged: (v) { if (v != null) setState(() => language = v); }),
    const SizedBox(height: 16), FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Enregistrer')),
    const SizedBox(height: 12), const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('Base de données locale'), subtitle: Text('SQLite est stockée dans le dossier privé de l’application. Désinstaller l’application peut supprimer les données locales : faites des sauvegardes régulièrement.'))),
  ]);
}

class BackupPage extends StatelessWidget {
  const BackupPage({super.key, required this.principal});
  final Principal principal;
  Future<void> _exportFinance(BuildContext context) async {
    try {
      final r = await FinanceExchange.export(principal);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'MBB_Comptabilite_${today()}.json'));
      await file.writeAsString(r.json);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Échange MBB Comptabilité'));
      if (context.mounted && r.skipped > 0) showMessage(context, '${r.skipped} ligne(s) à montant nul non exportée(s).');
    } catch (e) { if (context.mounted) showMessage(context, 'Échec de l’exportation : $e'); }
  }
  Future<void> _importFinance(BuildContext context) async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: false);
      if (picked == null || picked.files.single.path == null) return;
      final raw = await File(picked.files.single.path!).readAsString();
      final preview = await FinanceExchange.preview(principal, raw);
      if (!context.mounted) return;
      if (!preview.fileOk) {
        await showDialog<void>(context: context, builder: (c) => AlertDialog(title: const Text('Fichier refusé'), content: Text(preview.fileErrors.join('\n')), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer'))]));
        return;
      }
      final plan = preview.plan!;
      final details = [...plan.conflicts, ...plan.invalid].take(8).join('\n');
      final go = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: const Text('Résumé de l’importation'),
        content: SingleChildScrollView(child: Text('${plan.summary()}\n\nRien n’est supprimé ni écrasé. Les conflits et lignes invalides sont ignorés.${details.isEmpty ? '' : '\n\n$details'}')),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')), if (plan.toAdd.isNotEmpty) FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Importer ${plan.toAdd.length}'))]));
      if (go != true) return;
      final n = await FinanceExchange.apply(principal, plan);
      if (context.mounted) showMessage(context, '$n opération(s) importée(s). Une copie de sécurité a été créée avant l’importation.');
    } catch (e) { if (context.mounted) showMessage(context, 'Échec de l’importation : $e'); }
  }
  Future<void> _export(BuildContext context) async {
    try {
      final dbPath = await _databasePath();
      final result = await FilePicker.platform.saveFile(dialogTitle: 'Enregistrer la sauvegarde MBB', fileName: 'MBB_backup_${today()}.db', type: FileType.custom, allowedExtensions: ['db']);
      if (result == null) return;
      await File(dbPath).copy(result);
      await AppDatabase.instance.log('BACKUP_EXPORT', result);
      if (context.mounted) showMessage(context, 'Sauvegarde exportée : $result');
    } catch (e) { if (context.mounted) showMessage(context, 'Échec de la sauvegarde : $e'); }
  }
  Future<void> _import(BuildContext context) async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['db'], withData: false);
      if (picked == null || picked.files.single.path == null) return;
      if (!context.mounted) return;
      final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Restaurer une sauvegarde ?'), content: const Text('Le fichier est d’abord vérifié, puis une copie de sécurité de la base actuelle est créée automatiquement avant le remplacement.'), actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restaurer')),
      ]));
      if (confirm != true) return;
      final source = File(picked.files.single.path!);
      final problem = await AppDatabase.validateBackupFile(source.path);
      if (problem != null) { if (context.mounted) showMessage(context, problem); return; }
      final destination = await _databasePath();
      // Copie de sécurité automatique AVANT tout remplacement.
      final safetyDir = Directory(p.join(p.dirname(destination), 'sauvegardes_auto'));
      await safetyDir.create(recursive: true);
      final safety = File(p.join(safetyDir.path, 'avant_restauration_${DateTime.now().millisecondsSinceEpoch}.db'));
      await AppDatabase.instance.closeAndReset();
      await File(destination).copy(safety.path);
      try {
        await source.copy(destination);
      } catch (e) {
        await safety.copy(destination); // retour à l'état précédent
        rethrow;
      }
      await AppDatabase.instance.log('BACKUP_RESTORE', 'copie de sécurité : ${safety.path}');
      // Une sauvegarde provient d'un autre état : l'appareil repasse en consultation
      // pour éviter deux appareils qui enregistrent. Réglage : Paramètres > Appareil principal.
      await DeviceRoleStore.set(DeviceRole.consultation);
      if (context.mounted) showMessage(context, 'Base restaurée (copie de sécurité conservée dans le dossier de l’application). Cet appareil est maintenant en mode consultation. Fermez puis rouvrez MBB ; un administrateur peut le remettre en appareil principal dans Paramètres.');
    } catch (e) { if (context.mounted) showMessage(context, 'Échec de la restauration : $e'); }
  }
  Future<void> _shareAudit(BuildContext context) async {
    final rows = await AppDatabase.instance.query('audit_logs', orderBy: 'id DESC');
    final csv = StringBuffer('id;date;utilisateur;action;details\n');
    for (final r in rows) { csv.writeln('${r['id']};${r['created_at']};${r['username']};${r['action']};${r['details']}'); }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'MBB_historique.csv'));
    await file.writeAsString(csv.toString());
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Historique MBB'));
  }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    Text('Sauvegarde et transfert', style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 8), const Text('Le fichier .db contient la base SQLite de l’application. Conservez-le dans un endroit sûr.'),
    const SizedBox(height: 16),
    Card(child: ListTile(leading: const Icon(Icons.upload_file, color: teal), title: const Text('Exporter la base de données'), subtitle: const Text('Créer une copie complète de la base SQLite.'), trailing: const Icon(Icons.chevron_right), onTap: () => _export(context))),
    Card(child: ListTile(leading: const Icon(Icons.restore, color: navy), title: const Text('Restaurer une base de données'), subtitle: const Text('Remplacer la base locale à partir d’un fichier .db.'), trailing: const Icon(Icons.chevron_right), onTap: () => _import(context))),
    Card(child: ListTile(leading: const Icon(Icons.history), title: const Text('Exporter l’historique des actions'), subtitle: const Text('Partager l’historique au format CSV.'), trailing: const Icon(Icons.chevron_right), onTap: () => _shareAudit(context))),
    if (AccessPolicy.can(principal, Permission.financeExport)) ...[
      const SizedBox(height: 8),
      Card(child: ListTile(leading: const Icon(Icons.swap_horiz, color: teal), title: const Text('Exporter la comptabilité (JSON)'), subtitle: const Text('Fichier d’échange vérifiable, réservé à la comptabilité.'), trailing: const Icon(Icons.chevron_right), onTap: () => _exportFinance(context))),
      Card(child: ListTile(leading: const Icon(Icons.download_for_offline, color: navy), title: const Text('Importer la comptabilité (JSON)'), subtitle: const Text('Ajoute seulement les opérations nouvelles, avec résumé avant confirmation.'), trailing: const Icon(Icons.chevron_right), onTap: () => _importFinance(context))),
    ],
    const SizedBox(height: 12),
    const Card(child: ListTile(leading: Icon(Icons.warning_amber, color: Colors.orange), title: Text('Important'), subtitle: Text('Cette sauvegarde contient les données des DEUX bureaux (une seule base locale) et n’est pas chiffrée : ne la confiez qu’à une personne autorisée. Une exportation séparée par bureau reste à développer. Le système de comptes et permissions avancées reste à compléter avant un usage sensible en production.'))),
  ]);
}

Future<String> _databasePath() async {
  final dir = await getApplicationSupportDirectory();
  return p.join(dir.path, 'mbb_database.db');
}

Future<bool> confirmDelete(BuildContext context, String item) async =>
    await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Confirmer la suppression'),
      content: Text('Voulez-vous vraiment supprimer $item ?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
      ],
    )) ?? false;

class DeviceRoleCard extends StatelessWidget {
  const DeviceRoleCard({super.key});
  Future<void> _toggle(BuildContext context, bool principal) async {
    if (principal) {
      final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
        title: const Text('Faire de cet appareil l’appareil principal ?'),
        content: const Text('Un seul appareil doit enregistrer les données. Avant de continuer, mettez l’ancien appareil principal en mode consultation, et vérifiez que cet appareil contient bien la dernière sauvegarde.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Confirmer'))],
      ));
      if (ok != true) return;
    }
    await DeviceRoleStore.set(principal ? DeviceRole.principal : DeviceRole.consultation);
    await AppDatabase.instance.log(principal ? 'DEVICE_PRINCIPAL' : 'DEVICE_CONSULTATION', '');
  }
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DeviceRole>(
    valueListenable: DeviceRoleStore.notifier,
    builder: (_, role, __) => Card(child: SwitchListTile(
      secondary: const Icon(Icons.devices_outlined),
      title: const Text('Appareil principal'),
      subtitle: Text(role == DeviceRole.principal ? 'Cet appareil enregistre les données. Tous les autres doivent rester en consultation.' : 'Mode consultation : lecture, rapports et exportation seulement.'),
      value: role == DeviceRole.principal,
      onChanged: (v) => _toggle(context, v),
    )),
  );
}
