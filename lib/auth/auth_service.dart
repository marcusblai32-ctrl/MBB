import '../core/password_hasher.dart';
import '../core/permissions.dart';
import '../database/app_database.dart';

/// Authentification et gestion des comptes. Toutes les opérations sensibles
/// vérifient les droits ici, dans la logique métier, et pas dans l'interface.
class AuthService {
  const AuthService._();

  static const minPasswordLength = 8;

  static String labelOf(Bureau b) => b == Bureau.comptabilite
      ? 'Comptabilité'
      : 'Services des cartes et annonces';

  static Bureau bureauFromLabel(String label) => label == 'Comptabilité'
      ? Bureau.comptabilite
      : Bureau.cartesAnnonces;

  /// « ADM » (ancien rôle) devient administrateur DU SEUL bureau du compte.
  static Principal principalFrom(Map<String, Object?> row) => Principal(
        userId: row['id'] as int,
        username: '${row['username']}',
        bureau: bureauFromLabel('${row['service_access']}'),
        role: row['role'] == 'ADM'
            ? BureauRole.administrateur
            : BureauRole.employe,
        active: row['active'] == 1,
      );

  static String? validatePassword(String p) => p.length < minPasswordLength
      ? 'Le mot de passe doit contenir au moins $minPasswordLength caractères.'
      : null;

  static String normalizeUsername(String u) => u.trim().toLowerCase();

