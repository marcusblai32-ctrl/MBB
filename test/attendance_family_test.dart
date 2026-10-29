import 'package:flutter_test/flutter_test.dart';
import 'package:mbb/core/periods.dart';
import 'package:mbb/domain/attendance_logic.dart';
import 'package:mbb/domain/family_report.dart';

AttendanceEntry a(int m, String svc, String d, String s) =>
    AttendanceEntry(memberId: m, serviceName: svc, dateIso: d, status: s);

void main() {
  group('retard automatique', () {
    test('tolérance respectée', () {
      expect(classifyArrival(startTime: '09:00', graceMinutes: 15, arrivalTime: '09:15'), statusPresent);
      expect(classifyArrival(startTime: '09:00', graceMinutes: 15, arrivalTime: '09:16'), statusLate);
      expect(classifyArrival(startTime: '09:00', graceMinutes: 0, arrivalTime: '08:50'), statusPresent);
    });
    test('heure de début invalide ou absente : présent', () {
      expect(classifyArrival(startTime: '', graceMinutes: 15, arrivalTime: '10:00'), statusPresent);
      expect(classifyArrival(startTime: '25:00', graceMinutes: 15, arrivalTime: '10:00'), statusPresent);
    });
    test('2 retards = 1 présence', () {
      expect(equivalentPresences(3, 0), 3);
      expect(equivalentPresences(3, 1), 3);
      expect(equivalentPresences(3, 2), 4);
      expect(equivalentPresences(0, 5), 2);
    });
    test('format du rang', () {
      expect(formatRank(1), '001');
      expect(formatRank(999), '999');
    });
  });

  group('classement de persévérance', () {
    final members = {1: 'Alice', 2: 'Bob', 3: 'Carl', 4: 'Dina'};
    final entries = [
      a(1, 'Culte', '2026-10-04', statusPresent),
      a(1, 'Culte', '2026-10-11', statusPresent),
      a(1, 'Prière', '2026-10-07', statusPresent),
      a(2, 'Culte', '2026-10-04', statusLate),
      a(2, 'Culte', '2026-10-11', statusLate), // 2 retards = 1 présence
      a(3, 'culte ', '2026-10-04', statusPresent), // casse/espaces ignorés
      a(3, 'Culte', '2026-10-11', statusAbsent),
      a(4, 'Culte', '2026-09-27', statusPresent), // hors période
    ];
    final october = ReportPeriod.month(2026, 10);

    test('total de tous les services', () {
      final b = PerseveranceCalculator.rank(entries: entries, members: members, period: october);
      expect(b.ranking.map((m) => m.name), ['Alice', 'Carl', 'Bob', 'Dina']);
      expect(b.ranking.first.score, 3);
      expect(b.ranking.first.rankLabel, '001');
      // Bob (1 présence équivalente) et Carl (1 présence) : même score, mais
      // Carl a une vraie présence, donc Carl passe avant Bob.
      expect(b.totalPresents, 4);
      expect(b.totalLates, 2);
      expect(b.totalAbsents, 1);
    });
    test('par service séparément', () {
      final c = PerseveranceCalculator.rank(entries: entries, members: members, period: october, serviceName: 'Culte');
      expect(c.ranking.first.name, 'Alice');
      expect(c.ranking.first.score, 2);
      final p = PerseveranceCalculator.rank(entries: entries, members: members, period: october, serviceName: 'Prière');
      expect(p.totalPresents, 1);
      expect(p.ranking.last.rank, 2); // quatre membres, trois à zéro : rang partagé
    });
    test('semaine et année', () {
      final week = PerseveranceCalculator.rank(entries: entries, members: members,
          period: ReportPeriod.weekOf(DateTime(2026, 10, 4)));
      expect(week.totalPresents + week.totalLates + week.totalAbsents, greaterThan(0));
      final year = PerseveranceCalculator.rank(entries: entries, members: members, period: ReportPeriod.year(2026));
      expect(year.ranking.firstWhere((m) => m.name == 'Dina').presents, 1);
    });
    test('noms de services sans doublon', () {
      expect(PerseveranceCalculator.serviceNames(entries), ['Culte', 'Prière']);
    });
  });

  group('rapport des familles', () {
    test('toutes les familles, tous les membres, totaux', () {
      final r = FamilyReportBuilder.build([
        {'id': 1, 'name': 'Béraca', 'address': 'Rue 1'},
        {'id': 2, 'name': 'Alexis', 'address': ''},
      ], [
        {'first_name': 'Paul', 'last_name': 'Béraca', 'family_id': 1, 'status': 'Actif'},
        {'first_name': 'Ana', 'last_name': 'Béraca', 'family_id': 1, 'status': 'Actif'},
        {'first_name': 'Luc', 'last_name': 'Alexis', 'family_id': 2, 'status': 'Actif'},
        {'first_name': 'Zoé', 'last_name': 'Seul', 'family_id': null, 'status': 'Actif'},
      ]);
      expect(r.totalFamilies, 2);
      expect(r.totalMembers, 4);
      expect(r.membersInFamilies, 3);
      expect(r.families.first.name, 'Alexis');
      expect(r.families.last.members.map((m) => m.name), ['Ana Béraca', 'Paul Béraca']);
      expect(r.unassigned.single.name, 'Zoé Seul');
    });
    test('aucune donnée', () {
      final r = FamilyReportBuilder.build([], []);
      expect(r.totalFamilies, 0);
      expect(r.totalMembers, 0);
    });
  });
}
