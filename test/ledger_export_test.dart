import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mbb/core/money.dart';
import 'package:mbb/core/periods.dart';
import 'package:mbb/data/export_format.dart';
import 'package:mbb/domain/ledger.dart';

LedgerEntry e(String uid, EntryKind k, String cat, String date, int cents,
        {bool voided = false}) =>
    LedgerEntry(uid: uid, reference: 'R-$uid', kind: k, category: cat,
        dateIso: date, description: '', amount: Money(cents), voided: voided);

void main() {
  final all = [
    e('1', EntryKind.recette, 'Dîmes', '2025-12-31', 100000),
    e('2', EntryKind.depense, 'Loyer', '2025-12-31', 30000),
    e('3', EntryKind.recette, 'Dîmes', '2026-01-01', 50000),
    e('4', EntryKind.recette, 'Offrandes', '2026-01-15', 25050),
    e('5', EntryKind.depense, 'Loyer', '2026-01-31', 20000),
    e('6', EntryKind.recette, 'Dons', '2026-01-20', 99999, voided: true),
    e('7', EntryKind.recette, 'Dîmes', '2026-02-01', 70000),
  ];

  test('rapport mensuel : ouverture, totaux, clôture', () {
    final r = LedgerCalculator.build(all, ReportPeriod.month(2026, 1));
    expect(r.opening, const Money(70000));
    expect(r.income, const Money(75050));
    expect(r.expenses, const Money(20000));
    expect(r.closing, const Money(125050));
    expect(r.closing, r.opening + r.income - r.expenses);
    expect(r.voidedEntries.single.uid, '6');
    expect(r.incomeByCategory.first.category, 'Dîmes');
  });

  test('les écritures annulées ne comptent pas, y compris dans l’ouverture', () {
    final r = LedgerCalculator.build(all, ReportPeriod.month(2026, 2));
    expect(r.opening, const Money(125050));
    expect(r.closing, const Money(195050));
  });

  test('périodes adjacentes : aucune écriture omise ni comptée deux fois', () {
    final jan = LedgerCalculator.build(all, ReportPeriod.month(2026, 1));
    final feb = LedgerCalculator.build(all, ReportPeriod.month(2026, 2));
    expect(feb.opening, jan.closing);
  });

  test('période vide : rapport cohérent, sans erreur', () {
    final r = LedgerCalculator.build(all, ReportPeriod.day(DateTime(2026, 6, 6)));
    expect(r.isEmpty, isTrue);
    expect(r.opening, r.closing);
    final none = LedgerCalculator.build([], ReportPeriod.year(2026));
    expect(none.closing, Money.zero);
  });

  test('solde initial pris en compte', () {
    final r = LedgerCalculator.build([], ReportPeriod.year(2026),
        initialBalance: const Money(5000));
    expect(r.closing, const Money(5000));
  });

  group('export / import', () {
    ExchangeTx tx(String uid, {int cents = 1000, String ref = 'R1'}) => ExchangeTx(
        uid: uid, reference: ref, kind: 'recette', category: 'Dons',
        dateIso: '2026-01-01', description: '', amountCents: cents, voided: false);

    test('enveloppe valide, puis altérée', () {
      final env = buildEnvelope(bureau: 'Comptabilite', generatedAt: DateTime.utc(2026),
          appVersion: '1.0.0', data: {'transactions': [tx('a').toJson()]});
      final raw = jsonEncode(env);
      expect(validateEnvelope(raw, expectedBureau: 'Comptabilite').ok, isTrue);
      expect(validateEnvelope(raw, expectedBureau: 'Cartes_Annonces').ok, isFalse);
      final tampered = raw.replaceFirst('1000', '9000');
      expect(validateEnvelope(tampered, expectedBureau: 'Comptabilite').ok, isFalse);
      expect(validateEnvelope('{pas du json', expectedBureau: 'Comptabilite').ok, isFalse);
      expect(validateEnvelope('[]', expectedBureau: 'Comptabilite').ok, isFalse);
    });

    test('version future refusée', () {
      final env = buildEnvelope(bureau: 'Comptabilite', generatedAt: DateTime.utc(2026),
          appVersion: '9', data: {'transactions': []});
      env['version'] = 99;
      expect(validateEnvelope(jsonEncode(env), expectedBureau: 'Comptabilite').ok, isFalse);
    });

    test('plan : ajout, doublon identique, conflit, invalide', () {
      final existing = [tx('a'), tx('b', ref: 'R2')];
      final plan = planImport([
        tx('a').toJson(),                       // doublon identique
        tx('b', cents: 5, ref: 'R2').toJson(),  // même uid, contenu différent
        tx('c', ref: 'R3').toJson(),            // nouveau
        tx('d', ref: 'R1').toJson(),            // référence déjà prise
        {'uid': 'x'},                           // invalide
        'n’importe quoi',                       // invalide
      ], existing);
      expect(plan.toAdd.map((t) => t.uid), ['c']);
      expect(plan.identicalDuplicates.length, 1);
      expect(plan.conflicts.length, 2);
      expect(plan.invalid.length, 2);
      expect(plan.hasBlockingIssues, isTrue);
    });

    test('montant négatif ou nul invalide', () {
      final bad = tx('z').toJson()..['amountCents'] = 0;
      expect(planImport([bad], []).invalid.length, 1);
    });
  });
}
