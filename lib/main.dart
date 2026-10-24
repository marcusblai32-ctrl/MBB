import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MbbApp());
}

const navy = Color(0xFF092B50);
const blue = Color(0xFF1261B0);
const teal = Color(0xFF168A9B);
const background = Color(0xFFF3F6FA);

class MbbApp extends StatefulWidget {
  const MbbApp({super.key});
  @override
  State<MbbApp> createState() => _MbbAppState();
}

class _MbbAppState extends State<MbbApp> {
  String appName = 'MBB';
  String churchName = 'Mission Baptiste Béraca';
  String logoPath = '';
  Color primary = navy;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      appName = prefs.getString('appName') ?? 'MBB';
      churchName = prefs.getString('churchName') ?? 'Mission Baptiste Béraca';
      logoPath = prefs.getString('logoPath') ?? '';
      primary = Color(prefs.getInt('primaryColor') ?? navy.value);
      loading = false;
    });
  }

  Future<void> _saveBranding(String app, String church, Color color, String logo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appName', app);
    await prefs.setString('churchName', church);
    await prefs.setInt('primaryColor', color.value);
    await prefs.setString('logoPath', logo);
    setState(() {
      appName = app;
      churchName = church;
      primary = color;
      logoPath = logo;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: primary),
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: navy),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: MbbShell(
        appName: appName,
        churchName: churchName,
        logoPath: logoPath,
        primary: primary,
        onBrandingSaved: _saveBranding,
      ),
    );
  }
}

class MbbShell extends StatefulWidget {
  final String appName;
  final String churchName;
  final String logoPath;
  final Color primary;
  final Future<void> Function(String, String, Color, String) onBrandingSaved;
  const MbbShell({super.key, required this.appName, required this.churchName, required this.logoPath, required this.primary, required this.onBrandingSaved});

  @override
  State<MbbShell> createState() => _MbbShellState();
}

class _MbbShellState extends State<MbbShell> {
  int selected = 0;
  final sections = const [
    ('Tableau de bord', Icons.dashboard_outlined),
    ('Membres et croyants', Icons.people_alt_outlined),
    ('Familles', Icons.groups_outlined),
    ('Services et séances', Icons.event_available_outlined),
    ('Présences', Icons.fact_check_outlined),
    ('Finances', Icons.account_balance_wallet_outlined),
    ('Offrandes', Icons.volunteer_activism_outlined),
    ('Rapports', Icons.assessment_outlined),
    ('Administration', Icons.admin_panel_settings_outlined),
    ('Sauvegardes', Icons.backup_outlined),
    ('Paramètres', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = _page();
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: widget.primary, borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.menu_book_rounded, color: Colors.white)),
          const SizedBox(width: 10),
          Flexible(child: Text('${widget.appName} · ${widget.churchName}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        ]),
        actions: const [
          Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Row(children: [Icon(Icons.account_circle_outlined), SizedBox(width: 6), Text('Administrateur')])),
        ],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                backgroundColor: navy,
                selectedIndex: selected,
                onDestinationSelected: (i) => setState(() => selected = i),
                labelType: NavigationRailLabelType.all,
                selectedIconTheme: const IconThemeData(color: Colors.white),
                unselectedIconTheme: const IconThemeData(color: Color(0xFFD7E4F3)),
                selectedLabelTextStyle: const TextStyle(color: Colors.white, fontSize: 11),
                unselectedLabelTextStyle: const TextStyle(color: Color(0xFFD7E4F3), fontSize: 11),
                destinations: sections.map((s) => NavigationRailDestination(icon: Icon(s.$2), label: Text(s.$1))).toList(),
              ),
              Expanded(child: body),
            ])
          : body,
      drawer: wide ? null : Drawer(
        child: ListView(children: [
          DrawerHeader(decoration: const BoxDecoration(color: navy), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.menu_book_rounded, color: Colors.white, size: 36),
            const SizedBox(height: 10),
            Text(widget.appName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            Text(widget.churchName, style: const TextStyle(color: Colors.white70)),
          ])),
          ...sections.asMap().entries.map((e) => ListTile(
            leading: Icon(e.value.$2),
            title: Text(e.value.$1),
            selected: selected == e.key,
            onTap: () { setState(() => selected = e.key); Navigator.pop(context); },
          )),
        ]),
      ),
      floatingActionButton: selected == 1 || selected == 2 || selected == 3 || selected == 5
          ? FloatingActionButton(onPressed: () => _addAction(context), child: const Icon(Icons.add))
          : null,
    );
  }

  Widget _page() {
    switch (selected) {
      case 0: return DashboardPage(churchName: widget.churchName);
      case 1: return const GenericListPage(title: 'Membres et croyants', subtitle: 'Rechercher, consulter et gérer les personnes', icon: Icons.people_alt_outlined, rows: ['Jean Baptiste|Membre|12/03/1985', 'Marie Louise|Membre|08/07/1990', 'Pierre Jean|Croyant|15/09/2000', 'Ruth C.|Membre|22/11/1988', 'Samuel Pierre|Membre|03/04/1995']);
      case 2: return const GenericListPage(title: 'Familles', subtitle: 'Regrouper les membres par famille', icon: Icons.groups_outlined, rows: ['Famille Baptiste|5 membres|Active', 'Famille Pierre|4 membres|Active', 'Famille Jean|3 membres|Active']);
      case 3: return const GenericListPage(title: 'Services et séances', subtitle: 'Organiser les cultes et les réunions', icon: Icons.event_available_outlined, rows: ['Culte dominical|Dimanche · 08:00–10:00|Actif', 'Réunion de prière|Mardi · 18:00–19:30|Actif', 'Étude biblique|Mercredi · 18:00–19:30|Actif', 'École dominicale|Dimanche · 10:30–12:00|Actif']);
      case 4: return const AttendancePage();
      case 5: return const FinancePage();
      case 6: return const FinancePage(offeringsOnly: true);
      case 7: return const ReportsPage();
      case 8: return const AdminPage();
      case 9: return const BackupPage();
      default: return BrandingPage(
        appName: widget.appName,
        churchName: widget.churchName,
        logoPath: widget.logoPath,
        primary: widget.primary,
        onSave: widget.onBrandingSaved,
      );
    }
  }

  void _addAction(BuildContext context) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Ajouter un élément'),
      content: Text(selected == 1 ? 'Le formulaire de membre sera ajouté dans le module Membres.' : selected == 2 ? 'Le formulaire de famille sera ajouté dans le module Familles.' : selected == 3 ? 'Le formulaire de service sera ajouté dans le module Services.' : 'Le formulaire financier sera ajouté dans le module Finances.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
    ));
  }
}

