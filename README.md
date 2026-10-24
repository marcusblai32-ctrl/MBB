# MBB — Mission Baptiste Béraca

Application Flutter de gestion d'église, avec interface en français et base SQLite locale pour un fonctionnement hors ligne.

## Fonctionnalités de cette version de travail

- Connexion et inscription locales avec mot de passe haché et salé.
- Le premier compte créé devient ADM ; les suivants sont des utilisateurs.
- À l'inscription, choix obligatoire entre « Services des cartes et annonces » et « Comptabilité ».
- Navigation adaptée au service choisi (le compte ADM voit les deux espaces).
- Tableau de bord, membres, familles, cultes/réunions, présences et opérations financières.
- Création dynamique des classes et groupes, sans liste de groupes imposée ; « Pastorat » peut être créé comme tout autre groupe.
- Création d'annonces avec titre, groupe concerné, description, date et signature.
- Paramètres, sauvegarde/restauration et journal local déjà présents dans le projet de base.
- Icône Android MBB générée automatiquement par le workflow.
- GitHub Actions pour générer un APK Android et un ZIP Windows contenant les fichiers de l'application.

## Construire

```bash
flutter pub get
dart run flutter_launcher_icons
flutter analyze
flutter test
flutter build apk --release
```

Sur Windows :

```bash
flutter build windows --release
```

## GitHub Actions

Pousser tous les fichiers du projet à la racine du dépôt GitHub, puis ouvrir **Actions**. Les artefacts `MBB-Android-APK` et `MBB-Windows-ZIP` seront disponibles si toutes les étapes passent.

## Important : état actuel

Ceci est une version de travail, pas encore une version de production. Les fonctionnalités suivantes restent à terminer ou à valider :

- Gestion sécurisée des comptes par ADM, y compris suppression/désactivation d'autres comptes et contrôle strict des autorisations dans toutes les actions.
- Photos des membres avec sélecteur de fichier, affichage et stockage fiable sur les deux plateformes.
- Association détaillée des membres aux familles, groupes et classes de l'école du dimanche depuis leurs fiches.
- Rapports PDF, exports Excel/Word, génération de cartes, et export PDF des annonces.
- Comptabilité complète (budgets, reçus, clôture mensuelle, rapprochement et rapports détaillés).
- Chiffrement des sauvegardes et tests complets sur Android et Windows.
- Vérification réelle de `flutter analyze`, tests et builds dans GitHub Actions : aucun résultat de compilation n'est garanti avant l'exécution du workflow.

Les données sont locales à chaque appareil dans cette version. Pour partager les mêmes données entre plusieurs utilisateurs/appareils, il faudra ensuite intégrer une API et une base de données synchronisée.


## Mise à jour — gestion des membres

Le formulaire des membres permet maintenant de sélectionner une photo depuis l'appareil, de conserver une copie dans le répertoire privé de l'application, de renseigner la famille, le statut de baptême et le rôle, et de relier le membre aux groupes/classes dynamiques existants. La classe d'école du dimanche est choisie parmi les éléments dont le type contient « classe » ou « école ».

**État honnête du projet :** cette archive est une version de travail, pas encore une livraison finale validée. L'environnement de préparation ne dispose pas du SDK Flutter/Dart pour exécuter `flutter analyze`, `flutter test` ou les builds. Il faut laisser GitHub Actions effectuer ces vérifications, puis corriger tout éventuel échec avant d'utiliser l'application avec de vraies données.
