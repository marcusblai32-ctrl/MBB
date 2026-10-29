import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import 'permissions.dart';

/// Règle « un seul appareil enregistre les données ».
/// - principal : seul appareil autorisé à saisir/modifier des données ;
/// - consultation : lecture, rapports et exportation uniquement.
///
/// Le rôle est conservé hors de la base (SharedPreferences) : restaurer une
/// sauvegarde ne peut donc jamais transformer par accident un appareil en
/// appareil principal. Limite : sans serveur, l'application ne peut pas
/// empêcher quelqu'un d'installer une seconde copie et de la déclarer
/// principale ; la règle protège contre les erreurs, pas contre la mauvaise foi.
enum DeviceRole { principal, consultation }

class DeviceRoleStore {
  const DeviceRoleStore._();

  static const _key = 'mbb_device_role';
  static final notifier = ValueNotifier<DeviceRole>(DeviceRole.principal);
  static DeviceRole get current => notifier.value;

  /// À appeler au démarrage, avant l'ouverture de l'interface.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Installation existante ou nouvelle : appareil principal par défaut,
    // afin de ne jamais bloquer les données déjà saisies.
    final saved = prefs.getString(_key);
    _apply(saved == DeviceRole.consultation.name
        ? DeviceRole.consultation
        : DeviceRole.principal);
  }

  static Future<void> set(DeviceRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, role.name);
    _apply(role);
  }

  static void _apply(DeviceRole role) {
    notifier.value = role;
    final writable = role == DeviceRole.principal;
    AccessPolicy.writesEnabled = writable; // couche métier
    AppDatabase.readOnly = !writable; // couche données
  }
}