class DashboardPage extends StatelessWidget {
  final String churchName;
  const DashboardPage({super.key, required this.churchName});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(22), children: [
    Text('Tableau de bord', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 5),
    Text(churchName, style: const TextStyle(color: Colors.blueGrey)),
    const SizedBox(height: 20),
    Wrap(spacing: 14, runSpacing: 14, children: const [
      MetricCard(title: 'Présents', value: '48', detail: 'Dernière séance', icon: Icons.check_circle_outline, color: Color(0xFF198754)),
      MetricCard(title: 'Absents', value: '12', detail: 'Dernière séance', icon: Icons.person_off_outlined, color: Color(0xFFDC3545)),
      MetricCard(title: 'Retards', value: '5', detail: 'Dernière séance', icon: Icons.schedule, color: Color(0xFFE39A16)),
      MetricCard(title: 'Taux de présence', value: '76%', detail: 'Période sélectionnée', icon: Icons.donut_large, color: blue),
    ]),
    const SizedBox(height: 20),
    Wrap(spacing: 14, runSpacing: 14, children: const [
      SizedBox(width: 340, child: FinanceSummaryCard()),
      SizedBox(width: 340, child: TopAttendanceCard()),
    ]),
    const SizedBox(height: 18),
    const Card(child: Padding(padding: EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Bienvenue dans MBB', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      SizedBox(height: 8),
      Text('Cette interface est la base visuelle de votre logiciel de gestion d’église. Les chiffres affichés sont des exemples de démonstration et ne représentent pas encore des données réelles.'),
    ]))),
  ]);
}

class MetricCard extends StatelessWidget {
  final String title, value, detail;
  final IconData icon;
  final Color color;
  const MetricCard({super.key, required this.title, required this.value, required this.detail, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => SizedBox(width: 205, child: Card(child: Padding(padding: const EdgeInsets.all(17), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(color: Colors.blueGrey)), Icon(icon, color: color)]),
    const SizedBox(height: 12),
    Text(value, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: color)),
    Text(detail, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
  ]))));
}

class FinanceSummaryCard extends StatelessWidget {
  const FinanceSummaryCard({super.key});
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
    Text('Finances · cette semaine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    Divider(height: 24),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Recettes'), Text('125 000 HTG', style: TextStyle(color: Color(0xFF198754), fontWeight: FontWeight.bold))]),
    SizedBox(height: 12),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Dépenses'), Text('68 500 HTG', style: TextStyle(color: Color(0xFFDC3545), fontWeight: FontWeight.bold))]),
    SizedBox(height: 12),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Solde calculé'), Text('56 500 HTG', style: TextStyle(color: blue, fontWeight: FontWeight.bold))]),
  ])));
}

