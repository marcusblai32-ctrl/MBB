import 'dart:io';

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
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int selected = 0;
  String churchName = 'Mission Baptiste Béraca';
  final pages = const [
    DashboardPage(), MembersPage(), FamiliesPage(), ServicesPage(),
    AttendancePage(), FinancePage(), SettingsPage(), BackupPage(),
  ];
  final labels = const ['Tableau de bord', 'Membres', 'Familles', 'Cultes et réunions', 'Présences', 'Finances', 'Paramètres', 'Sauvegarde'];
  final icons = const [Icons.dashboard_outlined, Icons.people_alt_outlined, Icons.family_restroom, Icons.church_outlined, Icons.fact_check_outlined, Icons.account_balance_wallet_outlined, Icons.settings_outlined, Icons.backup_outlined];

  Future<void> loadChurchName() async {
    final rows = await AppDatabase.instance.query('app_settings', where: 'key = ?', whereArgs: ['church_name']);
    if (rows.isNotEmpty && mounted) setState(() => churchName = rows.first['value'] as String);
  }
  @override
  void initState() { super.initState(); loadChurchName(); }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 850;
      return Scaffold(
        appBar: AppBar(
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
          onDestinationSelected: (v) => setState(() => selected = v),
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

class MembersPage extends StatefulWidget { const MembersPage({super.key}); @override State<MembersPage> createState() => _MembersPageState(); }
class _MembersPageState extends State<MembersPage> {
  String search = '';
  Future<List<Map<String, Object?>>> load() async {
    final rows = await AppDatabase.instance.query('members', orderBy: 'last_name COLLATE NOCASE');
    return rows.where((r) => '${r['first_name']} ${r['last_name']} ${r['phone']}'.toLowerCase().contains(search.toLowerCase())).toList();
  }
  Future<void> add() async {
    await showFormDialog(context, 'Ajouter un membre', const [
      FieldSpec('first_name', 'Prénom', required: true), FieldSpec('last_name', 'Nom', required: true),
      FieldSpec('phone', 'Téléphone'), FieldSpec('email', 'Courriel'), FieldSpec('address', 'Adresse'),
      FieldSpec('gender', 'Sexe (F/M/autre)'), FieldSpec('birth_date', 'Date de naissance (AAAA-MM-JJ)'),
      FieldSpec('notes', 'Notes'),
    ], (v) async {
      await AppDatabase.instance.insert('members', {...v, 'status': 'Actif', 'created_at': nowIso()});
      await AppDatabase.instance.log('CREATE_MEMBER', '${v['first_name']} ${v['last_name']}');
      if (mounted) setState(() {});
    });
  }
  Future<void> edit(Map<String, Object?> r) async {
    await showFormDialog(context, 'Modifier le membre', [
      FieldSpec('first_name', 'Prénom', required: true, initial: '${r['first_name']}'),
      FieldSpec('last_name', 'Nom', required: true, initial: '${r['last_name']}'),
      FieldSpec('phone', 'Téléphone', initial: '${r['phone']}'),
      FieldSpec('email', 'Courriel', initial: '${r['email']}'),
      FieldSpec('address', 'Adresse', initial: '${r['address']}'),
      FieldSpec('gender', 'Sexe', initial: '${r['gender']}'),
      FieldSpec('birth_date', 'Date de naissance', initial: '${r['birth_date']}'),
      FieldSpec('notes', 'Notes', initial: '${r['notes']}'),
    ], (v) async {
      await AppDatabase.instance.update('members', v, where: 'id = ?', whereArgs: [r['id']]);
      await AppDatabase.instance.log('UPDATE_MEMBER', '${r['id']}');
      if (mounted) setState(() {});
    });
  }
  Future<void> remove(Map<String, Object?> r) async {
    final yes = await confirmDelete(context, '${r['first_name']} ${r['last_name']}');
    if (yes) { await AppDatabase.instance.delete('members', where: 'id = ?', whereArgs: [r['id']]); await AppDatabase.instance.log('DELETE_MEMBER', '${r['id']}'); if (mounted) setState(() {}); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    floatingActionButton: FloatingActionButton.extended(onPressed: add, icon: const Icon(Icons.person_add), label: const Text('Ajouter')),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un membre'), onChanged: (v) => setState(() => search = v)),
      const SizedBox(height: 10),
      Expanded(child: FutureBuilder<List<Map<String, Object?>>>(future: load(), builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const Center(child: Text('Aucun membre. Appuyez sur Ajouter pour commencer.'));
        return ListView.builder(itemCount: rows.length, itemBuilder: (context, i) {
          final r = rows[i];
          return Card(child: ListTile(leading: CircleAvatar(backgroundColor: navy, child: Text('${r['first_name']}'.isNotEmpty ? '${r['first_name']}'.substring(0, 1).toUpperCase() : '?', style: const TextStyle(color: Colors.white))),
            title: Text('${r['first_name']} ${r['last_name']}'), subtitle: Text('${r['phone'] ?? ''}  ${r['email'] ?? ''}'),
            trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'edit') edit(r); if (v == 'delete') remove(r); }, itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Modifier')), PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ])));
        });
      })),
    ])),
  );
}


