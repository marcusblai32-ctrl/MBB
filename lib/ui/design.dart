import 'package:flutter/material.dart';

/// Système de design MBB : bleu profond + noir, inspiré de l'icône.
/// Toutes les couleurs, espacements et composants viennent d'ici.
class MbbColors {
  const MbbColors._();
  static const ink = Color(0xFF0B1220); // noir bleuté (texte, barre latérale)
  static const deep = Color(0xFF0A2A66); // bleu profond
  static const blue = Color(0xFF0B5BD3); // bleu de l'icône (action principale)
  static const accent = Color(0xFF1E88F5); // bleu vif
  static const sky = Color(0xFFE8F1FE); // fond d'accent clair
  static const canvas = Color(0xFFF3F6FB); // fond des pages
  static const surface = Colors.white;
  static const line = Color(0xFFDDE5F0);
  static const muted = Color(0xFF5B6B84);
  static const success = Color(0xFF12A150);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFD92D20);
  static const sidebar = Color(0xFF0A1A3C);
}

class MbbSpace {
  const MbbSpace._();
  static const xs = 4.0, sm = 8.0, md = 16.0, lg = 24.0, xl = 32.0;
  static const radius = 14.0;
}

const navy = MbbColors.deep;
const teal = MbbColors.accent;

ThemeData buildMbbTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: MbbColors.blue,
    primary: MbbColors.blue,
    secondary: MbbColors.accent,
    surface: MbbColors.surface,
    brightness: Brightness.light,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(MbbSpace.radius));
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: w));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: MbbColors.canvas,
    fontFamily: null,
    textTheme: Typography.blackMountainView.apply(bodyColor: MbbColors.ink, displayColor: MbbColors.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: MbbColors.ink,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: MbbColors.surface,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MbbSpace.radius),
        side: const BorderSide(color: MbbColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: border(MbbColors.line),
      enabledBorder: border(MbbColors.line),
      focusedBorder: border(MbbColors.blue, 2),
      errorBorder: border(MbbColors.danger),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MbbColors.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MbbColors.blue,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: MbbColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: MbbColors.blue,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MbbColors.ink,
      indicatorColor: MbbColors.blue,
      labelTextStyle: WidgetStatePropertyAll(const TextStyle(color: Colors.white, fontSize: 11)),
      iconTheme: WidgetStateProperty.resolveWith((s) =>
          IconThemeData(color: s.contains(WidgetState.selected) ? Colors.white : const Color(0xFF9FB3D6))),
    ),
    dialogTheme: DialogThemeData(shape: shape, backgroundColor: Colors.white),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: MbbColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    listTileTheme: const ListTileThemeData(iconColor: MbbColors.blue),
    dividerTheme: const DividerThemeData(color: MbbColors.line, space: 1),
  );
}

/// En-tête de page : titre, sous-titre et actions éventuelles.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, MbbSpace.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: MbbColors.ink)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(subtitle!, style: const TextStyle(color: MbbColors.muted)),
                ),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Carte de section avec titre.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.icon});
  final String title;
  final Widget child;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(MbbSpace.md + 2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, color: MbbColors.blue, size: 20), const SizedBox(width: 8)],
              Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: MbbSpace.md - 4),
            child,
          ]),
        ),
      );
}

/// Indicateur chiffré à fond dégradé bleu.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.title, required this.value, required this.icon, required this.color});
  final String title, value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 230,
        child: Container(
          padding: const EdgeInsets.all(MbbSpace.md + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MbbSpace.radius + 2),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(color, Colors.white, .12)!, Color.lerp(color, MbbColors.ink, .35)!],
            ),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
              ]),
            ),
          ]),
        ),
      );
}

/// Pastille de statut (Présent, Retard, Absent…).
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, this.color, {super.key});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}

/// État vide soigné.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(MbbSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(color: MbbColors.sky, shape: BoxShape.circle),
              child: Icon(icon, size: 34, color: MbbColors.blue),
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: MbbColors.muted)),
          ]),
        ),
      );
}

/// Barre latérale sombre (bureau) avec pastille bleue sur l'élément actif.
class SideNav extends StatelessWidget {
  const SideNav({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.header,
    required this.footer,
  });
  final List<({String label, IconData icon})> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final Widget header, footer;
  @override
  Widget build(BuildContext context) => Container(
        width: 248,
        color: MbbColors.sidebar,
        child: SafeArea(
          child: Column(children: [
            header,
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), children: [
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: i == selected ? MbbColors.blue : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onSelect(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(children: [
                            Icon(items[i].icon, size: 20, color: i == selected ? Colors.white : const Color(0xFF9FB3D6)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(items[i].label,
                                  style: TextStyle(
                                      color: i == selected ? Colors.white : const Color(0xFFC9D6EE),
                                      fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500)),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            footer,
          ]),
        ),
      );
}