class TopAttendanceCard extends StatelessWidget {
  const TopAttendanceCard({super.key});
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
    Text('Top 5 · présences', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    Divider(height: 24),
    _RankRow(rank: '1', name: 'Jean Baptiste', count: '7'),
    _RankRow(rank: '2', name: 'Marie Louise', count: '7'),
    _RankRow(rank: '3', name: 'Pierre Jean', count: '6'),
    _RankRow(rank: '4', name: 'Samuel Pierre', count: '6'),
    _RankRow(rank: '5', name: 'Ruth C.', count: '5'),
  ])));
}

class _RankRow extends StatelessWidget {
  final String rank, name, count;
  const _RankRow({required this.rank, required this.name, required this.count});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [SizedBox(width: 25, child: Text(rank)), Expanded(child: Text(name)), Text(count, style: const TextStyle(fontWeight: FontWeight.bold))]));
}

class GenericListPage extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final List<String> rows;
  const GenericListPage({super.key, required this.title, required this.subtitle, required this.icon, required this.rows});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(22), children: [
    Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    Text(subtitle, style: const TextStyle(color: Colors.blueGrey)),
    const SizedBox(height: 18),
    TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Rechercher...', suffixIcon: IconButton(onPressed: () {}, icon: const Icon(Icons.filter_list)))),
    const SizedBox(height: 12),
    ...rows.map((row) {
      final parts = row.split('|');
      return Card(child: ListTile(
        leading: CircleAvatar(backgroundColor: const Color(0xFFE5EEF8), child: Icon(icon, color: blue)),
        title: Text(parts.first, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(parts.skip(1).join(' · ')),
        trailing: const Icon(Icons.chevron_right),
      ));
    }),
  ]);
}

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}
class _AttendancePageState extends State<AttendancePage> {
  final statuses = <String, String>{'Jean Baptiste':'Présent', 'Marie Louise':'Présent', 'Pierre Jean':'Absent', 'Ruth C.':'En retard', 'Samuel Pierre':'Présent'};
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(22), children: [
    Text('Gestion des présences', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    const Text('Présences · Culte dominical · Exemple de démonstration'),
    const SizedBox(height: 16),
    const TextField(decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un nom...')),
    const SizedBox(height: 12),
    ...statuses.keys.map((name) => Card(child: ListTile(
      title: Text(name),
      trailing: DropdownButton<String>(
        value: statuses[name],
        items: const ['Présent','Absent','En retard'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: (value) => setState(() => statuses[name] = value!),
      ),
    ))),
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Démo : enregistrement à connecter à la base de données.'))), icon: const Icon(Icons.save_outlined), label: const Text('Enregistrer les présences')),
  ]);
}

class FinancePage extends StatelessWidget {
  final bool offeringsOnly;
  const FinancePage({super.key, this.offeringsOnly = false});
  @override
  Widget build(BuildContext context) {
    final rows = offeringsOnly
      ? const [['27/04/2025','Offrandes','15 000','Recette'], ['20/04/2025','Dîmes','25 000','Recette']]
      : const [['27/04/2025','Offrandes','15 000','Recette'], ['26/04/2025','Sonorisation','4 500','Dépense'], ['24/04/2025','Dîmes','25 000','Recette'], ['20/04/2025','Électricité','7 800','Dépense']];
    return ListView(padding: const EdgeInsets.all(22), children: [
      Text(offeringsOnly ? 'Gestion des offrandes' : 'Gestion financière', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 14),
      Wrap(spacing: 12, runSpacing: 12, children: const [
        MetricCard(title: 'Recettes', value: '125 000', detail: 'HTG · démonstration', icon: Icons.south_west, color: Color(0xFF198754)),
        MetricCard(title: 'Dépenses', value: '68 500', detail: 'HTG · démonstration', icon: Icons.north_east, color: Color(0xFFDC3545)),
        MetricCard(title: 'Solde', value: '56 500', detail: 'HTG · calculé en démo', icon: Icons.account_balance, color: blue),
      ]),
      const SizedBox(height: 16),
      const TextField(decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Catégorie, description ou référence...')),
      const SizedBox(height: 12),
      Card(child: Column(children: [
        const ListTile(title: Text('Date                         Catégorie                       Montant')),
        const Divider(height: 1),
        ...rows.map((r) => ListTile(
          dense: true,
          title: Text('${r[0]}   ·   ${r[1]}'),
          subtitle: Text(r[3]),
          trailing: Text('${r[2]} HTG', style: TextStyle(color: r[3] == 'Recette' ? const Color(0xFF198754) : const Color(0xFFDC3545), fontWeight: FontWeight.bold)),
        )),
      ])),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le formulaire financier sera connecté à SQLite dans la prochaine étape.'))), icon: const Icon(Icons.add), label: const Text('Nouvelle opération')),
    ]);
  }
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(22), children: [
    Text('Rapports et statistiques', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    ...[
      ('Présences', 'Rapport de présences', Icons.fact_check_outlined),
      ('Absences', 'Rapport des absences', Icons.person_off_outlined),
      ('Retards', 'Rapport des retards', Icons.schedule),
      ('Classements', 'Classements par période', Icons.leaderboard_outlined),
      ('Liste des membres', 'Liste complète', Icons.people_alt_outlined),
      ('Rapport financier', 'Recettes, dépenses et solde', Icons.account_balance_wallet_outlined),
    ].map((item) => Card(child: ListTile(leading: Icon(item.$3, color: blue), title: Text(item.$1), subtitle: Text(item.$2), trailing: const Icon(Icons.chevron_right), onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La génération des fichiers Excel, PDF et Word sera ajoutée dans le module Rapports.'))))),
  ]);
}

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(22), children: [
    Text('Administration', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    const Card(child: ListTile(leading: Icon(Icons.manage_accounts_outlined), title: Text('Comptes utilisateurs'), subtitle: Text('À développer : création, désactivation et changement de mot de passe.'))),
    const Card(child: ListTile(leading: Icon(Icons.security_outlined), title: Text('Rôles et permissions'), subtitle: Text('À développer : rôles personnalisés et contrôle de chaque opération.'))),
    const Card(child: ListTile(leading: Icon(Icons.history), title: Text('Journal des opérations'), subtitle: Text('À développer : historique des actions sensibles.'))),
  ]);
}

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(22), children: [
    Text('Sauvegardes', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    const Card(child: ListTile(leading: Icon(Icons.backup_outlined, color: blue), title: Text('Créer une sauvegarde complète'), subtitle: Text('Sauvegarde des données locales de l’église.'))),
    const Card(child: ListTile(leading: Icon(Icons.restore_outlined, color: teal), title: Text('Restaurer une sauvegarde'), subtitle: Text('Importer un fichier de sauvegarde MBB.'))),
    const Card(child: ListTile(leading: Icon(Icons.verified_outlined), title: Text('Vérifier l’intégrité'), subtitle: Text('Validation du format et de la version du fichier.'))),
    const SizedBox(height: 10),
    const Text('Ces actions sont des emplacements d’interface : le système réel de sauvegarde et de restauration doit encore être implémenté et testé.'),
  ]);
}

class BrandingPage extends StatefulWidget {
  final String appName, churchName, logoPath;
  final Color primary;
  final Future<void> Function(String, String, Color, String) onSave;
  const BrandingPage({super.key, required this.appName, required this.churchName, required this.logoPath, required this.primary, required this.onSave});
  @override
  State<BrandingPage> createState() => _BrandingPageState();
}
class _BrandingPageState extends State<BrandingPage> {
  late final TextEditingController appController = TextEditingController(text: widget.appName);
  late final TextEditingController churchController = TextEditingController(text: widget.churchName);
  late Color color = widget.primary;
  String logo = '';
  final colors = const [navy, blue, teal, Color(0xFF6B4E9B), Color(0xFFB87912), Color(0xFF202A38)];
  @override
  void initState() { super.initState(); logo = widget.logoPath; }
  @override
  void dispose() { appController.dispose(); churchController.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(22), children: [
    Text('Personnalisation de l’église', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('Configurez le nom affiché, l’identité de l’église et la couleur principale.'),
    const SizedBox(height: 18),
    Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Identité de l’application', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      const SizedBox(height: 14),
      TextField(controller: appController, decoration: const InputDecoration(labelText: 'Nom affiché de l’application')),
      const SizedBox(height: 12),
      TextField(controller: churchController, decoration: const InputDecoration(labelText: 'Nom de l’église ou organisation')),
      const SizedBox(height: 18),
      const Text('Couleur principale', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, children: colors.map((c) => InkWell(
        onTap: () => setState(() => color = c),
        child: Container(width: 38, height: 38, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: color == c ? Colors.black : Colors.white, width: color == c ? 3 : 1))),
      )).toList()),
      const SizedBox(height: 18),
      const Text('Logo', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 5),
      const Text('La sélection et l’affichage d’un fichier logo seront ajoutés dans une étape suivante.'),
      const SizedBox(height: 18),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: () async {
          final app = appController.text.trim();
          final church = churchController.text.trim();
          if (app.isEmpty || church.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez renseigner les deux noms.')));
            return;
          }
          await widget.onSave(app, church, color, logo);
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Personnalisation enregistrée sur cet appareil.')));
        },
        icon: const Icon(Icons.save_outlined), label: const Text('Enregistrer la personnalisation'),
      )),
      const SizedBox(height: 8),
      const Text('Note : le nom et l’icône natifs sous lesquels l’application est installée nécessitent une reconstruction du paquet.', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
    ]))),
  ]);
}