class FamiliesPage extends StatefulWidget {
  const FamiliesPage({super.key});
  @override
  State<FamiliesPage> createState() => _FamiliesPageState();
}

class _FamiliesPageState extends State<FamiliesPage> {
  Future<void> add() async {
    await showFormDialog(context, 'Ajouter une famille', const [
      FieldSpec('name', 'Nom de la famille', required: true),
      FieldSpec('address', 'Adresse'),
      FieldSpec('notes', 'Notes'),
    ], (v) async {
      await AppDatabase.instance.insert('families', {
        ...v,
        'created_at': nowIso(),
      });
      await AppDatabase.instance.log('CREATE_FAMILY', v['name'] ?? '');
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: add,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter famille'),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: AppDatabase.instance.query('families', orderBy: 'name'),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return const Center(child: Text('Aucune famille enregistrée.'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: rows.map((r) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.family_restroom, color: teal),
                  title: Text('${r['name']}'),
                  subtitle: Text('${r['address']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final confirmed = await confirmDelete(context, '${r['name']}');
                      if (!confirmed) return;
                      await AppDatabase.instance.delete(
                        'families',
                        where: 'id = ?',
                        whereArgs: [r['id']],
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});
  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  Future<void> add() async {
    await showFormDialog(context, 'Ajouter un culte ou une réunion', [
      const FieldSpec('title', 'Nom du service', required: true),
      FieldSpec('service_date', 'Date (AAAA-MM-JJ)', required: true, initial: today()),
      const FieldSpec('notes', 'Notes'),
    ], (v) async {
      await AppDatabase.instance.insert('services', v);
      await AppDatabase.instance.log('CREATE_SERVICE', v['title'] ?? '');
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: add,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter service'),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: AppDatabase.instance.query('services', orderBy: 'service_date DESC'),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return const Center(child: Text('Aucun culte ou réunion enregistré.'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: rows.map((r) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.church, color: navy),
                  title: Text('${r['title']}'),
                  subtitle: Text("${r['service_date']} — ${r['notes']}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final confirmed = await confirmDelete(context, '${r['title']}');
                      if (!confirmed) return;
                      await AppDatabase.instance.delete(
                        'services',
                        where: 'id = ?',
                        whereArgs: [r['id']],
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
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
    const SizedBox(height: 12), DropdownButtonFormField<String>(initialValue: language, decoration: const InputDecoration(labelText: 'Langue de l’interface'), items: const [DropdownMenuItem(value: 'Français', child: Text('Français')), DropdownMenuItem(value: 'Kreyòl ayisyen', child: Text('Kreyòl ayisyen'))], onChanged: (v) { if (v != null) setState(() => language = v); }),
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
      // Vérifier que la page existe encore après l'opération asynchrone.
      if (!context.mounted) return;
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
      if (context.mounted) { showMessage(context, 'Base restaurée. Fermez puis rouvrez MBB pour recharger les données.'); }
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
