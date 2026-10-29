/// Autorisations appliquées dans la couche métier (et non seulement par le
/// masquage de boutons). Aucun rôle « super-administrateur » : un
/// administrateur n'a de pouvoir que dans SON bureau.
enum Bureau {
  comptabilite('Comptabilité', 'Comptabilite'),
  cartesAnnonces('Service des cartes et des annonces', 'Cartes_Annonces');

  const Bureau(this.label, this.folder);
  final String label;
  final String folder;
}

enum BureauRole { administrateur, employe }

enum Permission {
  // Comptabilité
  financeView(Bureau.comptabilite),
  financeRecord(Bureau.comptabilite),
  financeVoid(Bureau.comptabilite),
  financeReport(Bureau.comptabilite),
  financeExport(Bureau.comptabilite),
  financeImport(Bureau.comptabilite),
  // Cartes et annonces
  membersView(Bureau.cartesAnnonces),
  membersEdit(Bureau.cartesAnnonces),
  membersDelete(Bureau.cartesAnnonces),
  cardsManage(Bureau.cartesAnnonces),
  announcementsManage(Bureau.cartesAnnonces),
  attendanceManage(Bureau.cartesAnnonces),
  cardsReport(Bureau.cartesAnnonces),
  cardsExport(Bureau.cartesAnnonces),
  cardsImport(Bureau.cartesAnnonces),
  // Communes à chaque bureau, mais limitées au bureau de l'utilisateur
  usersManage(null),
  backupManage(null);

  const Permission(this.bureau);

  /// Bureau auquel la permission est rattachée ; null = s'applique au bureau
  /// de l'utilisateur seulement (gestion de ses propres comptes/sauvegardes).
  final Bureau? bureau;

  /// Vrai si l'action modifie des données (refusée sur un appareil en consultation).
  bool get isWrite => !_readPermissions.contains(this);
}

const _readPermissions = <Permission>{
  Permission.financeView,
  Permission.financeReport,
  Permission.financeExport,
  Permission.membersView,
  Permission.cardsReport,
  Permission.cardsExport,
  Permission.backupManage,
};

class Principal {
  const Principal({
    required this.userId,
    required this.username,
    required this.bureau,
    required this.role,
    this.active = true,
  });
  final int userId;
  final String username;
  final Bureau bureau;
  final BureauRole role;
  final bool active;
}

class AuthorizationException implements Exception {
  AuthorizationException(this.message);
  final String message;
  @override
  String toString() => 'AuthorizationException: $message';
}

class AccessPolicy {
  const AccessPolicy._();

  /// Faux sur un appareil en mode consultation : toute action d'écriture est refusée.
  static bool writesEnabled = true;

  static const _employeePermissions = <Permission>{
    Permission.financeView,
    Permission.financeRecord,
    Permission.financeReport,
    Permission.membersView,
    Permission.membersEdit,
    Permission.cardsManage,
    Permission.announcementsManage,
    Permission.attendanceManage,
    Permission.cardsReport,
  };

  static bool can(Principal? p, Permission permission) {
    if (p == null || !p.active) return false;
    if (permission.isWrite && !writesEnabled) return false;
    // Une permission rattachée à un bureau n'est jamais accordée à un
    // utilisateur d'un autre bureau, quel que soit son rôle.
    if (permission.bureau != null && permission.bureau != p.bureau) return false;
    switch (p.role) {
      case BureauRole.administrateur:
        return true;
      case BureauRole.employe:
        return _employeePermissions.contains(permission);
    }
  }

  static void require(Principal? p, Permission permission) {
    if (!can(p, permission)) {
      throw AuthorizationException(
          'Action non autorisée (${permission.name}).');
    }
  }
}