  static Future<Principal?> login(String username, String password) async {
    final db = AppDatabase.instance;
    final rows = await db.query('users',
        where: 'username = ? AND active = 1',
        whereArgs: [normalizeUsername(username)]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final stored = '${row['password_hash']}';
    var ok = false;
    if (stored.startsWith(r'pbkdf2$')) {
      ok = PasswordHasher.verify(password, stored);
      if (ok && PasswordHasher.needsRehash(stored)) {
        await db.update('users', {'password_hash': PasswordHasher.hash(password)},
            where: 'id = ?', whereArgs: [row['id']]);
      }
    } else if (PasswordHasher.verifyLegacy(password, '${row['salt']}', stored)) {
      ok = true; // migration automatique vers PBKDF2
      await db.update(
          'users', {'password_hash': PasswordHasher.hash(password), 'salt': ''},
          where: 'id = ?', whereArgs: [row['id']]);
    }
    if (!ok) {
      await db.log('LOGIN_FAILED', '${row['username']}', username: 'inconnu');
      return null;
    }
    final p = principalFrom(row);
    await db.log('LOGIN', labelOf(p.bureau), username: p.username);
    return p;
  }

  static Future<bool> bureauHasAdmin(Bureau b) async {
    final rows = await AppDatabase.instance.query('users',
        where: "service_access = ? AND role = 'ADM' AND active = 1",
        whereArgs: [labelOf(b)]);
    return rows.isNotEmpty;
  }

  static Future<List<Bureau>> bureausWithoutAdmin() async => [
        for (final b in Bureau.values)
          if (!await bureauHasAdmin(b)) b
      ];

  static Future<Map<String, Object?>> _insertUser(
      Bureau bureau, String username, String password, bool admin) async {
    final err = validatePassword(password);
    final name = normalizeUsername(username);
    if (name.isEmpty) throw ArgumentError('Identifiant obligatoire.');
    if (err != null) throw ArgumentError(err);
    final values = <String, Object?>{
      'username': name,
      'password_hash': PasswordHasher.hash(password),
      'salt': '',
      'role': admin ? 'ADM' : 'Utilisateur',
      'service_access': labelOf(bureau),
      'is_first_admin': 0,
      'active': 1,
      'created_at': DateTime.now().toIso8601String(),
    };
    final id = await AppDatabase.instance.insert('users', values);
    return {...values, 'id': id};
  }

  /// Première configuration : possible UNIQUEMENT tant que le bureau n'a
  /// aucun administrateur actif. Ensuite, seul un administrateur du bureau
  /// peut créer des comptes.
  static Future<Principal> bootstrapAdmin(
      Bureau bureau, String username, String password) async {
    if (!AccessPolicy.writesEnabled) {
      throw AuthorizationException('Appareil en mode consultation : création de compte impossible.');
    }
    if (await bureauHasAdmin(bureau)) {
      throw AuthorizationException(
          'Ce bureau possède déjà un administrateur.');
    }
    final row = await _insertUser(bureau, username, password, true);
    await AppDatabase.instance.log('BOOTSTRAP_ADMIN', labelOf(bureau),
        username: '${row['username']}');
    return principalFrom(row);
  }

  static Future<void> createUser(Principal actor, String username,
      String password, {required bool admin}) async {
    AccessPolicy.require(actor, Permission.usersManage);
    await _insertUser(actor.bureau, username, password, admin);
    await AppDatabase.instance.log(
        'CREATE_USER', '${normalizeUsername(username)} ${admin ? 'admin' : 'employé'}',
        username: actor.username);
  }

  static Future<List<Map<String, Object?>>> listUsers(Principal actor) async {
    AccessPolicy.require(actor, Permission.usersManage);
    return AppDatabase.instance.query('users',
        where: 'service_access = ?',
        whereArgs: [labelOf(actor.bureau)],
        orderBy: 'username');
  }

  static Future<Map<String, Object?>> _target(Principal actor, int id) async {
    AccessPolicy.require(actor, Permission.usersManage);
    final rows = await AppDatabase.instance.query('users',
        where: 'id = ? AND service_access = ?',
        whereArgs: [id, labelOf(actor.bureau)]);
    if (rows.isEmpty) {
      throw AuthorizationException('Compte introuvable dans votre bureau.');
    }
    return rows.first;
  }

  static Future<void> setActive(Principal actor, int id, bool active) async {
    final t = await _target(actor, id);
    if (!active) {
      if (id == actor.userId) {
        throw AuthorizationException('Vous ne pouvez pas désactiver votre propre compte.');
      }
      if (t['role'] == 'ADM') {
        final admins = await AppDatabase.instance.query('users',
            where: "service_access = ? AND role = 'ADM' AND active = 1",
            whereArgs: [labelOf(actor.bureau)]);
        if (admins.length <= 1) {
          throw AuthorizationException('Impossible de désactiver le dernier administrateur du bureau.');
        }
      }
    }
    await AppDatabase.instance.update('users', {'active': active ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    await AppDatabase.instance.log(
        active ? 'ACTIVATE_USER' : 'DEACTIVATE_USER', '${t['username']}',
        username: actor.username);
  }

  static Future<void> resetPassword(
      Principal actor, int id, String newPassword) async {
    final t = await _target(actor, id);
    final err = validatePassword(newPassword);
    if (err != null) throw ArgumentError(err);
    await AppDatabase.instance.update(
        'users', {'password_hash': PasswordHasher.hash(newPassword), 'salt': ''},
        where: 'id = ?', whereArgs: [id]);
    await AppDatabase.instance.log('RESET_PASSWORD', '${t['username']}',
        username: actor.username);
  }

  static Future<void> changeOwnPassword(
      Principal me, String current, String next) async {
    if (!AccessPolicy.writesEnabled) {
      throw AuthorizationException('Appareil en mode consultation : modification impossible.');
    }
    final rows = await AppDatabase.instance
        .query('users', where: 'id = ?', whereArgs: [me.userId]);
    if (rows.isEmpty ||
        !PasswordHasher.verify(current, '${rows.first['password_hash']}')) {
      throw AuthorizationException('Mot de passe actuel incorrect.');
    }
    final err = validatePassword(next);
    if (err != null) throw ArgumentError(err);
    await AppDatabase.instance.update(
        'users', {'password_hash': PasswordHasher.hash(next)},
        where: 'id = ?', whereArgs: [me.userId]);
    await AppDatabase.instance
        .log('CHANGE_PASSWORD', '', username: me.username);
  }
}
