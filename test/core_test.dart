import 'package:flutter_test/flutter_test.dart';
import 'package:mbb/core/money.dart';
import 'package:mbb/core/password_hasher.dart';
import 'package:mbb/core/periods.dart';
import 'package:mbb/core/permissions.dart';

void main() {
  group('Money', () {
    test('analyse des saisies', () {
      expect(Money.tryParse('1 250,50'), const Money(125050));
      expect(Money.tryParse('1250.5'), const Money(125050));
      expect(Money.tryParse('300'), const Money(30000));
      expect(Money.tryParse('0,05'), const Money(5));
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('1,234'), isNull);
      expect(Money.tryParse('1,2,3'), isNull);
      expect(Money.tryParse(''), isNull);
    });
    test('formatage français', () {
      expect(const Money(123456789).format(), '1 234 567,89');
      expect(const Money(-5).format(), '-0,05');
      expect(const Money(0).format(), '0,00');
    });
    test('0,1 + 0,2 est exact', () {
      expect(Money.tryParse('0,1')! + Money.tryParse('0,2')!, Money.tryParse('0,3'));
    });
  });

  group('ReportPeriod', () {
    test('semaine ISO lundi-dimanche', () {
      final w = ReportPeriod.weekOf(DateTime(2026, 1, 1)); // jeudi
      expect(w.startIso, '2025-12-29');
      expect(w.endIso, '2026-01-04');
      expect(w.dayCount, 7);
    });
    test('mois, y compris février bissextile', () {
      expect(ReportPeriod.month(2024, 2).endIso, '2024-02-29');
      expect(ReportPeriod.month(2026, 2).endIso, '2026-02-28');
      expect(ReportPeriod.month(2026, 12).endIso, '2026-12-31');
    });
    test('période précédente', () {
      expect(ReportPeriod.month(2026, 1).previous().startIso, '2025-12-01');
      expect(ReportPeriod.year(2026).previous().startIso, '2025-01-01');
      expect(ReportPeriod.day(DateTime(2026, 3, 1)).previous().startIso, '2026-02-28');
      final c = ReportPeriod.custom(DateTime(2026, 3, 10), DateTime(2026, 3, 14));
      expect(c.previous().startIso, '2026-03-05');
      expect(c.previous().endIso, '2026-03-09');
    });
    test('bornes incluses, sans doublon entre périodes adjacentes', () {
      final m1 = ReportPeriod.month(2026, 1), m2 = ReportPeriod.month(2026, 2);
      expect(m1.contains('2026-01-31'), isTrue);
      expect(m2.contains('2026-01-31'), isFalse);
      expect(m2.contains('2026-02-01'), isTrue);
    });
    test('dates inversées rejetées', () {
      expect(() => ReportPeriod.custom(DateTime(2026, 2, 2), DateTime(2026, 2, 1)),
          throwsArgumentError);
    });
    test('dossier d’archivage', () {
      expect(ReportPeriod.month(2026, 2).archiveFolder('Comptabilite'),
          'Comptabilite/2026/Fevrier');
    });
  });

  group('Permissions', () {
    const compAdmin = Principal(userId: 1, username: 'a', bureau: Bureau.comptabilite, role: BureauRole.administrateur);
    const compEmp = Principal(userId: 2, username: 'b', bureau: Bureau.comptabilite, role: BureauRole.employe);
    const cardsAdmin = Principal(userId: 3, username: 'c', bureau: Bureau.cartesAnnonces, role: BureauRole.administrateur);
    const cardsEmp = Principal(userId: 4, username: 'd', bureau: Bureau.cartesAnnonces, role: BureauRole.employe);

    test('aucun accès croisé, même pour un administrateur', () {
      expect(AccessPolicy.can(cardsAdmin, Permission.financeView), isFalse);
      expect(AccessPolicy.can(cardsEmp, Permission.financeRecord), isFalse);
      expect(AccessPolicy.can(compAdmin, Permission.membersView), isFalse);
      expect(AccessPolicy.can(compEmp, Permission.cardsManage), isFalse);
    });
    test('employé limité, administrateur complet dans son bureau', () {
      expect(AccessPolicy.can(compEmp, Permission.financeRecord), isTrue);
      expect(AccessPolicy.can(compEmp, Permission.financeVoid), isFalse);
      expect(AccessPolicy.can(compEmp, Permission.usersManage), isFalse);
      expect(AccessPolicy.can(compAdmin, Permission.financeVoid), isTrue);
      expect(AccessPolicy.can(cardsEmp, Permission.membersDelete), isFalse);
      expect(AccessPolicy.can(cardsAdmin, Permission.membersDelete), isTrue);
    });
    test('compte désactivé ou absent refusé', () {
      const off = Principal(userId: 5, username: 'e', bureau: Bureau.comptabilite, role: BureauRole.administrateur, active: false);
      expect(AccessPolicy.can(off, Permission.financeView), isFalse);
      expect(AccessPolicy.can(null, Permission.financeView), isFalse);
      expect(() => AccessPolicy.require(null, Permission.financeView),
          throwsA(isA<AuthorizationException>()));
    });
  });

  group('PasswordHasher', () {
    test('vecteur de test RFC 7914 (PBKDF2-HMAC-SHA256, c=1)', () {
      final h = PasswordHasher.hash('passwd', iterations: 1, saltBytes: 'salt'.codeUnits);
      expect(h.split(r'$').last,
          '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc');
    });
    test('vérification et rejet', () {
      final h = PasswordHasher.hash('MotDePasse!2026', iterations: 1000);
      expect(PasswordHasher.verify('MotDePasse!2026', h), isTrue);
      expect(PasswordHasher.verify('autre', h), isFalse);
      expect(PasswordHasher.verify('x', 'garbage'), isFalse);
      expect(PasswordHasher.needsRehash(h), isTrue);
    });
    test('deux hachages du même mot de passe diffèrent (sel)', () {
      expect(PasswordHasher.hash('x', iterations: 10), isNot(PasswordHasher.hash('x', iterations: 10)));
    });
  });
}
