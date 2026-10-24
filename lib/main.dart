import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database/app_database.dart';

const navy = Color(0xFF17365D);
const teal = Color(0xFF16A6A1);
final money = NumberFormat.currency(locale: 'fr_FR', symbol: 'HTG ', decimalDigits: 2);
String nowIso() => DateTime.now().toIso8601String();
String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.database;
  runApp(const MBBApp());
}

class MBBApp extends StatelessWidget {
  const MBBApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
  Map<String, Object?>? currentUser;
  @override
  Widget build(BuildContext context) {
    if (currentUser != null) return HomeShell(currentUser: currentUser!, onLogout: () => setState(() => currentUser = null));
    return LoginPage(onLogin: (user) => setState(() => currentUser = user));
  }
}

String _hashPassword(String salt, String password) => sha256.convert(utf8.encode('$salt:$password')).toString();

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin});
  final ValueChanged<Map<String, Object?>> onLogin;
  @override State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;
  Future<void> login() async {
    setState(() { busy = true; error = null; });
    try {
      final rows = await AppDatabase.instance.query('users', where: 'username = ? AND active = 1', whereArgs: [username.text.trim().toLowerCase()]);
      if (rows.isEmpty || _hashPassword('${rows.first['salt']}', password.text) != rows.first['password_hash']) {
        setState(() => error = 'Identifiant ou mot de passe incorrect.');
      } else {
        widget.onLogin(rows.first);
      }
    } catch (_) { setState(() => error = 'Impossible de se connecter. Vérifiez les données locales.'); }
    if (mounted) setState(() => busy = false);
  }
  @override void dispose() { username.dispose(); password.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 76, height: 76, decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.church_outlined, color: Colors.white, size: 44)),
      const SizedBox(height: 12), const Text('MBB', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: navy)),
      const Text('Mission Baptiste Béraca', textAlign: TextAlign.center), const SizedBox(height: 24),
      TextField(controller: username, decoration: const InputDecoration(labelText: 'Identifiant ou e-mail', prefixIcon: Icon(Icons.person_outline))),
      const SizedBox(height: 12), TextField(controller: password, obscureText: true, onSubmitted: (_) => login(), decoration: const InputDecoration(labelText: 'Mot de passe', prefixIcon: Icon(Icons.lock_outline))),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 18), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: busy ? null : login, icon: const Icon(Icons.login), label: Text(busy ? 'Connexion…' : 'Se connecter'))),
      TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SignupPage(onCreated: (user) { Navigator.of(context).pop(); widget.onLogin(user); }))), child: const Text('Créer un compte')),
    ])))))),
  );
}

