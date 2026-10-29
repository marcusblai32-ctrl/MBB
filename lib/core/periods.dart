enum PeriodKind { daily, weekly, monthly, yearly, custom }

const frenchMonths = [
  'Janvier',
  'Fevrier',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Aout',
  'Septembre',
  'Octobre',
  'Novembre',
  'Decembre',
];

const frenchMonthsAccented = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Période de rapport. Les bornes `start` et `end` sont INCLUSES et sans heure.
/// Les dates sont stockées en base au format AAAA-MM-JJ, donc
/// `date BETWEEN startIso AND endIso` ne crée ni omission ni doublon.
class ReportPeriod {
  ReportPeriod._(this.kind, this.start, this.end);

  final PeriodKind kind;
  final DateTime start;
  final DateTime end;

  factory ReportPeriod.day(DateTime d) {
    final s = dateOnly(d);
    return ReportPeriod._(PeriodKind.daily, s, s);
  }

  /// Semaine ISO : du lundi au dimanche contenant [d].
  factory ReportPeriod.weekOf(DateTime d) {
    final s = DateTime(
      d.year,
      d.month,
      d.day - (d.weekday - DateTime.monday),
    );

    return ReportPeriod._(
      PeriodKind.weekly,
      s,
      DateTime(s.year, s.month, s.day + 6),
    );
  }

  factory ReportPeriod.month(int year, int month) {
    return ReportPeriod._(
      PeriodKind.monthly,
      DateTime(year, month, 1),
      DateTime(year, month + 1, 0),
    );
  }

  factory ReportPeriod.year(int year) => ReportPeriod._(
        PeriodKind.yearly,
        DateTime(year, 1, 1),
        DateTime(year, 12, 31),
      );

  factory ReportPeriod.custom(DateTime a, DateTime b) {
    final s = dateOnly(a);
    final e = dateOnly(b);

    if (e.isBefore(s)) {
      throw ArgumentError('La date de fin précède la date de début.');
    }

    return ReportPeriod._(PeriodKind.custom, s, e);
  }

  String get startIso => isoDate(start);

  String get endIso => isoDate(end);

  int get dayCount {
    // Calcul en jours calendaires, insensible aux changements d'heure.
    final a = DateTime.utc(start.year, start.month, start.day);
    final b = DateTime.utc(end.year, end.month, end.day);

    return b.difference(a).inDays + 1;
  }

  bool contains(String iso) =>
      iso.compareTo(startIso) >= 0 && iso.compareTo(endIso) <= 0;

  /// Période précédente de même nature (pour les comparaisons).
  ReportPeriod previous() {
    switch (kind) {
      case PeriodKind.daily:
        return ReportPeriod.day(
          DateTime(start.year, start.month, start.day - 1),
        );

      case PeriodKind.weekly:
        return ReportPeriod.weekOf(
          DateTime(start.year, start.month, start.day - 7),
        );

      case PeriodKind.monthly:
        return ReportPeriod.month(start.year, start.month - 1);

      case PeriodKind.yearly:
        return ReportPeriod.year(start.year - 1);

      case PeriodKind.custom:
        final n = dayCount;
        final pe = DateTime(start.year, start.month, start.day - 1);
        final ps = DateTime(pe.year, pe.month, pe.day - (n - 1));

        return ReportPeriod._(PeriodKind.custom, ps, pe);
    }
  }

  String get kindTitle => switch (kind) {
        PeriodKind.daily => 'Rapport journalier',
        PeriodKind.weekly => 'Rapport hebdomadaire',
        PeriodKind.monthly => 'Rapport mensuel',
        PeriodKind.yearly => 'Rapport annuel',
        PeriodKind.custom => 'Rapport sur période personnalisée',
      };

  static String _fr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String get label => switch (kind) {
        PeriodKind.daily => 'Journée du ${_fr(start)}',
        PeriodKind.weekly => 'Semaine du ${_fr(start)} au ${_fr(end)}',
        PeriodKind.monthly =>
          '${frenchMonthsAccented[start.month - 1]} ${start.year}',
        PeriodKind.yearly => 'Année ${start.year}',
        PeriodKind.custom => 'Du ${_fr(start)} au ${_fr(end)}',
      };

  /// Chemin d'archivage : `Bureau/année/mois/`
  /// (cf. cahier des charges §9.1).
  String archiveFolder(String bureauFolder) =>
      '$bureauFolder/${start.year}/${frenchMonths[start.month - 1]}';

  String get fileStem => switch (kind) {
        PeriodKind.daily => 'Journalier_$startIso',
        PeriodKind.weekly => 'Hebdomadaire_${startIso}_au_$endIso',
        PeriodKind.monthly =>
          'Mensuel_${start.year}-${start.month.toString().padLeft(2, '0')}',
        PeriodKind.yearly => 'Annuel_${start.year}',
        PeriodKind.custom => 'Personnalise_${startIso}_au_$endIso',
      };
}