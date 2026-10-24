# MBB — Mission Baptiste Béraca

Application Flutter de gestion d'église, conçue pour fonctionner hors ligne avec une base de données SQLite locale.

## Modules inclus dans cette version

- Tableau de bord avec nombre de membres, familles, cultes, recettes, dépenses et solde.
- Membres : ajout, recherche, modification et suppression.
- Familles : ajout et suppression.
- Cultes et réunions : ajout et suppression.
- Présences : marquer Présent, Absent ou Retard pour une date.
- Finances : enregistrer recettes et dépenses, consulter et supprimer les opérations.
- Paramètres : nom de l'église, nom d'application enregistré et langue.
- Sauvegarde/restauration de la base SQLite et export CSV de l'historique.
- Journal local des actions importantes.
- GitHub Actions pour construire un APK Android et un ZIP Windows.

## Prérequis

Installer Flutter stable et configurer Android SDK pour les builds locaux. Pour Windows, construire sur Windows.

## Démarrage

```bash
flutter pub get
flutter run
```

## Builds locaux

```bash
flutter build apk --release
flutter build windows --release
```

## Builds GitHub

1. Créez un dépôt GitHub privé nommé `MBB`.
2. Envoyez tous les fichiers de ce dossier à la racine du dépôt (pas le ZIP seul).
3. Ouvrez l'onglet **Actions**. Le workflow se lance sur `push` ou manuellement.
4. Téléchargez `MBB-Android-APK` ou `MBB-Windows-ZIP` dans les artefacts du workflow.

## Base de données

La base est créée automatiquement dans le répertoire privé de l'application sous le nom `mbb_database.db`. Les tables incluent `users`, `members`, `families`, `services`, `attendance`, `finance_categories`, `transactions`, `app_settings` et `audit_logs`.

Le schéma inclut une table `users`, mais cette version n'a pas encore d'écran de connexion ni de gestion des rôles utilisable. N'utilisez pas l'application comme système de sécurité de production avant d'ajouter l'authentification, les permissions et le chiffrement des sauvegardes.

## Limites à connaître

- Le nom de l'application système et l'icône ne peuvent pas être changés dynamiquement depuis l'écran Paramètres après compilation. Il faut une configuration de build pour cela.
- La sauvegarde `.db` n'est pas chiffrée.
- L'import de sauvegarde remplace la base active; après restauration, fermer puis rouvrir l'application.
- La langue est enregistrée mais la traduction complète de l'interface n'est pas encore implémentée.
- Les rapports PDF/XLSX/DOCX, les reçus financiers et la gestion avancée des familles/membres sont à compléter.
- Le test fourni est un test de fumée, pas une validation exhaustive de tous les modules.
