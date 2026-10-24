# MBB — Mission Baptiste Béraca

Base Flutter initiale inspirée de la maquette visuelle fournie : tableau de bord, navigation, membres, familles, services, présences, finances, rapports, sauvegardes et personnalisation.

## Lancer localement
1. Installer Flutter et le SDK correspondant à votre système.
2. Depuis la racine : `flutter pub get`
3. Créer les plateformes si elles sont absentes : `flutter create --platforms=android,windows .`
4. Android : `flutter run`
5. Windows : `flutter run -d windows`

## Générations GitHub Actions
Envoyer le contenu du projet dans un dépôt GitHub, puis ouvrir Actions. Le workflow `Build MBB` crée les dossiers Android et Windows s'ils sont absents et publie les artefacts `MBB.apk`, `MBB-Windows.zip`. Le fichier `MBB.exe` est inclus dans le ZIP Windows.

## Important
Ceci est une base fonctionnelle de démarrage avec navigation et données de démonstration. Les modules de gestion complète, l'authentification robuste, les permissions fines, les exports réels Excel/PDF/Word et les sauvegardes chiffrées doivent être implémentés et testés avant usage avec des données réelles. Le nom et le logo dans l'interface sont configurables ; le nom et l'icône natifs installés nécessitent une reconstruction spécifique.