class SignupPage extends StatefulWidget {
  const SignupPage({super.key, required this.onCreated});
  final ValueChanged<Map<String, Object?>> onCreated;
  @override State<SignupPage> createState() => _SignupPageState();
}
class _SignupPageState extends State<SignupPage> {
  final username = TextEditingController(); final password = TextEditingController(); final confirm = TextEditingController();
  String service = 'Services des cartes et annonces'; String? error; bool busy = false;
  Future<void> createAccount() async {
    final name = username.text.trim().toLowerCase();
    if (name.isEmpty || password.text.length < 8 || password.text != confirm.text) {
      setState(() => error = 'Saisissez un identifiant, un mot de passe de 8 caractères minimum et deux mots de passe identiques.'); return;
    }
    setState(() { busy = true; error = null; });
    try {
      final db = AppDatabase.instance;
      final count = await db.count('users');
      final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final values = <String, Object?>{'username': name, 'password_hash': _hashPassword(salt, password.text), 'salt': salt,
        'role': count == 0 ? 'ADM' : 'Utilisateur', 'service_access': service, 'is_first_admin': count == 0 ? 1 : 0,
        'active': 1, 'created_at': nowIso()};
      final id = await db.insert('users', values);
      await db.log('CREATE_ACCOUNT', '$name / $service / ${count == 0 ? 'ADM' : 'Utilisateur'}');
      if (!mounted) return;
      widget.onCreated({...values, 'id': id});
    } catch (_) { setState(() => error = 'Cet identifiant existe déjà ou le compte n’a pas pu être créé.'); }
    if (mounted) setState(() => busy = false);
  }
  @override void dispose() { username.dispose(); password.dispose(); confirm.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Créer un compte')), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: ListView(padding: const EdgeInsets.all(20), children: [
    const Icon(Icons.person_add_alt_1, size: 52, color: navy), const SizedBox(height: 16),
    TextField(controller: username, decoration: const InputDecoration(labelText: 'Identifiant', prefixIcon: Icon(Icons.person_outline))), const SizedBox(height: 12),
    TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe (8 caractères minimum)', prefixIcon: Icon(Icons.lock_outline))), const SizedBox(height: 12),
    TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmer le mot de passe', prefixIcon: Icon(Icons.lock_reset))), const SizedBox(height: 18),
    DropdownButtonFormField<String>(value: service, decoration: const InputDecoration(labelText: 'Service auquel vous souhaitez accéder', prefixIcon: Icon(Icons.work_outline)), items: const [
      DropdownMenuItem(value: 'Services des cartes et annonces', child: Text('Services des cartes et annonces')),
      DropdownMenuItem(value: 'Comptabilité', child: Text('Comptabilité')),
    ], onChanged: (v) { if (v != null) setState(() => service = v); }),
    const SizedBox(height: 10), const Text('Le premier compte créé devient Administrateur (ADM). Les comptes suivants restent des utilisateurs.'),
    if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Colors.red))),
    const SizedBox(height: 16), FilledButton.icon(onPressed: busy ? null : createAccount, icon: const Icon(Icons.person_add), label: Text(busy ? 'Création…' : 'Créer mon compte')),
  ]))));
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.currentUser, required this.onLogout});
  final Map<String, Object?> currentUser;
  final VoidCallback onLogout;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int selected = 0;
  String churchName = 'Mission Baptiste Béraca';
  late final List<Widget> pages;
  late final List<String> labels;
  late final List<IconData> icons;
  bool get isAdmin => widget.currentUser['role'] == 'ADM' || widget.currentUser['is_first_admin'] == 1;
  bool get accounting => widget.currentUser['service_access'] == 'Comptabilité';
  @override void initState() { super.initState();
    if (isAdmin) { pages = const [DashboardPage(), MembersPage(), FamiliesPage(), ServicesPage(), AttendancePage(), FinancePage(), GroupsPage(), AnnouncementsPage(), SettingsPage(), BackupPage()]; labels = const ['Tableau de bord','Membres','Familles','Cultes et réunions','Présences','Comptabilité','Classes et groupes','Annonces','Paramètres','Sauvegarde']; icons = const [Icons.dashboard_outlined,Icons.people_alt_outlined,Icons.family_restroom,Icons.church_outlined,Icons.fact_check_outlined,Icons.account_balance_wallet_outlined,Icons.groups_outlined,Icons.campaign_outlined,Icons.settings_outlined,Icons.backup_outlined]; }
    else if (accounting) { pages = const [DashboardPage(), FinancePage(), GroupsPage(), SettingsPage(), BackupPage()]; labels = const ['Tableau de bord','Comptabilité','Classes et groupes','Paramètres','Sauvegarde']; icons = const [Icons.dashboard_outlined,Icons.account_balance_wallet_outlined,Icons.groups_outlined,Icons.settings_outlined,Icons.backup_outlined]; }
    else { pages = const [DashboardPage(), MembersPage(), FamiliesPage(), ServicesPage(), AttendancePage(), GroupsPage(), AnnouncementsPage(), SettingsPage(), BackupPage()]; labels = const ['Tableau de bord','Membres','Familles','Cultes et réunions','Présences','Classes et groupes','Annonces','Paramètres','Sauvegarde']; icons = const [Icons.dashboard_outlined,Icons.people_alt_outlined,Icons.family_restroom,Icons.church_outlined,Icons.fact_check_outlined,Icons.groups_outlined,Icons.campaign_outlined,Icons.settings_outlined,Icons.backup_outlined]; }
  }

  Future<void> loadChurchName() async {
    final rows = await AppDatabase.instance.query('app_settings', where: 'key = ?', whereArgs: ['church_name']);
    if (rows.isNotEmpty && mounted) setState(() => churchName = rows.first['value'] as String);
  }
  @override
  void didChangeDependencies() { super.didChangeDependencies(); loadChurchName(); }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 850;
      return Scaffold(
        appBar: AppBar(
          actions: [Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Center(child: Text(isAdmin ? 'ADM' : (accounting ? 'Comptabilité' : 'Services')))), IconButton(tooltip: 'Déconnexion', onPressed: widget.onLogout, icon: const Icon(Icons.logout))],
          title: Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.church, color: navy)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MBB', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(churchName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal), overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),
        body: Row(children: [
          if (wide) NavigationRail(
            selectedIndex: selected, onDestinationSelected: (v) => setState(() => selected = v),
            labelType: NavigationRailLabelType.all,
            destinations: List.generate(labels.length, (i) => NavigationRailDestination(icon: Icon(icons[i]), label: Text(labels[i]))),
          ),
          Expanded(child: IndexedStack(index: selected, children: pages)),
        ]),
        bottomNavigationBar: wide ? null : NavigationBar(
          selectedIndex: selected > 4 ? 0 : selected,
          onDestinationSelected: (v) => setState(() => selected = v == 4 ? pages.length - 1 : v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Accueil'),
            NavigationDestination(icon: Icon(Icons.people_alt_outlined), label: 'Membres'),
            NavigationDestination(icon: Icon(Icons.fact_check_outlined), label: 'Présences'),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Finances'),
            NavigationDestination(icon: Icon(Icons.menu), label: 'Menu'),
          ],
        ),
        floatingActionButton: !wide && selected == 0 ? FloatingActionButton.extended(
          onPressed: () => setState(() => selected = 1), icon: const Icon(Icons.person_add_alt_1), label: const Text('Ajouter membre'),
        ) : null,
      );
    });
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}
class _DashboardPageState extends State<DashboardPage> {
  Future<Map<String, dynamic>> stats() async {
    final db = AppDatabase.instance;
    return {
      'members': await db.count('members'),
      'families': await db.count('families'),
      'services': await db.count('services'),
      'income': await db.financeTotal('Recette'),
      'expenses': await db.financeTotal('Dépense'),
    };
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: stats(), builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final s = snap.data!;
      final income = s['income'] as double; final expenses = s['expenses'] as double;
      return RefreshIndicator(onRefresh: () async { setState(() {}); await stats(); }, child: ListView(
        padding: const EdgeInsets.all(18), children: [
          Text('Bienvenue dans MBB', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const Text('Gestion de votre église, même sans internet.'),
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 12, children: [
            StatCard(title: 'Membres', value: '${s['members']}', icon: Icons.people, color: navy),
            StatCard(title: 'Familles', value: '${s['families']}', icon: Icons.family_restroom, color: teal),
            StatCard(title: 'Cultes / réunions', value: '${s['services']}', icon: Icons.church, color: Colors.deepPurple),
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
          const SizedBox(height: 12),
          const Card(child: ListTile(leading: Icon(Icons.cloud_off, color: teal), title: Text('Mode hors ligne'), subtitle: Text('Les informations sont conservées dans une base SQLite locale sur cet appareil.'))),
          const SizedBox(height: 8),
          Text('Note : pour transférer les données entre appareils, utilisez Sauvegarde et restaurez le fichier sur l’autre appareil.', style: Theme.of(context).textTheme.bodySmall),
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
  const MembersPage({super.key});
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
        const SizedBox(height: 10), DropdownButtonFormField<String>(value: gender.isEmpty ? null : gender, decoration: const InputDecoration(labelText: 'Sexe'), items: const [DropdownMenuItem(value: 'Femme', child: Text('Femme')), DropdownMenuItem(value: 'Homme', child: Text('Homme')), DropdownMenuItem(value: 'Autre', child: Text('Autre'))], onChanged: (v) => refresh(() => gender = v ?? '')),
        const SizedBox(height: 10), DropdownButtonFormField<int?>(value: familyId, decoration: const InputDecoration(labelText: 'Famille'), items: [const DropdownMenuItem<int?>(value: null, child: Text('Aucune famille')), ...families.map((f) => DropdownMenuItem<int?>(value: f['id'] as int, child: Text('${f['name']}')))], onChanged: (v) => refresh(() => familyId = v)),
        const SizedBox(height: 10), DropdownButtonFormField<int?>(value: sundayClassId, decoration: const InputDecoration(labelText: 'Classe d’école du dimanche'), items: [const DropdownMenuItem<int?>(value: null, child: Text('Aucune classe sélectionnée')), ...groups.where((g) => '${g['item_type']}'.toLowerCase().contains('classe') || '${g['item_type']}'.toLowerCase().contains('école')).map((g) => DropdownMenuItem<int?>(value: g['id'] as int, child: Text('${g['name']}')))], onChanged: (v) => refresh(() => sundayClassId = v)),
        const SizedBox(height: 10), DropdownButtonFormField<String>(value: role.isEmpty ? null : role, decoration: const InputDecoration(labelText: 'Rôle dans l’église'), items: const [DropdownMenuItem(value: 'Pasteur', child: Text('Pasteur')), DropdownMenuItem(value: 'Diacre', child: Text('Diacre')), DropdownMenuItem(value: 'Responsable', child: Text('Responsable')), DropdownMenuItem(value: 'Membre', child: Text('Membre')), DropdownMenuItem(value: 'Autre', child: Text('Autre'))], onChanged: (v) => refresh(() => role = v ?? '')),
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
            trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'edit') _memberForm(member: r); if (v == 'delete') remove(r); }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Modifier')), PopupMenuItem(value: 'delete', child: Text('Supprimer'))])));
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

class FinancePage extends StatefulWidget { const FinancePage({super.key}); @override State<FinancePage> createState() => _FinancePageState(); }
class _FinancePageState extends State<FinancePage> {
  Future<void> add(String kind) async => showFormDialog(context, kind == 'Recette' ? 'Ajouter une recette' : 'Ajouter une dépense', [
    const FieldSpec('category', 'Catégorie', required: true), FieldSpec('amount', 'Montant HTG', required: true, numeric: true),
    FieldSpec('transaction_date', 'Date (AAAA-MM-JJ)', required: true, initial: today()), const FieldSpec('description', 'Description'),
  ], (v) async {
    final amount = double.tryParse(v['amount']!.replaceAll(',', '.'));
    if (amount == null || amount <= 0) { if (mounted) showMessage(context, 'Entrez un montant positif valide.'); return; }
    await AppDatabase.instance.insert('transactions', {...v, 'amount': amount, 'kind': kind, 'created_at': nowIso()});
    await AppDatabase.instance.log('CREATE_TRANSACTION', '$kind ${v['category']} $amount');
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
          title: Text('${r['category']} — ${money.format(amount)}'), subtitle: Text('${r['transaction_date']} · ${r['description']}'), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { if (await confirmDelete(context, 'cette opération')) { await AppDatabase.instance.delete('transactions', where: 'id = ?', whereArgs: [r['id']]); await AppDatabase.instance.log('DELETE_TRANSACTION', '${r['id']}'); if (mounted) setState(() {}); } })));
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
    TextField(controller: church, decoration: const InputDecoration(labelText: 'Nom de l’église')),
    const SizedBox(height: 12), TextField(controller: app, decoration: const InputDecoration(labelText: 'Nom de l’application affiché dans les paramètres')),
    const SizedBox(height: 12), DropdownButtonFormField<String>(value: language, decoration: const InputDecoration(labelText: 'Langue de l’interface'), items: const [DropdownMenuItem(value: 'Français', child: Text('Français')), DropdownMenuItem(value: 'Kreyòl ayisyen', child: Text('Kreyòl ayisyen'))], onChanged: (v) { if (v != null) setState(() => language = v); }),
    const SizedBox(height: 16), FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Enregistrer')),
    const SizedBox(height: 12), const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('Base de données locale'), subtitle: Text('SQLite est stockée dans le dossier privé de l’application. Désinstaller l’application peut supprimer les données locales : faites des sauvegardes régulièrement.'))),
  ]);
}

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});
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
      final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Restaurer une sauvegarde ?'), content: const Text('Cette opération remplace la base locale actuelle. Exportez d’abord une copie de sécurité.'), actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restaurer')),
      ]));
      if (confirm != true) return;
      final source = File(picked.files.single.path!);
      final destination = await _databasePath();
      final db = await AppDatabase.instance.database;
      await db.close();
      await source.copy(destination);
      if (context.mounted) showMessage(context, 'Base restaurée. Fermez puis rouvrez MBB pour recharger les données.');
    } catch (e) { if (context.mounted) showMessage(context, 'Échec de la restauration : $e'); }
  }
  Future<void> _shareAudit(BuildContext context) async {
    final rows = await AppDatabase.instance.query('audit_logs', orderBy: 'id DESC');
    final csv = StringBuffer('id;date;utilisateur;action;details\n');
    for (final r in rows) { csv.writeln('${r['id']};${r['created_at']};${r['username']};${r['action']};${r['details']}'); }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'MBB_historique.csv'));
    await file.writeAsString(csv.toString());
    await Share.shareXFiles([XFile(file.path)], text: 'Historique MBB');
  }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    Text('Sauvegarde et transfert', style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 8), const Text('Le fichier .db contient la base SQLite de l’application. Conservez-le dans un endroit sûr.'),
    const SizedBox(height: 16),
    Card(child: ListTile(leading: const Icon(Icons.upload_file, color: teal), title: const Text('Exporter la base de données'), subtitle: const Text('Créer une copie complète de la base SQLite.'), trailing: const Icon(Icons.chevron_right), onTap: () => _export(context))),
    Card(child: ListTile(leading: const Icon(Icons.restore, color: navy), title: const Text('Restaurer une base de données'), subtitle: const Text('Remplacer la base locale à partir d’un fichier .db.'), trailing: const Icon(Icons.chevron_right), onTap: () => _import(context))),
    Card(child: ListTile(leading: const Icon(Icons.history), title: const Text('Exporter l’historique des actions'), subtitle: const Text('Partager l’historique au format CSV.'), trailing: const Icon(Icons.chevron_right), onTap: () => _shareAudit(context))),
    const SizedBox(height: 12),
    const Card(child: ListTile(leading: Icon(Icons.warning_amber, color: Colors.orange), title: Text('Important'), subtitle: Text('Le fichier de sauvegarde n’est pas chiffré. Ne le partagez pas publiquement. Le système de comptes et permissions avancées reste à compléter avant un usage sensible en production.'))),
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
