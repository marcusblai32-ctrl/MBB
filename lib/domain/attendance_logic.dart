import '../core/periods.dart';

const statusPresent = 'Présent';
const statusLate = 'Retard';
const statusAbsent = 'Absent';

int? _minutesOf(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

String formatHm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Statut automatique d'une arrivée : « Retard » si l'heure d'arrivée dépasse
/// l'heure de début du service + la tolérance définie dans les paramètres.
/// Sans heure de début valide, la personne est considérée présente.
String classifyArrival({
  required String startTime,
  required int graceMinutes,
  required String arrivalTime,
}) {
  final s = _minutesOf(startTime), a = _minutesOf(arrivalTime);
  if (s == null || a == null) return statusPresent;
  return a > s + graceMinutes ? statusLate : statusPresent;
}

/// Règle de persévérance : 2 retards = 1 présence.
int equivalentPresences(int presents, int lates) => presents + lates ~/ 2;

String formatRank(int rank) => rank.toString().padLeft(3, '0');

String serviceKeyOf(String title) => title.trim().toLowerCase();

class AttendanceEntry {
  const AttendanceEntry({
    required this.memberId,
    required this.serviceName,
    required this.dateIso,
    required this.status,
  });
  final int memberId;
  final String serviceName, dateIso, status;
}

class MemberScore {
  MemberScore(this.memberId, this.name);
  final int memberId;
  final String name;
  int presents = 0, lates = 0, absents = 0;
  int rank = 0;
  int get score => equivalentPresences(presents, lates);
  String get rankLabel => formatRank(rank);
}

class PerseveranceBoard {
  PerseveranceBoard(this.ranking);
  final List<MemberScore> ranking;
  int get totalPresents => ranking.fold(0, (s, m) => s + m.presents);
  int get totalLates => ranking.fold(0, (s, m) => s + m.lates);
  int get totalAbsents => ranking.fold(0, (s, m) => s + m.absents);
  int get totalScore => ranking.fold(0, (s, m) => s + m.score);
}

class PerseveranceCalculator {
  const PerseveranceCalculator._();

  /// Noms des services présents dans les données (sans doublon de casse).
  static List<String> serviceNames(List<AttendanceEntry> entries) {
    final seen = <String, String>{};
    for (final e in entries) {
      seen.putIfAbsent(serviceKeyOf(e.serviceName), () => e.serviceName.trim());
    }
    final names = seen.values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  /// Classement décroissant : le plus de présences équivalentes = rang 001.
  /// [serviceName] null = total de tous les services. Les membres sans aucune
  /// présence sont classés en bas. À égalité (points et présences), même rang.
  static PerseveranceBoard rank({
    required List<AttendanceEntry> entries,
    required Map<int, String> members,
    required ReportPeriod period,
    String? serviceName,
  }) {
    final scores = {for (final e in members.entries) e.key: MemberScore(e.key, e.value)};
    final wanted = serviceName == null ? null : serviceKeyOf(serviceName);
    for (final e in entries) {
      final s = scores[e.memberId];
      if (s == null || !period.contains(e.dateIso)) continue;
      if (wanted != null && serviceKeyOf(e.serviceName) != wanted) continue;
      switch (e.status) {
        case statusPresent:
          s.presents++;
        case statusLate:
          s.lates++;
        case statusAbsent:
          s.absents++;
      }
    }
    final list = scores.values.toList()
      ..sort((a, b) {
        var c = b.score.compareTo(a.score);
        if (c != 0) return c;
        c = b.presents.compareTo(a.presents);
        if (c != 0) return c;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    for (var i = 0; i < list.length; i++) {
      final tie = i > 0 && list[i].score == list[i - 1].score && list[i].presents == list[i - 1].presents;
      list[i].rank = tie ? list[i - 1].rank : i + 1;
    }
    return PerseveranceBoard(list);
  }
}
